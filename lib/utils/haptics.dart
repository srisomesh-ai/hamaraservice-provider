import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vibration/vibration.dart';

/// A short vibration on every tap of something tappable (buttons, tabs,
/// cards, list rows, chips) — app-wide, without touching each button.
///
/// Uses the vibrator directly: Flutter's HapticFeedback goes through the
/// phone's "touch feedback" setting, which many phones ship switched off.
class Haptics {
  static bool? _hasVibrator;
  static int? _pointer;
  static Offset _downAt = Offset.zero;
  static Duration _downTime = Duration.zero;
  static bool _tappable = false;

  /// Call once after WidgetsFlutterBinding.ensureInitialized().
  static void install() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  /// One light tick.
  static Future<void> tap() async {
    try {
      _hasVibrator ??= await Vibration.hasVibrator() ?? false;
      if (_hasVibrator == true) {
        await Vibration.vibrate(duration: 18, amplitude: 90);
        return;
      }
    } catch (_) {}
    HapticFeedback.lightImpact();
  }

  static void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) {
      if (_pointer != null) { _tappable = false; return; } // second finger
      _pointer = e.pointer;
      _downAt = e.position;
      _downTime = e.timeStamp;
      _tappable = _isTappable(e.position, e.viewId);
    } else if (e is PointerUpEvent && e.pointer == _pointer) {
      _pointer = null;
      final moved = (e.position - _downAt).distance;
      final held = e.timeStamp - _downTime;
      if (_tappable && moved < 18 && held < const Duration(milliseconds: 600)) tap();
    } else if (e is PointerCancelEvent && e.pointer == _pointer) {
      _pointer = null;
    }
  }

  static bool _isTappable(Offset position, int viewId) {
    try {
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, position, viewId);
      for (final entry in result.path) {
        final t = entry.target;
        if (t is RenderSemanticsGestureHandler && t.onTap != null) return true;
        if (t is RenderSemanticsAnnotations) {
          final p = t.properties;
          if (p.enabled == false) return false;
          if (p.button == true || p.onTap != null) return true;
        }
      }
    } catch (_) {}
    return false;
  }
}
