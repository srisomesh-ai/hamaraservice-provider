import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';
import 'pending_approval_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Shown above the form, e.g. after a 401 or for a suspended account.
  final String? message;
  final bool sessionExpired;
  const LoginScreen({super.key, this.message, this.sessionExpired = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl   = TextEditingController();
  bool _loading    = false;
  bool _showPwd    = false;
  String _error    = '';

  bool _noAccount  = false;

  @override
  void initState() {
    super.initState();
    if (widget.message != null && widget.message!.isNotEmpty) {
      _error = widget.message!;
    } else if (widget.sessionExpired) {
      _error = 'Your session has expired. Please log in again.';
    }
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pwd   = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() { _error = 'Please enter email and password'; _noAccount = false; });
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() { _error = 'Please enter a valid email address'; _noAccount = false; });
      return;
    }
    setState(() { _loading = true; _error = ''; _noAccount = false; });

    final res = await ProviderApiService.login(email, pwd);
    if (!mounted) return;

    if (!res.ok) {
      // Unknown email? Offer registration (never prefill the password).
      bool noAccount = false;
      if (!res.networkError && res.status < 500) {
        noAccount = (await ProviderApiService.checkEmailExists(email)) == false;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _noAccount = noAccount;
        _error = noAccount ? 'No account found for $email.' : res.error;
      });
      return;
    }

    final data     = res.map ?? {};
    final provider = data['provider'] is Map
        ? Map<String, dynamic>.from(data['provider'] as Map)
        : <String, dynamic>{};
    final status   = '${data['status'] ?? provider['status'] ?? 'pending'}';
    final providerId = '${provider['id'] ?? ''}';

    await NotificationService.registerToken();
    if (!mounted) return;
    setState(() => _loading = false);

    if (status == 'approved') {
      Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => DashboardScreen(providerId: providerId)),
        (_) => false);
    } else if (status == 'pending') {
      Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => PendingApprovalScreen(
          name: '${provider['name'] ?? 'Provider'}', email: email)),
        (_) => false);
    } else {
      await ProviderApiService.clearToken();
      if (mounted) setState(() => _error = 'Account $status. Contact info@hamaraservice.com');
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
                        if (_noAccount) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.person_add_rounded, size: 18, color: AppColors.brand),
                              label: const Text('No account found — Register?',
                                style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => RegisterScreen(
                                  prefillEmail: _emailCtrl.text.trim().toLowerCase()))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.brand),
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                        ],
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

                      // Divider
                      const SizedBox(height: 8),
                      Row(children: [
                        const Expanded(child: Divider(color: AppColors.line)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                        const Expanded(child: Divider(color: AppColors.line)),
                      ]),
                      const SizedBox(height: 12),
                      // Big Register button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_rounded, size: 22),
                          label: const Text('REGISTER AS PROVIDER',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                          onPressed: () => Navigator.push(context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                            elevation: 3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('New to HamaraService? Create your provider account',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 11)),
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

