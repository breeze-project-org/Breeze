import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

Future<List<int>?> showGesturePasswordSetupDialog(
  BuildContext context, {
  required String title,
  required String confirmTitle,
}) {
  return showCalmDialog<List<int>>(
    context,
    title: title,
    icon: Icons.gesture_rounded,
    bodyBuilder: (_) => _GesturePatternSetupBody(confirmTitle: confirmTitle),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
    barrierDismissible: false,
  );
}

Future<GestureUnlockResult?> showGestureUnlockDialog(
  BuildContext context, {
  required String expectedHash,
  String title = '',
  String hint = '',
  bool showForgotPassword = false,
}) {
  return showCalmDialog<GestureUnlockResult>(
    context,
    title: title.isEmpty ? t.gestureLock.gestureTitle : title,
    icon: Icons.lock_outline_rounded,
    bodyBuilder: (_) =>
        _GestureUnlockBody(expectedHash: expectedHash, hint: hint),
    actionsBuilder: (dialogContext) => [
      if (showForgotPassword)
        CalmButton(
          label: t.gestureLock.forgotPassword,
          variant: CalmButtonVariant.ghost,
          onPressed: () =>
              Navigator.of(dialogContext)
                  .pop(GestureUnlockResult.forgotPassword),
        ),
    ],
    barrierDismissible: false,
  );
}

String hashGesturePattern(List<int> pattern) {
  return sha256.convert(utf8.encode(pattern.join('-'))).toString();
}

String hashPinCode(String pin) {
  return sha256.convert(utf8.encode('pin:$pin')).toString();
}

Future<String?> showPinCodeSetupDialog(
  BuildContext context, {
  required String title,
  required String confirmTitle,
}) {
  final bodyKey = GlobalKey<_PinSetupBodyState>();
  return showCalmDialog<String>(
    context,
    title: title,
    icon: Icons.pin_outlined,
    bodyBuilder: (_) => _PinSetupBody(key: bodyKey, confirmTitle: confirmTitle),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      CalmButton(
        label: t.common.ok,
        variant: CalmButtonVariant.primary,
        onPressed: () => bodyKey.currentState?.submit(),
      ),
    ],
    barrierDismissible: false,
  );
}

Future<bool?> showPinVerifyDialog(
  BuildContext context, {
  required String expectedHash,
  String title = '',
  String hint = '',
}) {
  final bodyKey = GlobalKey<_PinVerifyBodyState>();
  return showCalmDialog<bool>(
    context,
    title: title.isEmpty ? t.gestureLock.pinTitle : title,
    icon: Icons.password_rounded,
    bodyBuilder: (_) =>
        _PinVerifyBody(key: bodyKey, expectedHash: expectedHash, hint: hint),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(false),
      ),
      CalmButton(
        label: t.common.ok,
        variant: CalmButtonVariant.primary,
        onPressed: () => bodyKey.currentState?.submit(),
      ),
    ],
    barrierDismissible: false,
  );
}

enum GestureUnlockResult { success, forgotPassword }

/// 九宫格手势板：完整保留旧版轨迹采样、去重与完成回调逻辑。
class AppGesturePatternBoard extends StatefulWidget {
  const AppGesturePatternBoard({
    super.key,
    required this.onCompleted,
    this.error = false,
  });

  final ValueChanged<List<int>> onCompleted;

  /// 校验失败时把圆点与连线染成危险色，给一次即时反馈。
  final bool error;

  @override
  State<AppGesturePatternBoard> createState() => _AppGesturePatternBoardState();
}

