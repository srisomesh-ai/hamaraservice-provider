import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import 'intro_screen.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final introSeen   = prefs.getBool('provider_intro_seen') ?? false;
    final loggedIn    = prefs.getBool('provider_logged_in') ?? false;
    final providerId  = prefs.getString('provider_id') ?? '';
    final token       = prefs.getString('provider_jwt') ?? '';

    // Re-check the cached account status — only approved providers may
    // skip the login screen.
    String status = '';
    try {
      final raw = prefs.getString('provider_data');
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) status = data['status']?.toString() ?? '';
      }
    } catch (_) {}
    final canAutoLogin = loggedIn && providerId.isNotEmpty &&
        token.isNotEmpty && status == 'approved';
    if (loggedIn && !canAutoLogin) {
      await prefs.setBool('provider_logged_in', false);
    }
    if (!mounted) return;

    if (!introSeen) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const IntroScreen()));
    } else if (canAutoLogin) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => DashboardScreen(providerId: providerId)));
    } else {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0D3D47), AppColors.teal],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.home_repair_service_rounded, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 20),
                RichText(text: const TextSpan(children: [
                  TextSpan(text: 'Hamara', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
                  TextSpan(text: 'Service', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.brand)),
                ])),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('PROVIDER APP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5)),
                ),
                const SizedBox(height: 48),
                const SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white54))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
