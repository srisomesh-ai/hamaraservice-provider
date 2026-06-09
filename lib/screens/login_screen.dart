import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl   = TextEditingController();
  final _nameCtrl  = TextEditingController();
  bool _loading    = false;
  bool _isRegister = false;
  bool _showPwd    = false;
  String _error    = '';

  Future<void> _saveProviderProfile(User user) async {
    final ref = FirebaseDatabase.instance.ref('providers/${user.uid}');
    final snap = await ref.get();

    if (snap.exists) {
      // Provider already exists — only update name/email/photo, NEVER touch status or services
      await ref.update({
        'name':      user.displayName ?? '',
        'email':     user.email ?? '',
        'photo':     user.photoURL ?? '',
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } else {
      // New provider — create with pending status
      await ref.set({
        'id':        user.uid,
        'name':      user.displayName ?? _nameCtrl.text.trim(),
        'email':     user.email ?? '',
        'photo':     user.photoURL ?? '',
        'status':    'pending',
        'available': false,
        'services':  [],
        'totalJobs': 0,
        'rating':    5.0,
        'totalEarnings': 0,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _signInGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => _loading = false); return; }
      final googleAuth = await googleUser.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(cred);
      if (result.user != null) await _saveProviderProfile(result.user!);
      if (mounted) Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } catch (e) {
      setState(() { _loading = false; _error = 'Google sign in failed. Try again.'; });
    }
  }

  Future<void> _signInEmail() async {
    final email = _emailCtrl.text.trim();
    final pwd   = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      if (result.user != null) await _saveProviderProfile(result.user!);
      if (mounted) Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } on FirebaseAuthException catch (e) {
      final msgs = {
        'user-not-found':    'No account with this email. Please register.',
        'wrong-password':    'Incorrect password.',
        'invalid-email':     'Invalid email format.',
        'invalid-credential':'Incorrect email or password.',
      };
      setState(() { _loading = false; _error = msgs[e.code] ?? 'Sign in failed.'; });
    }
  }

  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final pwd   = _pwdCtrl.text;
    final name  = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter your full name'); return; }
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    if (pwd.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
      await result.user?.updateDisplayName(name);
      await _saveProviderProfile(result.user!);
      if (mounted) Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } on FirebaseAuthException catch (e) {
      final msgs = {
        'email-already-in-use': 'Email already registered. Please sign in.',
        'weak-password':        'Password too weak.',
      };
      setState(() { _loading = false; _error = msgs[e.code] ?? 'Registration failed.'; });
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) { setState(() => _error = 'Enter your email first'); return; }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent!'), backgroundColor: AppColors.green));
    } catch (e) {
      setState(() => _error = 'Could not send reset email.');
    }
  }

  @override
  void dispose() { _emailCtrl.dispose(); _pwdCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

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
                const SizedBox(height: 48),
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: const Icon(Icons.home_repair_service_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 12),
                const Text('Provider App', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Earn by serving customers', style: TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_isRegister ? 'Create Account' : 'Welcome Back!',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(_isRegister ? 'Register as a service provider' : 'Sign in to receive bookings',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: OutlinedButton(
                          onPressed: _loading ? null : _signInGoogle,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.line, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Image.network('https://www.google.com/favicon.ico', width: 20, height: 20,
                              errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 22, color: AppColors.teal)),
                            const SizedBox(width: 10),
                            const Text('Continue with Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        const Expanded(child: Divider(color: AppColors.line)),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                        const Expanded(child: Divider(color: AppColors.line)),
                      ]),
                      const SizedBox(height: 16),
                      if (_isRegister) ...[
                        _fieldLabel('Full Name'),
                        const SizedBox(height: 6),
                        TextField(controller: _nameCtrl,
                          decoration: InputDecoration(hintText: 'Your full name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                        const SizedBox(height: 12),
                      ],
                      _fieldLabel('Email'),
                      const SizedBox(height: 6),
                      TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(hintText: 'you@email.com',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 12),
                      _fieldLabel('Password'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _pwdCtrl, obscureText: !_showPwd,
                        decoration: InputDecoration(
                          hintText: _isRegister ? 'Min 8 characters' : 'Your password',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
                            onPressed: () => setState(() => _showPwd = !_showPwd)),
                        ),
                      ),
                      if (!_isRegister) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                            child: const Text('Forgot password?', style: TextStyle(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFC8181))),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFE53E3E)))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity, height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : (_isRegister ? _register : _signInEmail),
                          child: _loading
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                              : Text(_isRegister ? 'Create Account' : 'Sign In',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() { _isRegister = !_isRegister; _error = ''; }),
                          child: Text(
                            _isRegister ? 'Already registered? Sign In' : 'New provider? Register',
                            style: const TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600),
                          ),
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

  Widget _fieldLabel(String text) => Text(text.toUpperCase(),
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5));
}