class _AppGesturePatternBoardState extends State<AppGesturePatternBoard> {
  final GlobalKey _boardKey = GlobalKey();
  final List<int> _selected = <int>[];
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return GestureDetector(
      onPanStart: (details) {
        _selected.clear();
        _dragging = true;
        _trySelect(details.localPosition);
        setState(() {});
      },
      onPanUpdate: (details) {
        if (!_dragging) {
          return;
        }
        _trySelect(details.localPosition);
        setState(() {});
      },
      onPanEnd: (_) => _finish(),
      onPanCancel: _finish,
      child: RepaintBoundary(
        key: _boardKey,
        child: SizedBox(
          width: 240,
          height: 240,
          child: CustomPaint(
            painter: _GesturePatternPainter(
              selected: List<int>.from(_selected),
              activeColor: widget.error ? c.danger : c.accent,
              inactiveColor: c.borderStrong,
            ),
          ),
        ),
      ),
    );
  }

  void _trySelect(Offset position) {
    final size =
        (_boardKey.currentContext?.findRenderObject() as RenderBox?)?.size;
    if (size == null) {
      return;
    }
    final cellWidth = size.width / 3;
    final cellHeight = size.height / 3;
    final col = (position.dx / cellWidth).floor();
    final row = (position.dy / cellHeight).floor();
    if (col < 0 || col > 2 || row < 0 || row > 2) {
      return;
    }
    final index = row * 3 + col;
    if (_selected.contains(index)) {
      return;
    }
    _selected.add(index);
  }

  void _finish() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    final result = List<int>.from(_selected);
    _selected.clear();
    setState(() {});
    if (result.isNotEmpty) {
      widget.onCompleted(result);
    }
  }
}

// --- 手势设置 ---

class _GesturePatternSetupBody extends StatefulWidget {
  const _GesturePatternSetupBody({required this.confirmTitle});

  final String confirmTitle;

  @override
  State<_GesturePatternSetupBody> createState() =>
      _GesturePatternSetupBodyState();
}

class _GesturePatternSetupBodyState extends State<_GesturePatternSetupBody> {
  List<int>? _firstPattern;
  String _errorText = '';

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final confirming = _firstPattern != null;
    final hint = confirming
        ? t.gestureLock.setupHintConfirm
        : t.gestureLock.setupHintFirst;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                hint,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(11.5),
                style: TextStyle(
                  fontSize: 11.5,
                  color: c.text2,
                  height: 1.35,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
            if (confirming) ...[
              const SizedBox(width: 8),
              CalmBadge(label: widget.confirmTitle, tone: CalmBadgeTone.tonal),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: CalmCard(
            padding: const EdgeInsets.all(8),
            radius: 18,
            color: c.surface2,
            child: AppGesturePatternBoard(
              onCompleted: _handleCompleted,
              error: _errorText.isNotEmpty,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _GestureErrorLine(text: _errorText),
      ],
    );
  }

  void _handleCompleted(List<int> pattern) {
    if (pattern.length < 4) {
      setState(() {
        _errorText = t.gestureLock.setupErrorMinPoints;
      });
      return;
    }

    if (_firstPattern == null) {
      setState(() {
        _firstPattern = pattern;
        _errorText = '';
      });
      return;
    }

    if (listEquals(_firstPattern, pattern)) {
      Navigator.of(context).pop(pattern);
      return;
    }

    setState(() {
      _firstPattern = null;
      _errorText = t.gestureLock.setupErrorMismatch;
    });
  }
}

// --- 手势解锁 ---

class _GestureUnlockBody extends StatefulWidget {
  const _GestureUnlockBody({required this.expectedHash, required this.hint});

  final String expectedHash;
  final String hint;

