import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/provider_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl   = TextEditingController();
  bool _loading    = false;
  bool _showPwd    = false;
  String _error    = '';

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pwd   = _pwdCtrl.text.trim();
    if (email.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      // Login via MySQL API — checks email+password+status
      final result = await ProviderApiService.login(email, pwd);

      if (result == null) {
        setState(() { _loading = false; _error = 'Email or password incorrect.'; });
        return;
      }

      final provider = result['provider'] as Map<String,dynamic>? ?? {};
      final status   = provider['status']?.toString() ?? 'pending';

      if (status == 'suspended') {
        setState(() { _loading = false; _error = 'Your account has been suspended. Please contact support.'; });
        return;
      }
      if (status == 'rejected') {
        setState(() { _loading = false; _error = 'Your application was rejected. Please contact support.'; });
        return;
      }
      if (status != 'approved') {
        setState(() { _loading = false; });
        if (mounted) {
          Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => _PendingApprovalScreen(
              name:  provider['name']?.toString() ?? 'Provider',
              email: email,
            )));
        }
        return;
      }

      final providerId = provider['id']?.toString() ?? '';
      if (mounted) {
        Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => DashboardScreen(providerId: providerId)));
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Connection error. Please try again.'; });
    }
  }

  @override
  void dispose() { _emailCtrl.dispose(); _pwdCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3D47), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 60),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: const Icon(Icons.home_repair_service_rounded, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 16),
                const Text('Provider App', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Sign in to receive bookings', style: TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Welcome Back!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      const Text('Use your HamaraService provider credentials',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      const SizedBox(height: 24),

                      // Email
                      const Text('EMAIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'your@email.com',
                          prefixIcon: const Icon(Icons.email_rounded, color: AppColors.muted, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password
                      const Text('PASSWORD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _pwdCtrl,
                        obscureText: !_showPwd,
                        decoration: InputDecoration(
                          hintText: 'Your password',
                          prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.muted, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
                            onPressed: () => setState(() => _showPwd = !_showPwd),
                          ),
                        ),
                      ),

                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5F5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFC8181)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFE53E3E)))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _loading
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation(Colors.white)))
                              : const Text('Login to Dashboard',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Register link
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: const Text('New provider? Register here',
                            style: TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pending Approval Screen ───────────────────────────────────────────────
class _PendingApprovalScreen extends StatelessWidget {
  final String name;
  final String email;
  const _PendingApprovalScreen({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3D47), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.yellow, width: 2)),
                  child: const Icon(Icons.hourglass_top_rounded,
                    color: AppColors.yellow, size: 44),
                ),
                const SizedBox(height: 28),
                const Text('Application Under Review',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 12),
                Text('Hi $name! Your provider application is being reviewed by our team.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.5)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                  child: Column(children: [
                    _infoRow(Icons.check_circle_outline_rounded, AppColors.green,
                      'Application received', 'We have your details'),
                    const SizedBox(height: 14),
                    _infoRow(Icons.manage_search_rounded, AppColors.yellow,
                      'Under review', 'Usually takes 24–48 hours'),
                    const SizedBox(height: 14),
                    _infoRow(Icons.notifications_active_rounded, AppColors.muted,
                      'Approval notification', 'You will get notified when approved'),
                  ]),
                ),
                const SizedBox(height: 28),
                Text('Registered with: $email',
                  style: const TextStyle(fontSize: 13, color: Colors.white60)),
                const SizedBox(height: 8),
                const Text('For support: info@hamaraservice.com',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 24),
                // Contact support button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.support_agent_rounded, size: 18),
                    label: const Text('Contact Support',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      final uri = Uri.parse(
                        'mailto:info@hamaraservice.com'
                        '?subject=Provider%20Account%20Query%20--%20$email'
                        '&body=Hi%20HamaraService%20Team%2C%0A%0AI%20registered%20as%20a%20provider%20with%20email%3A%20$email%0A%0APlease%20help%20me%20with%20my%20application.%0A%0AThank%20you.'
                      );
                      // ignore: deprecated_member_use
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Back to Login',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String title, String sub) {
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20)),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
    ]);
  }
}
