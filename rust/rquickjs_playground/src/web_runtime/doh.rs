//! DoH（DNS over HTTPS）解析：给 reqwest 提供自定义 [`Resolve`]。
//!
//! # 为什么要有这个模块
//!
//! 墙内直连时 UDP/53 会被污染（`picaapi.picacomic.com` 会解析到
//! `174.37.154.236` 这类假 IP），而 Cloudflare / Google 的 DoH 端点
//! （`1.1.1.1`、`dns.google`）本身又被黑洞。国内两家公共 DoH 都是可达的，
//! 而且会**原样返回** `HTTPS`(type 65) 记录里的 `ech=` / `ipv4hint=`——
//! ECH 需要的两样东西它们都有，所以拿它们同时当通用解析器和 ECH 引导。
//!
//! # 四家并发，谁先答用谁
//!
//! ```text
//! AliDNS ┐
//! DNSPod ┴─ 同时发，第一个有效答案胜出
//! Cloudflare ┐
//! Google     ┘
//! 全灭 → 系统解析（getaddrinfo）
//! ```
//!
//! 结构化并发：四家都在当前任务里跑（`FuturesUnordered`），胜出的瞬间其余
//! future 直接 drop（同步取消），没有 spawn / abort 的时序问题。
//!
//! 墙内直连时 CF / Google 是黑洞，它们的查询会「发出去但永远不回」——代价只是
//! 每个 DNS miss 多两个 SYN，国内任一家 200ms 答上来就立刻取消，不影响延迟。
//! 反过来，TUN / 代理 / 海外网络里 CF 和 Google 往往更快，并发才能吃到这个好处。
//!
//! # TUN 模式（Clash / mihomo / sing-box）
//!
//! TUN 在 IP 层劫持流量，三条路径的表现各不相同：
//!
//! - **DoH 本身**：连的是 `223.6.6.6:443` / `1.12.12.12:443`（IP 字面量），
//!   不走 DNS，TUN 按 IP 规则路由。多数配置里国内 DNS 走 DIRECT；被 REJECT
//!   就熔断 → 系统解析（TUN 的 fake-ip），仍然可用。
//! - **普通请求**：DoH 返回的是真 IP（不是 fake-ip），TUN 靠 sniff SNI / Host
//!   匹配域名规则，行为正常。
//! - **ECH**：外层 SNI 是 `cloudflare-ech.com`，sniffer 看不到真实域名，只能
//!   按 IP 规则路由。若规则集只有域名规则、`MATCH` 又是 DIRECT，ECH 连接可能
//!   直连被墙——`http.rs` 里 ECH 失败会用普通链路重试一次（带真实 SNI），
//!   最坏多花一次握手，不会卡死。
//!
//! 另外 fake-ip 默认段 `198.18.0.0/15` 不在 `is_private_or_local_ip` 里，
//! 所以 `allow_private_network = false` 也不会误拦；只有把 fake-ip 段改成
//! 内网段（如 `10.x`）才会被当成内网请求拒掉。
//!
//! # 三条硬约束（都是踩过的坑）
//!
//! 1. **DoH 失败必须回落系统解析**：DoH 只是「更好的 DNS」，不是必需品。
//!    查不到就退回 `getaddrinfo`，不能让 DoH 挂掉把整个网络打死。
//! 2. **必须熔断**：单个服务商连续失败 [`DOH_FAILURE_THRESHOLD`] 次后
//!    [`DOH_COOLDOWN`] 内直接跳过它，否则每个请求都要白等一次超时。
//! 3. **HTTPS RR 必须缓存**：ECH 配置是在请求路径上取的，正缓存
//!    [`HTTPS_RR_POSITIVE_TTL`]、负缓存 [`HTTPS_RR_NEGATIVE_TTL`] / [`HTTPS_RR_EMPTY_TTL`]，
//!    绝不能让 DoH 阻塞请求（之前 8s × 2 端点直接把 10s 的 axios 超时耗光）。
//!
//! # 与代理的关系
//!
//! hickory 的 DoH 连接不走 reqwest 的代理配置（它是独立 HTTP/2 客户端）。
//! 所以**配了代理时宿主干脆不挂 DoH**：域名直接交给代理（CONNECT / `socks5h`），
//! 客户端不需要解析；ECH 那边也会跳过 DoH，缺 ECHConfig 就回落普通链路。
//! 这样「加了 DoH 反而让代理用户用不了」的情况不会发生。

