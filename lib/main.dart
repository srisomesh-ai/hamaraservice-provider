import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/notification_service.dart';
import 'services/provider_api_service.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorScreen();

  // Android reads its Firebase config from android/app/google-services.json
  // (written by CI from the GOOGLE_SERVICES_JSON secret). Firebase is used
  // only for FCM push in this app.
  // Only Firebase core is awaited before the first frame (with a time
  // limit); notifications + permission prompts start once the UI is visible,
  // so the app can never hang on its launch screen.
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService.init().catchError((Object e) {
        debugPrint('Notification init failed: $e');
      }));
    });
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Any 401 from the API (expired / rotated JWT) → back to login.
  ProviderApiService.onUnauthorized = () {
    NotificationService.appReady = false;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(sessionExpired: true)),
        (_) => false);
  };

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runZonedGuarded(() => runApp(const ProviderApp()),
      (e, s) => debugPrint('Uncaught: $e\n$s'));
}

/// In release builds Flutter shows a blank grey box when a screen fails to
/// build. Show the actual error instead so a screenshot tells us the cause.
void _installErrorScreen() {
  if (kDebugMode) return;
  ErrorWidget.builder = (FlutterErrorDetails d) => Material(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text('Something went wrong.\n\n${d.exceptionAsString()}',
                style: const TextStyle(color: Colors.black87, fontSize: 13)),
          ),
        ),
      );
}

class ProviderApp extends StatelessWidget {
  const ProviderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HamaraService Provider',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
