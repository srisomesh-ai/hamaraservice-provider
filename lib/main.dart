import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'utils/theme.dart';
import 'screens/splash_screen.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

    // Save FCM token to Firebase so server can send push notifications
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      print('FCM Token: $token');
      // Token will be saved per-provider in dashboard after login
    }

    // Refresh token listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('FCM token refreshed: $newToken');
      // Dashboard will save updated token on next load
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

    // Handle foreground messages — show in-app banner
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground FCM: ${message.notification?.title} — ${message.notification?.body}');
    });

  } catch (e) {
    print('Firebase init error: \$e');
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
