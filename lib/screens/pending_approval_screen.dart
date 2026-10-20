import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/provider_api_service.dart';
import '../utils/support_contact.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Shown to providers whose account is still `pending`. They keep their JWT
/// (so the status can be re-checked) but `provider_logged_in` stays false.
class PendingApprovalScreen extends StatefulWidget {
  final String name;
  final String email;
  const PendingApprovalScreen({super.key, required this.name, required this.email});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    loadSupportConfig().then((_) { if (mounted) setState(() {}); });
    // So the "account approved" push reaches this device.
    NotificationService.registerToken();
  }

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    final res = await ProviderApiService.getMyProfile();
    if (!mounted) return;
    setState(() => _checking = false);
    if (res.unauthorized) return; // global handler routes to login
    if (!res.ok) {
      _snack(res.error, AppColors.red);
      return;
    }
    final p = res.map ?? {};
    final status = '${p['status'] ?? 'pending'}';
    if (status == 'approved') {
      await ProviderApiService.markLoggedIn(true);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => DashboardScreen(providerId: '${p['id'] ?? ''}')),
          (_) => false);
    } else if (status == 'pending' || status == 'review') {
      _snack('Still under review. We will notify you when approved.', AppColors.teal);
    } else {
      await ProviderApiService.clearToken();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen(message: 'Account $status. Contact ${supportConfigNow.email}')),
          (_) => false);
    }
  }

  Future<void> _logout() async {
    await ProviderApiService.clearToken();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _contactSupport() async {
    final cached = await ProviderApiService.getCachedProvider();
    if (!mounted) return;
    final id = '${cached?['id'] ?? ''}';
    await openSupport(context,
        providerId: id,
        extra: 'My application (${widget.email}) is pending approval.');
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
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
                Text('Hi ${widget.name}! Your provider application is being reviewed by our team.',
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
                if (widget.email.isNotEmpty)
                  Text('Registered with: ${widget.email}',
                    style: const TextStyle(fontSize: 13, color: AppColors.ink2)),
                const SizedBox(height: 8),
                Text('For support: ${supportConfigNow.email}',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _checking
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check Approval Status',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: _checking ? null : _checkStatus,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.support_agent_rounded, size: 18),
                    label: const Text('Contact Support',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: _contactSupport,
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
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.teal),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Log Out',
                      style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
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
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
    ]);
  }
}
