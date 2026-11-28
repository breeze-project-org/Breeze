import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/network/http/plugin/unified_plugin_envelope.dart';
import 'package:zephyr/page/login/slider_captcha_dialog.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class LoginPage extends StatefulWidget {
  final String? from;

  const LoginPage({super.key, this.from});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginFieldSpec {
  const _LoginFieldSpec({
    required this.key,
    required this.kind,
    required this.label,
    this.required = false,
    this.placeholder = '',
    this.help = '',
    this.captchaFetchFnPath = '',
    this.captchaRefreshText = '',
    this.sliderCreateFnPath = '',
    this.sliderVerifyFnPath = '',
    this.sliderRefreshText = '',
  });

  final String key;
  final String kind;
  final String label;
  final bool required;
  final String placeholder;
  final String help;

  /// captcha-image 字段取图函数（插件 fnPath），空表示非验证码字段。
  final String captchaFetchFnPath;

  /// 验证码图下方刷新提示文案，空时用默认文案。
  final String captchaRefreshText;

  /// slider-captcha 字段取题/验题函数（插件 fnPath），空表示非滑块字段。
  final String sliderCreateFnPath;
  final String sliderVerifyFnPath;

  /// 滑块字段刷新提示文案，空时用默认文案。
  final String sliderRefreshText;

  bool get obscure => kind == 'password';

  bool get multiline => kind == 'multiline';

  bool get isCaptchaImage => kind == 'captcha-image';

  bool get isSliderCaptcha =>
      kind == 'slider-captcha' &&
      sliderCreateFnPath.isNotEmpty &&
      sliderVerifyFnPath.isNotEmpty;
}