use std::collections::HashMap;
use std::future::Future;
use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use futures_util::stream::{FuturesUnordered, StreamExt};
use hickory_resolver::TokioResolver;
use hickory_resolver::config::{
    ConnectionConfig, LookupIpStrategy, NameServerConfig, ResolverConfig, ResolverOpts,
};
use hickory_resolver::net::NetError;
use hickory_resolver::net::runtime::TokioRuntimeProvider;
use hickory_resolver::proto::rr::rdata::A;
use hickory_resolver::proto::rr::rdata::svcb::{SvcParamKey, SvcParamValue};
use hickory_resolver::proto::rr::{RData, RecordType};
use reqwest::dns::{Addrs, Name, Resolve, Resolving};
use tokio::time::timeout;

/// DoH 查询路径（RFC 8484 wireformat）。
const DOH_PATH: &str = "/dns-query";
/// 单个服务商的查询超时（hickory 内部超时，也是并发抢答时的等待上限）。
const DOH_QUERY_TIMEOUT: Duration = Duration::from_millis(1500);
/// 整轮并发的总预算：超过这个时间就当四家全灭，回落系统解析。
const DOH_RACE_TIMEOUT: Duration = Duration::from_millis(1600);
/// 单个服务商连续失败多少次后熔断。
const DOH_FAILURE_THRESHOLD: u32 = 3;
/// 熔断后多久再试一次。
const DOH_COOLDOWN: Duration = Duration::from_secs(60);
/// HTTPS RR 正缓存（Cloudflare 的 TTL 是 300s）。
const HTTPS_RR_POSITIVE_TTL: Duration = Duration::from_secs(300);
/// HTTPS RR 负缓存：一家都没答上来时，60s 内不再重试。
const HTTPS_RR_NEGATIVE_TTL: Duration = Duration::from_secs(60);
/// HTTPS RR 空缓存：DNS 答了但没有 `ech`，10 分钟内不再问（换家也是同样答案）。
const HTTPS_RR_EMPTY_TTL: Duration = Duration::from_secs(600);

/// 一个 DoH 服务商。
struct DohProvider {
    /// 日志里用的名字。
    label: &'static str,
    /// `(IP 字面量, TLS server_name)`。
    ///
    /// 用 IP 而不是域名，避免「解析 DoH 域名」这个先有鸡还是先有蛋的问题；
    /// `server_name` 只用于 TLS 证书校验。
    servers: &'static [(&'static str, &'static str)],
    /// 懒构建的解析器（首次在 tokio 上下文里用到时才建）。
    resolver: OnceLock<TokioResolver>,
    /// 连续失败计数。
    failures: AtomicU32,
    /// 熔断截止时间（unix 毫秒），0 表示未熔断。
    disabled_until_ms: AtomicU64,
}

impl DohProvider {
    const fn new(label: &'static str, servers: &'static [(&'static str, &'static str)]) -> Self {
        Self {
            label,
            servers,
            resolver: OnceLock::new(),
            failures: AtomicU32::new(0),
            disabled_until_ms: AtomicU64::new(0),
        }
    }

    /// 当前是否允许尝试这家（熔断期内直接跳过）。
    fn usable(&self) -> bool {
        now_ms() >= self.disabled_until_ms.load(Ordering::Acquire)
    }

