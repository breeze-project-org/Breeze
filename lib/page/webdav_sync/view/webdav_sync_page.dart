import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:markdown_widget/widget/markdown_block.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/webdav_sync/webdav_sync.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/widgets/dialog.dart';
import 'package:zephyr/util/event/event.dart';

@RoutePage()
class WebDavSyncPage extends StatefulWidget {
  const WebDavSyncPage({super.key});

  @override
  State<WebDavSyncPage> createState() => _WebDavSyncPageState();
}

class _WebDavSyncPageState extends State<WebDavSyncPage> {
  final TextEditingController _webdavHost = TextEditingController();
  final TextEditingController _webdavUsername = TextEditingController();
  final TextEditingController _webdavPassword = TextEditingController();
  final TextEditingController _s3Endpoint = TextEditingController();
  final TextEditingController _s3AccessKey = TextEditingController();
  final TextEditingController _s3SecretKey = TextEditingController();
  final TextEditingController _s3Bucket = TextEditingController();
  final TextEditingController _s3Region = TextEditingController();
  final TextEditingController _s3Port = TextEditingController();
  bool _s3UseSSL = true;
  bool _s3PathStyle = false;

  @override
  void initState() {
    super.initState();
    final settings = globalSetting;
    _webdavHost.text = settings.syncSetting.webdavSetting.host;
    _webdavUsername.text = settings.syncSetting.webdavSetting.username;
    _webdavPassword.text = settings.syncSetting.webdavSetting.password;
    _s3Endpoint.text = settings.syncSetting.s3Setting.endpoint;
    _s3AccessKey.text = settings.syncSetting.s3Setting.accessKey;
    _s3SecretKey.text = settings.syncSetting.s3Setting.secretKey;
    _s3Bucket.text = settings.syncSetting.s3Setting.bucket;
    _s3Region.text = settings.syncSetting.s3Setting.region;
    _s3Port.text = settings.syncSetting.s3Setting.port > 0
        ? settings.syncSetting.s3Setting.port.toString()
        : '';
    _s3UseSSL = settings.syncSetting.s3Setting.useSSL;
    _s3PathStyle = settings.syncSetting.s3Setting.pathStyle;
  }

