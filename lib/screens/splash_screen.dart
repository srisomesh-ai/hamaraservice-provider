import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import 'intro_screen.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'pending_approval_screen.dart';
import '../services/provider_api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _error = '');
    final prefs = await SharedPreferences.getInstance();
    final introSeen = prefs.getBool('provider_intro_seen') ?? false;
    if (!introSeen) return _go(const IntroScreen());

    if (!await ProviderApiService.hasToken()) return _go(const LoginScreen());

    final res = await ProviderApiService.getMyProfile();
    if (!mounted) return;
    if (res.unauthorized) return; // global 401 handler routes to login

    if (!res.ok) {
      if (res.networkError || res.status >= 500) {
        // Offline: let approved providers in with cached data; others retry.
        final loggedIn = prefs.getBool('provider_logged_in') ?? false;
        final pid = prefs.getString('provider_id') ?? '';
        if (loggedIn && pid.isNotEmpty) return _go(DashboardScreen(providerId: pid));
        setState(() => _error = res.error);
        return;
      }
      // 400/404 → token no longer maps to a provider
      await ProviderApiService.clearToken();
      return _go(const LoginScreen());
    }

    final p = res.map ?? {};
    final status = '${p['status'] ?? 'pending'}';
    final pid = '${p['id'] ?? ''}';
    await prefs.setString('provider_id', pid);
    if (status == 'approved') {
      await ProviderApiService.markLoggedIn(true);
      return _go(DashboardScreen(providerId: pid));
    }
    await ProviderApiService.markLoggedIn(false);
    if (status == 'pending' || status == 'review') {
      return _go(PendingApprovalScreen(
          name: '${p['name'] ?? 'Provider'}', email: '${p['email'] ?? ''}'));
    }
    await ProviderApiService.clearToken();
    await _go(LoginScreen(message: status == 'suspended'
        ? 'Account suspended. Contact support.'
        : status == 'rejected'
            ? 'Application rejected. Contact support.'
            : 'Account $status. Contact support.'));
  }

  Future<void> _go(Widget screen) async {
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
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
                if (_error.isEmpty)
                  const SizedBox(width: 28, height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white54)))
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _navigate,
                    child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