    /// 取（必要时构建）解析器。`&'static self`：服务商表本身是 `static`，
    /// 拿到的引用可以跨 await / 跨任务用。
    fn resolver(&'static self) -> Option<&'static TokioResolver> {
        if let Some(resolver) = self.resolver.get() {
            return Some(resolver);
        }

        let mut name_servers = Vec::with_capacity(self.servers.len());
        for (ip, server_name) in self.servers {
            let Ok(ip) = ip.parse::<IpAddr>() else {
                continue;
            };
            name_servers.push(NameServerConfig::new(
                ip,
                true,
                vec![ConnectionConfig::https(
                    Arc::from(*server_name),
                    Some(Arc::from(DOH_PATH)),
                )],
            ));
        }
        if name_servers.is_empty() {
            return None;
        }

        let mut options = ResolverOpts::default();
        options.timeout = DOH_QUERY_TIMEOUT;
        options.attempts = 1;
        // 同一家的多个 IP 并发查：谁先答用谁，黑洞 IP 不会拖慢整体。
        options.num_concurrent_reqs = 2;
        options.ip_strategy = LookupIpStrategy::Ipv4AndIpv6;
        options.cache_size = 512;

        let resolver = match TokioResolver::builder_with_config(
            ResolverConfig::from_name_servers(name_servers),
            TokioRuntimeProvider::default(),
        )
        .with_options(options)
        .build()
        {
            Ok(resolver) => resolver,
            Err(error) => {
                tracing::warn!("doh: failed to build {} resolver: {error}", self.label);
                return None;
            }
        };

        // 并发首次初始化时可能被别人抢先写入，`set` 失败也无所谓，取已有的即可。
        let _ = self.resolver.set(resolver);
        self.resolver.get()
    }

    fn note_success(&self) {
        self.failures.store(0, Ordering::Release);
    }

    /// 记一次结果：能拿到 DNS 响应（NXDOMAIN / SERVFAIL 等）说明链路是通的，
    /// 只有连接层的失败才算故障，否则一个不存在的域名就能把 DoH 熔断掉。
    fn note_outcome(&self, error: &NetError) {
        if matches!(error, NetError::Dns(_)) {
            self.note_success();
        } else {
            self.note_failure(error);
        }
    }

    fn note_failure(&self, error: &NetError) {
        let failures = self.failures.fetch_add(1, Ordering::AcqRel) + 1;
        if failures >= DOH_FAILURE_THRESHOLD {
            let until = now_ms() + DOH_COOLDOWN.as_millis() as u64;
            self.disabled_until_ms.store(until, Ordering::Release);
            tracing::warn!(
                "doh: {} failed {failures} times in a row ({error}), skipping it for {}s",
                self.label,
                DOH_COOLDOWN.as_secs()
            );
        }
    }
}

/// 四家一起抢答。顺序只影响「同时答上来」时的先后（`FuturesUnordered` 按完成顺序）。
static PROVIDERS: [DohProvider; 4] = [
    // 国内：墙内直连可达，而且原样返回 `ech=`。
    DohProvider::new(
        "alidns",
        &[
            ("223.6.6.6", "dns.alidns.com"),
            ("223.5.5.5", "dns.alidns.com"),
        ],
    ),
    DohProvider::new(
        "doh.pub",
        &[("1.12.12.12", "doh.pub"), ("120.53.53.53", "doh.pub")],
    ),
    // 国外：墙内直连基本不可达，但 TUN / 代理 / 海外网络里往往最快。
    DohProvider::new(
        "cloudflare",
        &[
            ("1.1.1.1", "cloudflare-dns.com"),
            ("1.0.0.1", "cloudflare-dns.com"),
        ],
    ),
    DohProvider::new(
        "google",
        &[("8.8.8.8", "dns.google"), ("8.8.4.4", "dns.google")],
    ),
];

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

/// 四家并发查，谁先答用谁。
///
/// 结构化并发：所有查询都在**当前任务**里跑（`FuturesUnordered`），谁先答就返回，
/// 剩下的随它一起 drop 掉——同步取消，没有 `spawn` / `abort` 的时序问题，
/// 也不需要 `'static + Send` 的约束。
///
/// 闭包返回 `Ok(Some(v))` 表示拿到结果，`Ok(None)` 表示「答了但没有需要的记录」，
/// `Err(NetError::Dns(_))` 表示拿到了确定答案（NXDOMAIN 等），换家也没用。
async fn race_providers<T, F, Fut>(providers: &'static [DohProvider], query: &F) -> Option<T>
where
    F: Fn(&'static TokioResolver) -> Fut,
    Fut: Future<Output = Result<Option<T>, NetError>>,
{
    let mut pending = FuturesUnordered::new();
    for provider in providers {
        if !provider.usable() {
            continue;
        }
        let Some(resolver) = provider.resolver() else {
            continue;
        };
        let future = query(resolver);
        pending.push(async move { (provider, future.await) });
    }

    let deadline = Instant::now() + DOH_RACE_TIMEOUT;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        match timeout(remaining, pending.next()).await {
            Ok(Some((provider, Ok(Some(value))))) => {
                provider.note_success();
                return Some(value);
            }
            Ok(Some((provider, Ok(None)))) => {
                // 有 DNS 响应但没我们要的记录：链路是通的，继续等其它家。
                provider.note_success();
            }
            Ok(Some((provider, Err(error)))) => {
                provider.note_outcome(&error);
                if matches!(error, NetError::Dns(_)) {
                    // NXDOMAIN 之类是确定答案，换家也没用。
                    return None;
                }
            }
            // 所有服务商都结束了。
            Ok(None) => break,
            // 整体超时。
            Err(_) => break,
        }
    }
    None
}

/// 四家并发查，全灭返回 `None`（调用方回落系统解析）。
async fn resolve_via_providers<T, F, Fut>(query: F) -> Option<T>
where
    F: Fn(&'static TokioResolver) -> Fut,
    Fut: Future<Output = Result<Option<T>, NetError>>,
{
    race_providers(&PROVIDERS, &query).await
}

/// reqwest 的自定义解析器：先 DoH（国内 → 国外），全失败回落系统解析。
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct DohResolver;

impl Resolve for DohResolver {
    fn resolve(&self, name: Name) -> Resolving {
        let host = name.as_str().to_string();
        Box::pin(async move {
            let query = |resolver: &'static TokioResolver| {
                let host = host.clone();
                async move {
                    let lookup = resolver.lookup_ip(host.as_str()).await?;
                    let addrs: Vec<SocketAddr> =
                        lookup.iter().map(|ip| SocketAddr::new(ip, 0)).collect();
                    Ok((!addrs.is_empty()).then_some(addrs))
                }
            };

            if let Some(addrs) = resolve_via_providers(query).await {
                return Ok(Box::new(addrs.into_iter()) as Addrs);
            }

            // 回落系统解析：内网域名、hosts 里写死的域名、DoH 不可用时都靠它。
            let addrs: Vec<SocketAddr> =
                tokio::net::lookup_host((host.as_str(), 0)).await?.collect();
            Ok(Box::new(addrs.into_iter()) as Addrs)
        })
    }
}

/// `HTTPS` RR 的查询结论。
enum HttpsRrLookup {
    /// 拿到了 ECHConfig 与 ipv4hint。
    Found(Vec<u8>, Vec<String>),
    /// DNS 答了，但没有 `ech`（域名没配 ECH，或者被中间设备裁剪）。
    Answered,
}

/// HTTPS RR 缓存项。`value` 为 `None` 表示负缓存（查过但没拿到）。
struct HttpsRrCacheEntry {
    expires_at: Instant,
    value: Option<(Vec<u8>, Vec<String>)>,
}

static HTTPS_RR_CACHE: LazyLock<Mutex<HashMap<String, HttpsRrCacheEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// 缓存上限：ECH 域名通常个位数，超过就顺手清一遍过期项。
const HTTPS_RR_CACHE_LIMIT: usize = 256;

fn cache_get(host: &str) -> Option<Option<(Vec<u8>, Vec<String>)>> {
    let guard = HTTPS_RR_CACHE.lock().ok()?;
    let entry = guard.get(host)?;
    if entry.expires_at <= Instant::now() {
        return None;
    }
    Some(entry.value.clone())
}

fn cache_put(host: &str, ttl: Duration, value: Option<(Vec<u8>, Vec<String>)>) {
    let Ok(mut guard) = HTTPS_RR_CACHE.lock() else {
        return;
    };
    if guard.len() >= HTTPS_RR_CACHE_LIMIT {
        let now = Instant::now();
        guard.retain(|_, entry| entry.expires_at > now);
    }
    guard.insert(
        host.to_string(),
        HttpsRrCacheEntry {
            expires_at: Instant::now() + ttl,
            value,
        },
    );
}

/// 查 `HTTPS`(type 65) 记录，返回 `(ECHConfigList 原始字节, ipv4hint)`。
///
/// 带正/负缓存，请求路径上可以直接调用：命中缓存时只是一次 mutex 读。
pub(crate) async fn lookup_https_rr(host: &str) -> Option<(Vec<u8>, Vec<String>)> {
    let host = host.trim().trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }
    if let Some(cached) = cache_get(&host) {
        return cached;
    }

    let query = |resolver: &'static TokioResolver| {
        let host = host.clone();
        async move {
            let lookup = resolver.lookup(host.as_str(), RecordType::HTTPS).await?;
            Ok(lookup
                .answers()
                .iter()
                .find_map(|record| extract_https_params(&record.data))
                .map(|(ech, ips)| HttpsRrLookup::Found(ech, ips))
                .or(Some(HttpsRrLookup::Answered)))
        }
    };