  @override
  void dispose() {
    _webdavHost.dispose();
    _webdavUsername.dispose();
    _webdavPassword.dispose();
    _s3Endpoint.dispose();
    _s3AccessKey.dispose();
    _s3SecretKey.dispose();
    _s3Bucket.dispose();
    _s3Region.dispose();
    _s3Port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final globalSettingCubit = context.watch<GlobalSettingCubit>();
    final syncServiceType =
        globalSettingCubit.state.syncSetting.syncServiceType;
    final title = syncServiceType == SyncServiceType.none
        ? t.webdavSync.title
        : t.webdavSync.serviceTitle(service: syncServiceType.label);

    return SettingPageShell(
      title: title,
      subtitle: t.settings.syncConfigSubtitle,
      child: ListView(
        padding: kSettingPagePadding,
        children: <Widget>[
          if (syncServiceType == SyncServiceType.none) ...[
            _buildNoneTip(),
          ] else if (syncServiceType == SyncServiceType.webdav) ...[
            _buildWebDavForm(),
          ] else ...[
            _buildS3Form(),
          ],
          if (syncServiceType != SyncServiceType.none) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                CalmButton(
                  label: t.webdavSync.deleteConfig,
                  icon: Icons.delete_outline_rounded,
                  variant: CalmButtonVariant.danger,
                  onPressed: () => _clearConfig(syncServiceType),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: CalmButton(
                      label: t.webdavSync.testAndSave,
                      icon: Icons.cloud_done_outlined,
                      variant: CalmButtonVariant.primary,
                      onPressed: () => _testAndSave(syncServiceType),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: CalmButton(
              label: t.webdavSync.faq,
              icon: Icons.help_outline_rounded,
              variant: CalmButtonVariant.ghost,
              onPressed: () => _showQA(context),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNoneTip() {
    return CalmEmptyState(
      icon: Icons.cloud_off_rounded,
      title: t.webdavSync.noneTip,
      subtitle: t.settings.syncServiceSubtitle,
    );
  }

  Widget _buildWebDavForm() {
    return CalmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fieldLabel(t.webdavSync.webdavHost),
          CalmTextField(
            controller: _webdavHost,
            hintText: t.webdavSync.webdavHost,
            prefixIcon: Icons.cloud_outlined,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 14),
          _fieldLabel(t.webdavSync.username),
          CalmTextField(
            controller: _webdavUsername,
            hintText: t.webdavSync.username,
            prefixIcon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 14),
          _fieldLabel(t.webdavSync.password),
          CalmTextField(
            controller: _webdavPassword,
            hintText: t.webdavSync.password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
          ),
        ],
      ),
    );
  }

  Widget _buildS3Form() {
    return CalmCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel(t.webdavSync.s3Endpoint),
                CalmTextField(
                  controller: _s3Endpoint,
                  hintText: t.webdavSync.s3EndpointHint,
                  prefixIcon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                _fieldLabel('Access Key'),
                CalmTextField(
                  controller: _s3AccessKey,
                  hintText: 'Access Key',
                  prefixIcon: Icons.vpn_key_outlined,
                ),
                const SizedBox(height: 14),
                _fieldLabel('Secret Key'),
                CalmTextField(
                  controller: _s3SecretKey,
                  hintText: 'Secret Key',
                  prefixIcon: Icons.password_rounded,
                  obscureText: true,
                ),
                const SizedBox(height: 14),
                _fieldLabel(t.webdavSync.s3Bucket),
                CalmTextField(
                  controller: _s3Bucket,
                  hintText: t.webdavSync.s3Bucket,
                  prefixIcon: Icons.folder_outlined,
                ),
                const SizedBox(height: 14),
                _fieldLabel(t.webdavSync.s3Region),
                CalmTextField(
                  controller: _s3Region,
                  hintText: t.webdavSync.s3Region,
                  prefixIcon: Icons.public_rounded,
                ),
                const SizedBox(height: 14),
                _fieldLabel(t.webdavSync.s3Port),
                CalmTextField(
                  controller: _s3Port,
                  hintText: t.webdavSync.s3Port,
                  prefixIcon: Icons.numbers_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: CalmDivider(),
          ),
          settingSwitchTile(
            icon: Icons.lock_rounded,
            title: t.webdavSync.useSsl,
            value: _s3UseSSL,
            onChanged: (value) {
              setState(() {
                _s3UseSSL = value;
              });
            },
          ),
          settingSwitchTile(
            icon: Icons.route_outlined,
            title: t.webdavSync.pathStyle,
            subtitle: t.webdavSync.pathStyleSubtitle,
            value: _s3PathStyle,
            onChanged: (value) {
              setState(() {
                _s3PathStyle = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, color: context.calm.text2),
      ),
    );
  }

  void _testAndSave(SyncServiceType syncServiceType) async {
    if (syncServiceType == SyncServiceType.webdav) {
      await _testWebDavServer();
      return;
    }

    if (syncServiceType == SyncServiceType.s3) {
      await _testS3Server();
    }
  }

  void _clearConfig(SyncServiceType syncServiceType) {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    globalSettingCubit.resetState((current, defaults) {
      if (syncServiceType == SyncServiceType.webdav) {
        return current.copyWith(
          syncSetting: current.syncSetting.copyWith(
            webdavSetting: defaults.syncSetting.webdavSetting,
            syncSettings: false,
          ),
        );
      }

      if (syncServiceType == SyncServiceType.s3) {
        return current.copyWith(
          syncSetting: current.syncSetting.copyWith(
            s3Setting: defaults.syncSetting.s3Setting,
            syncSettings: false,
          ),
        );
      }

      return current;
    });

    if (syncServiceType == SyncServiceType.webdav) {
      _webdavHost.clear();
      _webdavUsername.clear();
      _webdavPassword.clear();
    } else if (syncServiceType == SyncServiceType.s3) {
      _s3Endpoint.clear();
      _s3AccessKey.clear();
      _s3SecretKey.clear();
      _s3Bucket.clear();
      _s3Region.clear();
      _s3Port.clear();
      setState(() {
        _s3UseSSL = true;
      });
    }
  }

  /// 显示不可中断的连接中弹窗，返回「精确关闭该弹窗」的回调。
  ///
  /// 关闭动作使用弹窗自身的 BuildContext（由 bodyBuilder 捕获），因此
  /// `Navigator.of(ctx).pop()` 只会 pop 掉弹窗路由，绝不会误关本页。
  VoidCallback _showConnectingDialog(String message) {
    BuildContext? dialogContext;
    showCalmDialog<void>(
      context,
      title: message,
      icon: Icons.cloud_sync_outlined,
      barrierDismissible: false,
      preventPop: true,
      bodyBuilder: (ctx) {
        dialogContext = ctx;
        return const CalmProgressBar(height: 5);
      },
    );
    return () {
      final ctx = dialogContext;
      if (ctx == null || !ctx.mounted) return;
      Navigator.of(ctx).pop();
    };
  }

  Future<void> _testWebDavServer() async {
    final closeLoading = _showConnectingDialog(t.webdavSync.connectingWebdav);

    try {
      await testWebDavServer(
        _webdavHost.text.trim(),
        _webdavUsername.text.trim(),
        _webdavPassword.text,
      );

      closeLoading();

      logger.d('WebDAV连接成功');

      if (!mounted) return;

      final globalSettingCubit = context.read<GlobalSettingCubit>();

      globalSettingCubit.updateWebDavSetting(
        (current) => current.copyWith(
          host: _webdavHost.text.trim(),
          username: _webdavUsername.text.trim(),
          password: _webdavPassword.text,
        ),
      );

      eventBus.fire(const NoticeSync(force: true));

      if (!mounted) return;
      commonDialog(context, t.webdavSync.success, t.webdavSync.webdavConnected);
    } catch (e) {
      logger.e(e);
      closeLoading();

      if (!mounted) return;
      commonDialog(
        context,
        t.webdavSync.error,
        t.webdavSync.webdavConnectFailed(error: e.toString()),
      );
    }
  }

  Future<void> _testS3Server() async {
    final portText = _s3Port.text.trim();
    final port = portText.isEmpty ? 0 : int.tryParse(portText);
    if (port == null || port < 0 || port > 65535) {
      commonDialog(context, t.webdavSync.error, t.webdavSync.invalidPort);
      return;
    }

    final closeLoading = _showConnectingDialog(t.webdavSync.connectingS3);

    try {
      await testS3Server(
        endpoint: _s3Endpoint.text.trim(),
        accessKey: _s3AccessKey.text.trim(),
        secretKey: _s3SecretKey.text,
        bucket: _s3Bucket.text.trim(),
        useSSL: _s3UseSSL,
        port: port,
        pathStyle: _s3PathStyle,
        region: _s3Region.text.trim(),
      );

      closeLoading();

      if (!mounted) return;

      final globalSettingCubit = context.read<GlobalSettingCubit>();
      globalSettingCubit.updateSyncSetting(
        (current) => current.copyWith(
          s3Setting: current.s3Setting.copyWith(
            endpoint: _s3Endpoint.text.trim(),
            accessKey: _s3AccessKey.text.trim(),
            secretKey: _s3SecretKey.text,
            bucket: _s3Bucket.text.trim(),
            region: _s3Region.text.trim(),
            useSSL: _s3UseSSL,
            port: port,
            pathStyle: _s3PathStyle,
          ),
        ),
      );

      eventBus.fire(const NoticeSync(force: true));

      if (!mounted) return;
      commonDialog(context, t.webdavSync.success, t.webdavSync.s3Connected);
    } catch (e) {
      logger.e(e);
      closeLoading();

      if (!mounted) return;
      commonDialog(
        context,
        t.webdavSync.error,
        t.webdavSync.s3ConnectFailed(error: e.toString()),
      );
    }
  }

  void _showQA(BuildContext context) {
    final String disclaimerMarkdown = t.webdavSync.faqMarkdown;

    showCalmDialog<void>(
      context,
      title: t.webdavSync.faq,
      icon: Icons.quiz_outlined,
      maxWidth: 520,
      bodyBuilder: (ctx) => MarkdownBlock(data: disclaimerMarkdown),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.webdavSync.close,
          variant: CalmButtonVariant.primary,
          onPressed: () {
            Navigator.of(ctx).pop();
          },
        ),
      ],
    );
  }
}
