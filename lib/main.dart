import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'utils/theme.dart';
import 'screens/splash_screen.dart';
import 'firebase_options.dart';

// Global FLNP instance — must be global to use inside async listeners
final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Data-only messages need to be shown manually
  final title = message.data['title'] ?? message.notification?.title ?? 'HamaraService';
  final body  = message.data['body']  ?? message.notification?.body  ?? 'You have a new update.';

  // Init local notifications
  final flnpBg = FlutterLocalNotificationsPlugin();
  await flnpBg.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  await flnpBg.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'hamaraservice_high_priority',
        'HamaraService Alerts',
        channelDescription: 'Booking and payment notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
      ),
    ),
    payload: message.data.toString(),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Initialize local notifications
    await flnp.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission — critical for iOS
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
      announcement: true,
      provisional: false,
    );
    print('FCM permission: ${settings.authorizationStatus}');

    // Show notifications when app is in foreground
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle foreground messages — show heads-up banner even when app is open
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      // data-only FCM — read from data map
      try {
        await flnp.show(
          message.hashCode,
          n.title ?? 'HamaraService',
          n.body ?? '',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'hamaraservice_high_priority',
              'HamaraService Alerts',
              channelDescription: 'New job alerts and payment notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              visibility: NotificationVisibility.public,
            ),
          ),
        );
      } catch (_) {}
    });

    // Save FCM token to Firebase so server can send push notifications
    Future<void> saveFcmToken(String token) async {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && token.isNotEmpty) {
          await FirebaseDatabase.instance.ref('providers/$uid/fcmToken').set(token);
          print('FCM Token saved for provider: $uid');
        }
      } catch (e) {
        print('FCM save error: $e');
      }
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      print('FCM Token: $token');
      saveFcmToken(token);
    }

    // Refresh token listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('FCM token refreshed: $newToken');
      saveFcmToken(newToken);
    });

    // Handle notification tap when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification tapped (background): ${message.data}');
    });

    // Check if app was opened from terminated state via notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('App opened from notification: ${initialMessage.data}');
    }

  } catch (e) {
    print('Firebase init error: $e');
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderApp());
}

class ProviderApp extends StatelessWidget {
  const ProviderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HamaraService Provider',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