    let (ttl, value) = match resolve_via_providers(query).await {
        Some(HttpsRrLookup::Found(ech, ips)) => (HTTPS_RR_POSITIVE_TTL, Some((ech, ips))),
        // 有 DNS 响应但没 ech：换家也是同样答案，缓存久一点，别每次请求都重查。
        Some(HttpsRrLookup::Answered) => (HTTPS_RR_EMPTY_TTL, None),
        None => (HTTPS_RR_NEGATIVE_TTL, None),
    };
    cache_put(&host, ttl, value.clone());
    value
}

/// 从 `HTTPS` RR 里取 `ech=` 与 `ipv4hint=`。
///
/// 只认 ServiceMode（`svc_priority > 0`）；AliasMode（priority 0）没有参数。
fn extract_https_params(rdata: &RData) -> Option<(Vec<u8>, Vec<String>)> {
    let RData::HTTPS(https) = rdata else {
        return None;
    };
    if https.svc_priority == 0 {
        return None;
    }

    let mut ech = None;
    let mut ips = Vec::new();
    for (key, value) in &https.svc_params {
        match (key, value) {
            (SvcParamKey::EchConfigList, SvcParamValue::EchConfigList(list)) => {
                // 含 2 字节冗余长度前缀，正好是 `rustls::pki_types::EchConfigListBytes` 要的格式。
                ech = Some(list.0.clone());
            }
            (SvcParamKey::Ipv4Hint, SvcParamValue::Ipv4Hint(hints)) => {
                ips.extend(hints.0.iter().map(|A(ip)| ip.to_string()));
            }
            _ => {}
        }
    }
    ech.map(|ech| (ech, ips))
}

