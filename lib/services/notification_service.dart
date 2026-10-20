import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'provider_api_service.dart';
import '../screens/active_booking_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/splash_screen.dart';

/// Global navigator so notification taps and 401 handling can route.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String kChannelId = 'hamaraservice_high_priority';
const String kChannelName = 'HamaraService Alerts';

const AndroidNotificationDetails _androidDetails = AndroidNotificationDetails(
  kChannelId,
  kChannelName,
  channelDescription: 'New job alerts, booking updates and payments',
  importance: Importance.max,
  priority: Priority.high,
  playSound: true,
  enableVibration: true,
  visibility: NotificationVisibility.public,
);

// Events that wake the screen (full-screen alert over the lock screen,
// like an incoming call) — the provider must act on these quickly.
const Set<String> _wakeEvents = {
  'new_booking', 'price_negotiation', 'price_confirmed', 'booking_confirmed',
};

const AndroidNotificationDetails _wakeDetails = AndroidNotificationDetails(
  kChannelId,
  kChannelName,
  channelDescription: 'New job alerts, booking updates and payments',
  importance: Importance.max,
  priority: Priority.max,
  playSound: true,
  enableVibration: true,
  visibility: NotificationVisibility.public,
  fullScreenIntent: true,
  category: AndroidNotificationCategory.call,
  autoCancel: true,
);

int _notificationId(RemoteMessage m) {
  final key = m.messageId ??
      '${m.data['event']}-${m.data['bookingId']}-${m.sentTime?.millisecondsSinceEpoch}';
  return key.hashCode & 0x7fffffff;
}

/// Shows a data-only FCM message as a local notification.
Future<void> _showLocal(FlutterLocalNotificationsPlugin plugin, RemoteMessage m) async {
  final title = '${m.data['title'] ?? m.notification?.title ?? 'HamaraService'}';
  final body = '${m.data['body'] ?? m.notification?.body ?? ''}';
  if (title.isEmpty && body.isEmpty) return;
  await plugin.show(
    _notificationId(m),
    title,
    body,
    NotificationDetails(
        android: _wakeEvents.contains('${m.data['event']}') ? _wakeDetails : _androidDetails),
    payload: jsonEncode(m.data),
  );
}

/// Background / terminated isolate handler. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If the message carries a `notification` block the OS already shows it;
  // showing it again here would duplicate it.
  if (message.notification != null) return;
  await Firebase.initializeApp();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await _showLocal(plugin, message);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final Set<String> _shownIds = {};

  /// Set by the dashboard once it is mounted; taps before that are queued.
  static bool appReady = false;
  static Map<String, dynamic>? _pending;

  static Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (resp) => _handlePayload(resp.payload),
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('FCM permission error: $e');
    }

    // Foreground: FCM shows nothing for data messages → show it ourselves.
    FirebaseMessaging.onMessage.listen((m) {
      final id = m.messageId ?? '';
      if (id.isNotEmpty && !_shownIds.add(id)) return;
      _showLocal(_plugin, m);
    });

    // Taps on OS-displayed notifications (messages with a notification block)
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _route(m.data));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _queueOrRoute(initial.data);

    // App launched by tapping one of our local notifications
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _handlePayload(launch?.notificationResponse?.payload);
    }

    await _askFullScreenOnce();

    // Token refresh → save only when logged in.
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      if (await ProviderApiService.hasToken()) {
        await ProviderApiService.saveFcmToken(t);
      }
    });
  }

  /// Android 14+ asks the user to allow full-screen alerts (needed to wake
  /// the screen for new jobs). Asked once per install.
  static Future<void> _askFullScreenOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('hs_fsi_asked') == true) return;
      await prefs.setBool('hs_fsi_asked', true);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestFullScreenIntentPermission();
    } catch (e) {
      debugPrint('Full-screen permission: $e');
    }
  }

  /// Call after a successful login (and on dashboard start).
  static Future<void> registerToken() async {
    try {
      if (!await ProviderApiService.hasToken()) return;
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) await ProviderApiService.saveFcmToken(t);
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  static void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final d = jsonDecode(payload);
      if (d is Map) _queueOrRoute(Map<String, dynamic>.from(d));
    } catch (_) {}
  }

  static void _queueOrRoute(Map<String, dynamic> data) {
    if (appReady) {
      _route(data);
    } else {
      _pending = data;
    }
  }

  /// Called by the dashboard when it becomes ready.
  static void consumePending() {
    final p = _pending;
    _pending = null;
    if (p != null) _route(p);
  }

  static Future<void> _route(Map<String, dynamic> data) async {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _pending = data;
      return;
    }
    if (!await ProviderApiService.hasToken()) return;
    final event = '${data['event'] ?? ''}';
    final bookingId = '${data['bookingId'] ?? data['booking_id'] ?? ''}';

    if (event == 'account_approved') {
      nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashScreen()), (_) => false);
      return;
    }
    if (event == 'new_booking' || bookingId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final pid = prefs.getString('provider_id') ?? '';
      if (pid.isEmpty) return;
      nav.pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => DashboardScreen(
                  providerId: pid,
                  initialTab: event == 'new_booking' ? 2 : 0)),
          (_) => false);
      return;
    }
    nav.push(MaterialPageRoute(
        builder: (_) => ActiveBookingScreen(bookingId: bookingId)));
  }
}