class _LoginPageState extends State<LoginPage> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Uint8List> _captchaImages = {};
  final Set<String> _captchaLoading = {};
  final Set<String> _captchaFailed = {};

  String title = '';
  late String from;
  List<_LoginFieldSpec> _fields = const [];
  String _submitFnPath = '';
  String _submitLabel = '';
  bool _loadingScheme = true;
  bool _submitting = false;
  String? _schemeError;

  @override
  void initState() {
    super.initState();
    from = (widget.from ?? '').trim();
    _loadLoginScheme();
  }

  Future<void> _loadLoginScheme() async {
    if (from.isEmpty) {
      if (mounted) {
        setState(() {
          _schemeError = t.login.missingPluginId;
          _loadingScheme = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _schemeError = null;
        _loadingScheme = true;
      });
    }

    try {
      final response = await callUnifiedComicPlugin(
        from: from,
        fnPath: 'getLoginBundle',
        core: const <String, dynamic>{},
        extern: const <String, dynamic>{},
      );
      final envelope = UnifiedPluginEnvelope.fromMap(
        response.data,
        source: response.source,
      );
      _applyLoginBundle(envelope.scheme, envelope.data);
    } catch (e) {
      logger.e(e);
      if (mounted) {
        final raw = e.toString();
        final missingBundle =
            raw.contains('getLoginBundle') ||
            raw.contains('function path not found') ||
            raw.contains('target is not function');
        setState(() {
          _schemeError = missingBundle
              ? t.login.loginNotSupported
              : t.login.loadConfigFailed(error: e);
          _loadingScheme = false;
        });
      }
    }
  }

  void _applyLoginBundle(
    Map<String, dynamic> scheme,
    Map<String, dynamic>? data,
  ) {
    final action = asJsonMap(scheme['action']);
    final submitFnPath =
        (action['fnPath'] ?? scheme['submitFnPath'] ?? scheme['fnPath'])
            ?.toString()
            .trim() ??
        '';
    final fields = asJsonList(scheme['fields'])
        .map((item) => asJsonMap(item))
        .toList();
    final specs = <_LoginFieldSpec>[];
    for (final field in fields) {
      final key = field['key']?.toString().trim() ?? '';
      if (key.isEmpty) {
        continue;
      }
      final captcha = asJsonMap(field['captcha']);
      final slider = asJsonMap(field['slider']);
      specs.add(
        _LoginFieldSpec(
          key: key,
          kind: field['kind']?.toString().trim().isNotEmpty == true
              ? field['kind'].toString().trim()
              : 'text',
          label: field['label']?.toString().trim().isNotEmpty == true
              ? field['label'].toString().trim()
              : key,
          required: field['required'] == true,
          placeholder: field['placeholder']?.toString() ?? '',
          help: field['help']?.toString() ?? '',
          captchaFetchFnPath: captcha['fetchFnPath']?.toString().trim() ?? '',
          captchaRefreshText: captcha['refreshText']?.toString() ?? '',
          sliderCreateFnPath: slider['createFnPath']?.toString().trim() ?? '',
          sliderVerifyFnPath: slider['verifyFnPath']?.toString().trim() ?? '',
          sliderRefreshText: slider['refreshText']?.toString() ?? '',
        ),
      );
    }
    if (specs.isEmpty || submitFnPath.isEmpty) {
      if (mounted) {
        setState(() {
          _schemeError = t.login.insufficientFields;
          _loadingScheme = false;
        });
      }
      return;
    }

    for (final entry in _controllers.values) {
      entry.dispose();
    }
    _controllers.clear();
    final values = <String, dynamic>{
      ...asJsonMap(data),
      ...asJsonMap(data?['values']),
    };
    for (final spec in specs) {
      // 滑块字段无文本输入：提交时弹拼图现验现用。
      if (spec.isSliderCaptcha) continue;
      _controllers[spec.key] = TextEditingController(
        text: values[spec.key]?.toString() ?? '',
      );
    }

    if (mounted) {
      setState(() {
        title = scheme['title']?.toString().trim() ?? '';
        _fields = specs;
        _submitFnPath = submitFnPath;
        _submitLabel =
            (action['submitText'] ?? action['label'] ?? scheme['submitText'])
                ?.toString()
                .trim() ??
            '';
        _schemeError = null;
        _loadingScheme = false;
        _captchaImages.clear();
        _captchaLoading.clear();
        _captchaFailed.clear();
      });
      // 验证码字段自动取图（每次进入登录页都是新图+新会话）。
      for (final spec in specs) {
        if (spec.isCaptchaImage && spec.captchaFetchFnPath.isNotEmpty) {
          _fetchCaptcha(spec.key);
        }
      }
    }
  }

  /// 取验证码图：插件返回 `{ imageBase64: string; mimeType?: string }`。
  /// 会话（Set-Cookie）由插件 JS 侧保管，提交时自动带回。
  Future<void> _fetchCaptcha(String key) async {
    final spec = _fields.where((e) => e.key == key).firstOrNull;
    if (spec == null || spec.captchaFetchFnPath.isEmpty) return;
    if (_captchaLoading.contains(key)) return;
    if (mounted) {
      setState(() {
        _captchaLoading.add(key);
        _captchaFailed.remove(key);
      });
    }
    try {
      final result = await callUnifiedComicPlugin(
        from: from,
        fnPath: spec.captchaFetchFnPath,
        core: const <String, dynamic>{},
        extern: const <String, dynamic>{},
      );
      final raw = (result.data['imageBase64'] ?? result.data['image'] ?? '')
          .toString();
      final bytes = base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
      if (bytes.isEmpty) throw StateError('empty captcha image');
      if (!mounted) return;
      setState(() {
        _captchaImages[key] = bytes;
      });
      // 取到新图后清空旧输入：旧码已随新图作废。
      _controllers[key]?.clear();
    } catch (e) {
      logger.e(e);
      if (mounted) {
        setState(() {
          _captchaFailed.add(key);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _captchaLoading.remove(key);
        });
      }
    }
  }

  bool get _hasCaptchaField =>
      _fields.any((e) => e.isCaptchaImage && e.captchaFetchFnPath.isNotEmpty);

  /// 刷新全部验证码图（提交失败后自动调用，保证旧码作废后用户拿到新图）。
  void _refreshAllCaptchas() {
    for (final spec in _fields) {
      if (spec.isCaptchaImage && spec.captchaFetchFnPath.isNotEmpty) {
        _fetchCaptcha(spec.key);
      }
    }
  }

  /// 打开拼图弹窗完成验证：通过返回一次性 pass，用户取消返回 null。
  /// 取题时透传当前表单值（账号绑定的站用它取题；不绑定的站忽略）。
  Future<String?> _solveSlider(
    _LoginFieldSpec spec,
    Map<String, dynamic> values,
  ) {
    if (!mounted) return Future.value();
    return SliderCaptchaDialog.show(
      context,
      from: from,
      createFnPath: spec.sliderCreateFnPath,
      verifyFnPath: spec.sliderVerifyFnPath,
      refreshText: spec.sliderRefreshText,
      values: values,
    );
  }

  @override
  void dispose() {
    for (final entry in _controllers.values) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _showDialog(String title, String message) async {
    if (message.contains("invalid email or password")) {
      message = t.login.invalidCredentials;
    }

    if (!mounted) return;

    return showCalmDialog<void>(
      context,
      title: title,
      icon: Icons.error_outline_rounded,
      tone: CalmTone.danger,
      barrierDismissible: false, // user must tap button!
      bodyBuilder: (ctx) {
        final c = ctx.calm;
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            message,
            textHeightBehavior: kCalmTextHeightBehavior,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.text2),
          ),
        );
      },
      actionsBuilder: (ctx) => <Widget>[
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
  }

  /// 登录提交返回值约定：`message?: string | null`，缺省/空白时用默认文案。
  String _resolveLoginSuccessMessage(Map<String, dynamic> result) {
    final message = result['message']?.toString().trim();
    if (message?.isNotEmpty == true) return message!;
    final dataMessage = asJsonMap(result['data'])['message']?.toString().trim();
    if (dataMessage?.isNotEmpty == true) return dataMessage!;
    return t.login.loginSuccess;
  }

  void _submitForm() async {
    if (!mounted) return;
    if (_loadingScheme || _schemeError != null || _submitting) {
      if (!_submitting) {
        showErrorToast(t.login.configNotReady);
      }
      return;
    }
    // 文本字段先收齐（滑块字段无输入，提交时现验现用）。
    final values = <String, dynamic>{};
    for (final spec in _fields) {
      if (spec.isSliderCaptcha) continue;
      final text = _controllers[spec.key]?.text ?? '';
      if (spec.required && text.trim().isEmpty) {
        showErrorToast(t.login.requiredFieldEmpty(label: spec.label));
        return;
      }
      values[spec.key] = text;
    }
    // 有滑块字段时逐个弹拼图：通过得一次性 pass 并入 values，
    // 用户取消则中止提交；取题时透传已填表单值（账号绑定的站用它取题）。
    // 先占 _submitting 防重复点击；取消/失败走 finally 恢复。
    setState(() {
      _submitting = true;
    });
    for (final spec in _fields) {
      if (!spec.isSliderCaptcha) continue;
      final pass = await _solveSlider(spec, values);
      if (!mounted) return;
      if (pass == null || pass.isEmpty) {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
        }
        return;
      }
      values[spec.key] = pass;
    }
    showInfoToast(t.login.loggingIn);

    try {
      // 新旧兼容：新插件读 core.values，旧插件读顶层 account/password。
      final result = await callUnifiedComicPlugin(
        from: from,
        fnPath: _submitFnPath,
        core: {...values, 'values': values},
        extern: const <String, dynamic>{},
      );
      showSuccessToast(_resolveLoginSuccessMessage(result.data));

      if (!mounted) return;
      context.maybePop();
    } catch (e) {
      logger.e(e);
      final message = normalizeSearchErrorMessage(e);
      _showDialog(t.login.loginFailed, message);
      // 失败自动刷新：验证码一次一码，旧码提交后即作废；
      // 无论失败原因是码错还是账密错，都换一张新图 + 清空输入。
      // 滑块 pass 现验现用：失败下次提交重新弹拼图，无需清理。
      if (_hasCaptchaField) _refreshAllCaptchas();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScheme) {
      return CalmPageScaffold(
        title: t.login.title,
        maxContentWidth: 480,
        body: Center(child: CalmLoading(label: t.common.loading, size: 22)),
      );
    }

    if (_schemeError != null) {
      return CalmPageScaffold(
        title: t.login.title,
        maxContentWidth: 480,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: CalmErrorState(
                title: _schemeError!,
                errorDetail: from.isEmpty ? t.login.missingPluginId : from,
                errorDetailMaxLines: 2,
                primaryLabel: t.login.retry,
                onPrimary: _loadLoginScheme,
              ),
            ),
          ),
        ),
      );
    }

    final submitLabel = _submitLabel.isEmpty
        ? t.login.loginButton
        : _submitLabel;
    // 滑块字段不占位：提交时自动弹拼图，登录页外观与无滑块时一致。
    final visibleFields = _fields.where((e) => !e.isSliderCaptcha).toList();
    return CalmPageScaffold(
      title: title.isEmpty ? t.login.title : title,
      maxContentWidth: 520,
      actions: [
        CalmIconButton(
          icon: Icons.settings_rounded,
          tooltip: t.settings.title,
          onPressed: () => context.pushRoute(GlobalSettingRoute()),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: CalmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < visibleFields.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _buildField(visibleFields[i]),
              ],
              const SizedBox(height: 18),
              CalmButton(
                label: submitLabel,
                icon: Icons.login_rounded,
                variant: CalmButtonVariant.primary,
                size: CalmButtonSize.md,
                expand: true,
                loading: _submitting,
                onPressed: _submitting ? null : _submitForm,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(_LoginFieldSpec spec) {
    if (spec.isCaptchaImage) return _buildCaptchaField(spec);
    // 滑块字段不渲染：提交时自动弹拼图，登录页外观与无滑块时一致。
    if (spec.isSliderCaptcha) return const SizedBox.shrink();

    final c = context.calm;
    final controller = _controllers[spec.key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: spec.required ? '${spec.label} *' : spec.label),
        const SizedBox(height: 6),
        if (spec.multiline)
          CalmTextArea(
            controller: controller,
            hintText: spec.placeholder.isEmpty
                ? spec.label
                : spec.placeholder,
            minLines: 3,
            maxLines: 5,
          )
        else
          CalmTextField(
            controller: controller,
            hintText: spec.placeholder.isEmpty ? null : spec.placeholder,
            prefixIcon: spec.obscure ? Icons.lock_outline_rounded : null,
            obscureText: spec.obscure,
          ),
        if (spec.help.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            spec.help,
            style: TextStyle(fontSize: 10.5, height: 1.5, color: c.text3),
          ),
        ],
      ],
    );
  }

  /// 验证码字段：左输入框 + 右图片（点击刷新），常规网站布局。
  /// 提交失败后宿主自动刷图，取到新图时清空旧输入（旧码已作废）。
  Widget _buildCaptchaField(_LoginFieldSpec spec) {
    final c = context.calm;
    final controller = _controllers[spec.key];
    final bytes = _captchaImages[spec.key];
    final loading = _captchaLoading.contains(spec.key);
    final failed = _captchaFailed.contains(spec.key);
    final refreshText = spec.captchaRefreshText.isEmpty
        ? t.login.captchaTapToRefresh
        : spec.captchaRefreshText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: spec.required ? '${spec.label} *' : spec.label),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: CalmTextField(
                controller: controller,
                hintText: spec.placeholder.isEmpty
                    ? spec.label
                    : spec.placeholder,
                prefixIcon: Icons.verified_user_outlined,
              ),
            ),
            const SizedBox(width: 10),
            // 右侧图与输入框等高，只负责显示不挡字；点图放大看，点按钮刷新。
            GestureDetector(
              onTap: loading || bytes == null
                  ? null
                  : () => _showCaptchaZoom(spec.key),
              child: Container(
                height: 36,
                width: 132,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface2,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: loading
                    ? CalmLoading(size: 14)
                    : (bytes != null
                          ? Image.memory(
                              bytes,
                              height: 36,
                              width: 132,
                              fit: BoxFit.fill,
                            )
                          : Text(
                              failed
                                  ? t.login.captchaLoadFailed
                                  : t.login.captchaLoading,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: failed ? c.danger : c.text3,
                              ),
                            )),
              ),
            ),
            const SizedBox(width: 6),
            CalmIconButton(
              icon: Icons.refresh_rounded,
              tooltip: refreshText,
              onPressed: loading ? null : () => _fetchCaptcha(spec.key),
            ),
          ],
        ),
        if (spec.help.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            spec.help,
            style: TextStyle(fontSize: 10.5, height: 1.5, color: c.text3),
          ),
        ],
      ],
    );
  }

  /// 点图放大：双倍尺寸看大字，弹窗内可直接刷新换一张。
  Future<void> _showCaptchaZoom(String key) async {
    final spec = _fields.where((e) => e.key == key).firstOrNull;
    if (spec == null) return;
    await showCalmDialog<void>(
      context,
      title: spec.label,
      subtitle: spec.help.trim().isEmpty ? null : spec.help,
      icon: Icons.image_outlined,
      maxWidth: 440,
      bodyBuilder: (ctx) {
        final c = ctx.calm;
        final bytes = _captchaImages[key];
        final loading = _captchaLoading.contains(key);
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: loading
                ? const CalmLoading()
                : Text(
                    t.login.captchaLoadFailed,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.text2),
                  ),
          ),
        );
      },
      actionsBuilder: (ctx) => <Widget>[
        CalmButton(
          label: t.login.retry,
          icon: Icons.refresh_rounded,
          variant: CalmButtonVariant.ghost,
          onPressed: _captchaLoading.contains(key)
              ? null
              : () {
                  _fetchCaptcha(key);
                  Navigator.of(ctx).pop();
                },
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
    // 弹窗里刷了图的话外层跟着重建。
    if (mounted) setState(() {});
  }
}

/// 表单字段小标题（胶囊输入框不自带 label，这里统一排版）。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Text(
      text,
      textHeightBehavior: kCalmTextHeightBehavior,
      strutStyle: calmStrut(11.5),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: c.text2,
        height: 1.2,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );
  }
}