  @override
  State<_GestureUnlockBody> createState() => _GestureUnlockBodyState();
}

class _GestureUnlockBodyState extends State<_GestureUnlockBody> {
  String _errorText = '';

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hint.isNotEmpty)
          Text(
            widget.hint,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(11.5),
            style: TextStyle(
              fontSize: 11.5,
              color: c.text2,
              height: 1.35,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        const SizedBox(height: 12),
        Center(
          child: CalmCard(
            padding: const EdgeInsets.all(8),
            radius: 18,
            color: c.surface2,
            child: AppGesturePatternBoard(
              onCompleted: _handleCompleted,
              error: _errorText.isNotEmpty,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _GestureErrorLine(text: _errorText),
      ],
    );
  }

  void _handleCompleted(List<int> pattern) {
    if (hashGesturePattern(pattern) == widget.expectedHash) {
      Navigator.of(context).pop(GestureUnlockResult.success);
      return;
    }
    setState(() {
      _errorText = t.gestureLock.incorrectPassword;
    });
  }
}

// --- PIN 设置 / 校验 ---

class _PinSetupBody extends StatefulWidget {
  const _PinSetupBody({super.key, required this.confirmTitle});

  final String confirmTitle;

  @override
  State<_PinSetupBody> createState() => _PinSetupBodyState();
}

class _PinSetupBodyState extends State<_PinSetupBody> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String _errorText = '';

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pinFieldLabel(context, t.gestureLock.resetPin),
        const SizedBox(height: 6),
        CalmTextField(
          controller: _controller,
          hintText: t.gestureLock.pinHintMinDigits,
          prefixIcon: Icons.pin_outlined,
          obscureText: true,
          clearable: false,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        _pinFieldLabel(context, widget.confirmTitle),
        const SizedBox(height: 6),
        CalmTextField(
          controller: _confirmController,
          hintText: t.gestureLock.pinHintMinDigits,
          prefixIcon: Icons.check_circle_outline_rounded,
          obscureText: true,
          clearable: false,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 10),
        Text(
          t.gestureLock.pinDescription,
          style: TextStyle(fontSize: 11, color: c.text3, height: 1.45),
        ),
        const SizedBox(height: 8),
        _GestureErrorLine(text: _errorText),
      ],
    );
  }

  void submit() {
    final pin = _controller.text.trim();
    final confirmPin = _confirmController.text.trim();
    if (!RegExp(r'^\d{4,}$').hasMatch(pin)) {
      setState(() {
        _errorText = t.gestureLock.pinMinLength;
      });
      return;
    }
    if (pin != confirmPin) {
      setState(() {
        _errorText = t.gestureLock.pinNotMatch;
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }
}

class _PinVerifyBody extends StatefulWidget {
  const _PinVerifyBody({
    super.key,
    required this.expectedHash,
    required this.hint,
  });

  final String expectedHash;
  final String hint;

  @override
  State<_PinVerifyBody> createState() => _PinVerifyBodyState();
}

class _PinVerifyBodyState extends State<_PinVerifyBody> {
  final TextEditingController _controller = TextEditingController();
  String _errorText = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hint.isNotEmpty)
          Text(
            widget.hint,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(11.5),
            style: TextStyle(
              fontSize: 11.5,
              color: c.text2,
              height: 1.35,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        const SizedBox(height: 10),
        _pinFieldLabel(context, t.gestureLock.pin),
        const SizedBox(height: 6),
        CalmTextField(
          controller: _controller,
          hintText: t.gestureLock.pinHintMinDigits,
          prefixIcon: Icons.password_rounded,
          obscureText: true,
          clearable: false,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 8),
        _GestureErrorLine(text: _errorText),
      ],
    );
  }

  void submit() {
    final pin = _controller.text.trim();
    if (hashPinCode(pin) == widget.expectedHash) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _errorText = t.gestureLock.pinIncorrect;
    });
  }
}

Widget _pinFieldLabel(BuildContext context, String text) {
  final c = context.calm;
  return Text(
    text,
    textHeightBehavior: kCalmTextHeightBehavior,
    strutStyle: calmStrut(11.5),
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      color: c.text2,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  );
}

/// 弹窗内的固定高度错误行：避免错误文案出现/消失时弹窗高度跳动。
class _GestureErrorLine extends StatelessWidget {
  const _GestureErrorLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return SizedBox(
      height: 18,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textHeightBehavior: kCalmTextHeightBehavior,
          strutStyle: calmStrut(11.5),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: c.danger,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }
}

class _GesturePatternPainter extends CustomPainter {
  const _GesturePatternPainter({
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<int> selected;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final points = _buildPoints(size);
    final linePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 1; i < selected.length; i++) {
      canvas.drawLine(points[selected[i - 1]], points[selected[i]], linePaint);
    }

    for (var i = 0; i < points.length; i++) {
      final isSelected = selected.contains(i);
      final fillPaint = Paint()
        ..color = isSelected
            ? activeColor.withValues(alpha: 0.18)
            : Colors.transparent
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = isSelected ? activeColor : inactiveColor
        ..strokeWidth = isSelected ? 3 : 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(points[i], 18, fillPaint);
      canvas.drawCircle(points[i], 18, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GesturePatternPainter oldDelegate) {
    return !listEquals(oldDelegate.selected, selected) ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }

  List<Offset> _buildPoints(Size size) {
    final stepX = size.width / 3;
    final stepY = size.height / 3;
    return List<Offset>.generate(9, (index) {
      final row = index ~/ 3;
      final col = index % 3;
      return Offset(stepX * (col + 0.5), stepY * (row + 0.5));
    });
  }
}
