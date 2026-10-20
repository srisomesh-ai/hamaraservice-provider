import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';
import '../widgets/ui.dart';
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
      _error = 'Your session expired — please login again.';
    }
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pwd   = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() { _error = 'Enter email and password'; _noAccount = false; });
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
      // 404 NOT_REGISTERED → unknown email: offer registration (the email is
      // carried over, never the password). Anything else (e.g. 400 "Incorrect
      // password. Please try again.") → show the server's text as is.
      final noAccount = res.status == 404 || res.error.startsWith('NOT_REGISTERED');
      setState(() {
        _loading = false;
        _noAccount = noAccount;
        _error = noAccount ? 'No provider account found for this email.' : res.error;
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
    } else if (status == 'pending' || status == 'review') {
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
    final t = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay.copyWith(statusBarColor: AppColors.teal2),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: AppColors.teal2,
              padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 32, 24, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.home_repair_service_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 20),
                Text('Provider Login',
                    style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Sign in to receive bookings from HamaraService customers',
                    style: t.bodyMedium?.copyWith(color: Colors.white70)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pwdCtrl,
                    obscureText: !_showPwd,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _loading ? null : _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_showPwd ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showPwd = !_showPwd),
                      ),
                    ),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Notice(_error,
                        tone: Tone.error,
                        action: _noAccount
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => RegisterScreen(
                                          prefillEmail: _emailCtrl.text.trim().toLowerCase()))),
                                  child: const Text('Register as provider →'),
                                ),
                              )
                            : null),
                  ],
                  const SizedBox(height: 24),
                  BigButton('Login', busy: _loading, onPressed: _login),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR', style: t.bodySmall),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 24),
                  BigButton('Register as Provider',
                      icon: Icons.person_add_alt_1_rounded,
                      color: AppColors.brand,
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const RegisterScreen()))),
                  const SizedBox(height: 10),
                  Text('New to HamaraService? Create your provider account',
                      textAlign: TextAlign.center, style: t.bodySmall),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
