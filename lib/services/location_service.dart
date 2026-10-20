import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'provider_api_service.dart';

/// Sends POST providers.php?action=location while the app is in the
/// foreground: every 60 s while online, every 30 s while on a
/// confirmed/active job. No background service.
class LocationService with WidgetsBindingObserver {
  LocationService._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final LocationService instance = LocationService._();

  bool _online = false;
  bool _onJob = false;
  bool _foreground = true;
  bool _sending = false;
  Timer? _timer;
  Duration? _current;

  set online(bool v) {
    if (_online == v) return;
    _online = v;
    _reschedule();
  }

  set onJob(bool v) {
    if (_onJob == v) return;
    _onJob = v;
    _reschedule();
  }

  void stopAll() {
    _online = false;
    _onJob = false;
    _reschedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reschedule();
  }

  void _reschedule() {
    final Duration? interval = !_foreground
        ? null
        : _onJob
            ? const Duration(seconds: 30)
            : _online
                ? const Duration(seconds: 60)
                : null;
    if (interval == _current && (interval == null || _timer != null)) return;
    _timer?.cancel();
    _timer = null;
    _current = interval;
    if (interval == null) return;
    sendNow();
    _timer = Timer.periodic(interval, (_) => sendNow());
  }

  /// Returns the position sent, or null when unavailable.
  Future<Position?> sendNow() async {
    if (_sending) return null;
    _sending = true;
    try {
      final pos = await currentPosition();
      if (pos != null && await ProviderApiService.hasToken()) {
        await ProviderApiService.sendLocation(pos.latitude, pos.longitude);
      }
      return pos;
    } catch (e) {
      debugPrint('Location send failed: $e');
      return null;
    } finally {
      _sending = false;
    }
  }

  /// Current position if permission is granted (asks once if needed).
  static Future<Position?> currentPosition({bool ask = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }
}
