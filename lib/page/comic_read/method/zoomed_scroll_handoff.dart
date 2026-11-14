import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 将放大条漫的纵向手势交给原列表，平移容器仅负责横向移动。
///
/// InteractiveViewer 的 child 是列表视口，而不是整章的高度。放大后列表
/// 虽然锁定了自身的拖动识别，仍可接收转交的拖动及松手速度。
class ZoomedScrollHandoff {
  double? _previousScale;
  Drag? _drag;
  ScrollPosition? _position;
  double _lastDirection = 0;

  bool get isActive => _drag != null || _position != null;

  void _onScrollActivityChanged() {
    if (_drag == null && _position?.isScrollingNotifier.value == false) {
      _detachPosition();
    }
  }

  void _detachPosition() {
    _position?.isScrollingNotifier.removeListener(_onScrollActivityChanged);
    _position = null;
  }

  void cancel() {
    final position = _position;
    _drag?.cancel();
    _drag = null;
    _detachPosition();
    // 取消本次手势留下的惯性，防止捏合、关开关或切页后继续滑动。
    if (position != null && position.hasPixels) {
      position.jumpTo(position.pixels);
    }
    _lastDirection = 0;
    _previousScale = null;
  }

  void end(ScaleEndDetails details) {
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    final scale = _previousScale ?? 1;
    final velocityY = details.velocity.pixelsPerSecond.dy;
    final canFling =
        details.pointerCount == 0 && velocityY * _lastDirection > 0;
    final velocity = canFling ? velocityY / scale : 0.0;
    drag.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        primaryVelocity: velocity,
      ),
    );
    _onScrollActivityChanged();
  }

  void start(TransformationController transformation) {
    cancel();
    _previousScale = transformation.value.getMaxScaleOnAxis();
  }

  void update({
    required ScaleUpdateDetails details,
    required TransformationController transformation,
    required ScrollController scrollController,
    required bool enabled,
  }) {
    final matrix = transformation.value;
    final scale = matrix.getMaxScaleOnAxis();
    final previousScale = _previousScale;
    _previousScale = scale;

    // 捏合及缩放锚点变化不应改变列表位置。
    if (!enabled ||
        details.pointerCount != 1 ||
        previousScale == null ||
        (scale - previousScale).abs() > 0.0001 ||
        scale <= kScaleLockThreshold ||
        !scrollController.hasClients) {
      cancel();
      _previousScale = scale;
      return;
    }

    // 不先消耗视口再转交边界余量：整次纵向拖动使用同一列表物理，
    // 避免两套惯性、边界裁剪和重新起步造成速度突变。
    final delta = details.focalPointDelta.dy;
    if (delta.abs() < 0.001) return;
    final position = scrollController.position;
    if (_drag == null) {
      _detachPosition();
      _position = position;
      position.isScrollingNotifier.addListener(_onScrollActivityChanged);
      _drag = position.drag(
        DragStartDetails(globalPosition: details.focalPoint),
        () {
          // end() 已将 _drag 清空时，继续跟踪松手后的惯性直到停止。
          if (_drag != null) {
            _drag = null;
            _detachPosition();
          }
        },
      );
    }
    _lastDirection = delta;
    _drag!.update(DragUpdateDetails(
      globalPosition: details.focalPoint,
      delta: Offset(0, delta / scale),
      primaryDelta: delta / scale,
    ));
  }
}