#[cfg(test)]
mod tests {
    use super::*;
    use hickory_resolver::proto::rr::Name;
    use hickory_resolver::proto::rr::rdata::HTTPS;
    use hickory_resolver::proto::rr::rdata::svcb::{EchConfigList, IpHint, SVCB};
    use std::net::Ipv4Addr;

    fn https_rdata(priority: u16, params: Vec<(SvcParamKey, SvcParamValue)>) -> RData {
        RData::HTTPS(HTTPS(SVCB::new(priority, Name::root(), params)))
    }

    #[test]
    fn extracts_ech_and_ipv4_hint() {
        let rdata = https_rdata(
            1,
            vec![
                (
                    SvcParamKey::EchConfigList,
                    SvcParamValue::EchConfigList(EchConfigList(vec![0xfe, 0x0d, 0x00, 0x01])),
                ),
                (
                    SvcParamKey::Ipv4Hint,
                    SvcParamValue::Ipv4Hint(IpHint(vec![
                        A(Ipv4Addr::new(104, 21, 86, 93)),
                        A(Ipv4Addr::new(172, 67, 217, 104)),
                    ])),
                ),
            ],
        );
        let (ech, ips) = extract_https_params(&rdata).expect("should extract");
        assert_eq!(ech, vec![0xfe, 0x0d, 0x00, 0x01]);
        assert_eq!(ips, vec!["104.21.86.93", "172.67.217.104"]);
    }

    #[test]
    fn ignores_alias_mode_and_missing_ech() {
        assert!(extract_https_params(&https_rdata(0, vec![])).is_none());
        let no_ech = https_rdata(
            1,
            vec![(
                SvcParamKey::Ipv4Hint,
                SvcParamValue::Ipv4Hint(IpHint(vec![A(Ipv4Addr::new(1, 2, 3, 4))])),
            )],
        );
        assert!(extract_https_params(&no_ech).is_none());
    }

    #[test]
    fn providers_cover_domestic_and_overseas() {
        let labels: Vec<&str> = PROVIDERS.iter().map(|provider| provider.label).collect();
        assert_eq!(labels, vec!["alidns", "doh.pub", "cloudflare", "google"]);
        for provider in PROVIDERS.iter() {
            assert!(!provider.servers.is_empty());
        }
    }

    /// 诊断用：逐家打印结果（墙内 CF / Google 预期失败，不算测试失败）。
    /// `cargo test -- --ignored --nocapture doh_providers_live_smoke`
    #[tokio::test]
    #[ignore]
    async fn doh_providers_live_smoke() {
        for provider in PROVIDERS.iter() {
            let Some(resolver) = provider.resolver() else {
                println!("{}: resolver build failed", provider.label);
                continue;
            };
            match timeout(
                DOH_QUERY_TIMEOUT,
                resolver.lookup("picaapi.part26.art", RecordType::HTTPS),
            )
            .await
            {
                Ok(Ok(lookup)) => {
                    let found = lookup
                        .answers()
                        .iter()
                        .find_map(|record| extract_https_params(&record.data));
                    match found {
                        Some((ech, ips)) => {
                            println!("{}: ech_len={} ips={ips:?}", provider.label, ech.len())
                        }
                        None => println!("{}: answered without ech", provider.label),
                    }
                }
                Ok(Err(error)) => println!("{}: {error}", provider.label),
                Err(_) => println!("{}: timed out", provider.label),
            }
        }
    }

    /// 联网冒烟：四家并发 → 系统解析，应能拿到 ECHConfig。
    /// `cargo test -- --ignored --nocapture doh_live_smoke`
    #[tokio::test]
    #[ignore]
    async fn doh_live_smoke() {
        let (ech, ips) = lookup_https_rr("picaapi.part26.art")
            .await
            .expect("chain should return ech");
        println!("chain: ech_len={} ips={ips:?}", ech.len());
        assert!(ech.len() > 8);
        assert!(!ips.is_empty());
    }
}
