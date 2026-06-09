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
  bool _loading = false;
  String _error = '';

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => _loading = false); return; }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user != null) {
        // Save provider profile to Firebase
        await FirebaseDatabase.instance.ref('providers/${user.uid}').update({
          'id': user.uid,
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'photo': user.photoURL ?? '',
          'status': 'pending',
          'available': false,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Sign in failed. Please try again.'; });
    }
  }

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
                const Text('Earn by serving customers', style: TextStyle(fontSize: 14, color: Colors.white70)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Welcome, Professional! 👋',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: 6),
                      const Text('Sign in to start receiving bookings',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      const SizedBox(height: 24),
                      if (_error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFC8181))),
                          child: Text(_error, style: const TextStyle(fontSize: 13, color: Color(0xFFE53E3E))),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity, height: 52,
                        child: OutlinedButton(
                          onPressed: _loading ? null : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.line, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _loading
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(AppColors.teal)))
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Image.network('https://www.google.com/favicon.ico', width: 20, height: 20,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 22, color: AppColors.teal)),
                                  const SizedBox(width: 10),
                                  const Text('Continue with Google', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                                ]),
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
