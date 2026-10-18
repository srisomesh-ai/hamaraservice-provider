import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/notification_service.dart';
import 'services/provider_api_service.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android reads its Firebase config from android/app/google-services.json
  // (written by CI from the GOOGLE_SERVICES_JSON secret). Firebase is used
  // only for FCM push in this app.
  try {
    await Firebase.initializeApp();
    await NotificationService.init();
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
  runApp(const ProviderApp());
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
