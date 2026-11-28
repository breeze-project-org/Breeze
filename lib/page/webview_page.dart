import 'dart:async';
import 'dart:io';

import 'package:auto_route/annotations.dart';
import 'package:desktop_webview_linux/desktop_webview_linux.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/event/event.dart';
import 'package:zephyr/util/system/external_link.dart';
import 'package:zephyr/util/event/webview_observe_bus.dart';
import 'package:zephyr/util/ohos/platform.dart';

@RoutePage()
class WebViewPage extends StatefulWidget {
  final List<String> info;

  const WebViewPage({super.key, required this.info});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  static const Set<String> _inAppSchemes = {
    'about',
    'data',
    'file',
    'http',
    'https',
    'javascript',
  };

  Webview? _linuxWebview;
  bool _isWebviewClosed = false;

  InAppWebViewController? _controller;
  int _progress = 0;
  String? _mainFrameError;
  String? _lastObservedUrl;

  String get _title =>
      widget.info.isNotEmpty ? widget.info[0] : t.webview.title;

  String get _url => widget.info.length > 1 ? widget.info[1].trim() : '';

  Uri? get _uri {
    if (_url.isEmpty) {
      return null;
    }
    return Uri.tryParse(_url);
  }

  bool get _isValidUrl {
    final uri = _uri;
    if (uri == null) {
      return false;
    }
    return uri.hasScheme && (uri.isScheme('http') || uri.isScheme('https'));
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isLinux && _isValidUrl) {
      _openLinuxWebView();
    }
  }

  Future<void> _openLinuxWebView() async {
    final url = _url;
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(title: _title, titleBarHeight: 0),
    );

    webview.setOnUrlRequestCallback((nextUrl) {
      unawaited(
        _reportUrlChangeAndCookies(nextUrl, trigger: 'linux_url_request'),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 800), () async {
          await _reportUrlChangeAndCookies(
            nextUrl,
            trigger: 'linux_url_settled',
            force: true,
          );
        }),
      );
      return true;
    });

    _linuxWebview = webview;
    webview.launch(url);
    unawaited(
      _reportUrlChangeAndCookies(url, trigger: 'linux_launch', force: true),
    );

    webview.onClose.then((_) {
      if (mounted) {
        setState(() => _isWebviewClosed = true);
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isLinux && !_isWebviewClosed && _linuxWebview != null) {
      _linuxWebview!.close();
    }
    super.dispose();
  }

  Future<void> _openExternal(Uri uri) async {
    if (!await openExternalUrl(uri)) {
      if (!mounted) {
        return;
      }
      CalmToast.show(
        context,
        title: t.webview.cannotOpenLink(uri: uri.toString()),
        tone: CalmTone.warning,
      );
    }
  }

  Future<void> _openExternalFromRaw(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return;
    }
    await _openExternal(uri);
  }

  String get _platformTag => Platform.isLinux ? 'linux' : 'inappwebview';

  Future<void> _reportUrlChangeAndCookies(
    String? rawUrl, {
    required String trigger,
    bool force = false,
    int? statusCode,
    String? errorDescription,
  }) async {
    final url = (rawUrl ?? '').trim();
    if (url.isEmpty) {
      return;
    }
    if (!force && _lastObservedUrl == url) {
      return;
    }
    _lastObservedUrl = url;

    final cookies = await _collectAllCookieSnapshots(url);
    final event = WebViewObserveEvent(
      url: url,
      trigger: trigger,
      platform: _platformTag,
      observedAt: DateTime.now(),
      cookies: cookies,
      statusCode: statusCode,
      errorDescription: errorDescription,
    );
    WebViewObserveBus.emit(event);
    logger.d(
      '[WebViewObserve] platform=${event.platform} trigger=${event.trigger} '
      'url=${event.url} cookies=${event.cookies.length}',
    );
  }

  Future<List<WebViewCookieSnapshot>> _collectAllCookieSnapshots(
    String currentUrl,
  ) async {
    if (Platform.isLinux) {
      final webview = _linuxWebview;
      if (webview == null) {
        return const [];
      }
      try {
        final cookies = await webview.getAllCookies(allDomains: true);
        return cookies
            .map(
              (cookie) => WebViewCookieSnapshot(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expiresDate: cookie.expires?.millisecondsSinceEpoch,
                isSecure: cookie.secure,
                isHttpOnly: cookie.httpOnly,
                isSessionOnly: cookie.sessionOnly,
              ),
            )
            .toList(growable: false);
      } catch (e, stackTrace) {
        logger.e(
          '[WebViewObserve] linux getAllCookies failed',
          error: e,
          stackTrace: stackTrace,
        );
        return const [];
      }
    }

    return _collectMobileCookies(currentUrl);
  }

  Future<List<WebViewCookieSnapshot>> _collectMobileCookies(
    String currentUrl,
  ) async {
    final manager = CookieManager.instance();
    try {
      final cookies = await manager.getAllCookies();
      if (cookies.isNotEmpty) {
        return cookies
            .map(
              (cookie) => WebViewCookieSnapshot(
                name: cookie.name,
                value: '${cookie.value ?? ''}',
                domain: cookie.domain,
                path: cookie.path,
                expiresDate: cookie.expiresDate,
                isSecure: cookie.isSecure,
                isHttpOnly: cookie.isHttpOnly,
                isSessionOnly: cookie.isSessionOnly,
              ),
            )
            .toList(growable: false);
      }
    } catch (e, stackTrace) {
      logger.e(
        '[WebViewObserve] getAllCookies failed',
        error: e,
        stackTrace: stackTrace,
      );
    }

    final uri = Uri.tryParse(currentUrl);
    if (uri == null || !uri.hasScheme) {
      return const [];
    }

    try {
      final cookies = await manager.getCookies(
        url: WebUri(uri.toString()),
        webViewController: _controller,
      );
      return cookies
          .map(
            (cookie) => WebViewCookieSnapshot(
              name: cookie.name,
              value: '${cookie.value ?? ''}',
              domain: cookie.domain,
              path: cookie.path,
              expiresDate: cookie.expiresDate,
              isSecure: cookie.isSecure,
              isHttpOnly: cookie.isHttpOnly,
              isSessionOnly: cookie.isSessionOnly,
            ),
          )
          .toList(growable: false);
    } catch (e, stackTrace) {
      logger.e(
        '[WebViewObserve] getCookies(url) failed',
        error: e,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Widget _buildInvalidUrlView(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CalmEmptyState(
            icon: Icons.link_off_rounded,
            title: t.webview.invalidLink,
            subtitle: _url.isEmpty ? t.webview.emptyLink : _url,
          ),
        ),
      ),
    );
  }

  /// 主文档重载：清掉错误态并让进度条归零后重新加载。
  Future<void> _reloadMainFrame() async {
    setState(() {
      _mainFrameError = null;
      _progress = 0;
    });
    try {
      await _controller?.reload();
    } on MissingPluginException catch (e) {
      logger.w('WebView 已销毁，无法重载', error: e);
    } on PlatformException catch (e) {
      logger.w('WebView 重载失败', error: e);
    }
  }

  Widget _buildMainFrameError(BuildContext context) {
    final uri = _uri;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CalmErrorState(
                title: t.webview.loadFailed,
                errorDetail: _mainFrameError ?? t.webview.loadFailed,
                errorDetailMaxLines: 2,
                primaryLabel: t.webview.retry,
                onPrimary: _reloadMainFrame,
              ),
              if (uri != null) ...[
                const SizedBox(height: 10),
                CalmButton(
                  label: t.webview.openInExternalBrowser,
                  icon: Icons.open_in_browser_rounded,
                  variant: CalmButtonVariant.secondary,
                  onPressed: () => _openExternal(uri),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinuxBody(BuildContext context) {
    final c = context.calm;
    final closed = _isWebviewClosed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: closed ? c.successSoft : c.accentSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(
                closed ? Icons.check_rounded : Icons.open_in_new_rounded,
                size: 26,
                color: closed ? c.success : c.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              closed
                  ? t.webview.windowClosed
                  : t.webview.openedInExternalWindow,
              textAlign: TextAlign.center,
              textHeightBehavior: kCalmTextHeightBehavior,
              strutStyle: calmStrut(14.5),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: c.text,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                _url,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, height: 1.5, color: c.text3),
              ),
            ),
            if (closed) ...[
              const SizedBox(height: 20),
              CalmButton(
                label: t.webview.back,
                icon: Icons.arrow_back_rounded,
                variant: CalmButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    if (!_isValidUrl) {
      return _buildInvalidUrlView(context);
    }

    if (_mainFrameError != null) {
      return _buildMainFrameError(context);
    }

    final webUri = WebUri(_url);

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: webUri),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            isInspectable: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            cacheEnabled: true,
            transparentBackground: false,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
            // Android 15/16 + 部分机型使用 Hybrid Composition 可能出现白屏。
            useHybridComposition: false,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
          },
          onLoadStart: (_, url) {
            if (mounted) {
              setState(() {
                _mainFrameError = null;
              });
            }
            unawaited(
              _reportUrlChangeAndCookies(
                url?.toString(),
                trigger: 'load_start',
              ),
            );
          },
          onLoadStop: (_, url) {
            unawaited(
              _reportUrlChangeAndCookies(
                url?.toString(),
                trigger: 'load_stop',
                force: true,
              ),
            );
          },
          onUpdateVisitedHistory: (_, url, _) {
            unawaited(
              _reportUrlChangeAndCookies(
                url?.toString(),
                trigger: 'history_changed',
              ),
            );
          },
          onProgressChanged: (_, progress) {
            if (mounted) {
              setState(() {
                _progress = progress.clamp(0, 100).toInt();
              });
            }
          },
          shouldOverrideUrlLoading: (_, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri == null) {
              return NavigationActionPolicy.ALLOW;
            }
            if (!_inAppSchemes.contains(uri.scheme)) {
              await _openExternalFromRaw(uri.toString());
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame != true) {
              return;
            }
            unawaited(
              _reportUrlChangeAndCookies(
                request.url.toString(),
                trigger: 'load_error',
                force: true,
                errorDescription: '${error.type}: ${error.description}',
              ),
            );
            if (mounted) {
              setState(() {
                _mainFrameError = t.webview.loadError(
                  error: '${error.type} / ${error.description}',
                );
              });
            }
          },
          onReceivedHttpError: (_, request, response) {
            if (request.isForMainFrame != true) {
              return;
            }
            unawaited(
              _reportUrlChangeAndCookies(
                request.url.toString(),
                trigger: 'http_error',
                force: true,
                statusCode: response.statusCode,
                errorDescription: response.reasonPhrase,
              ),
            );
            if (mounted) {
              setState(() {
                _mainFrameError = t.webview.httpErrorStatus(
                  statusCode: response.statusCode.toString(),
                );
              });
            }
          },
        ),
        if (_progress < 100)
          Align(
            alignment: Alignment.topCenter,
            child: CalmProgressBar(value: _progress / 100, height: 3),
          ),
      ],
    );
  }

  Widget _buildUnsupportedView(BuildContext context) {
    final c = context.calm;
    return CalmPageScaffold(
      title: _title,
      maxContentWidth: 480,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.public_off_rounded, size: 26, color: c.text3),
              ),
              const SizedBox(height: 14),
              Text(
                '当前平台暂不支持内置网页视图\n'
                'WebView is not available on this platform',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.6, color: c.text2),
              ),
              if (_url.isNotEmpty) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SelectableText(
                    _url,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: c.text3),
                  ),
                ),
                const SizedBox(height: 16),
                CalmButton(
                  label: t.webview.openInExternalBrowser,
                  icon: Icons.open_in_browser_rounded,
                  variant: CalmButtonVariant.primary,
                  onPressed: () => _openExternal(Uri.parse(_url)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isOhos) {
      return _buildUnsupportedView(context);
    }
    final uri = _uri;

    return CalmPageScaffold(
      title: _title,
      maxContentWidth: null,
      actions: <Widget>[
        if (Platform.isLinux && !_isWebviewClosed)
          CalmIconButton(
            icon: Icons.close_rounded,
            tooltip: t.webview.closeWindow,
            onPressed: () {
              _linuxWebview?.close();
              if (mounted) {
                setState(() => _isWebviewClosed = true);
              }
            },
          ),
        if (uri != null)
          CalmIconButton(
            icon: Icons.open_in_browser_rounded,
            tooltip: t.webview.openInExternalBrowser,
            onPressed: () => _openExternal(uri),
          ),
      ],
      body: Platform.isLinux
          ? _buildLinuxBody(context)
          : _buildMobileBody(context),
    );
  }
}
