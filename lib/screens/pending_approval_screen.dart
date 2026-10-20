import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/provider_api_service.dart';
import '../utils/support_contact.dart';
import '../utils/theme.dart';
import '../widgets/ui.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Shown to providers whose account is still `pending`. They keep their JWT
/// (so the status can be re-checked) but `provider_logged_in` stays false.
class PendingApprovalScreen extends StatefulWidget {
  final String name;
  final String email;
  /// Just registered → "Hi <name>! Application submitted."
  final bool submitted;
  const PendingApprovalScreen(
      {super.key, required this.name, required this.email, this.submitted = false});

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
      _snack('🎉 Approved! Welcome aboard', AppColors.green);
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => DashboardScreen(providerId: '${p['id'] ?? ''}')),
          (_) => false);
    } else if (status == 'pending' || status == 'review') {
      _snack('Still under review — we will notify you', AppColors.teal);
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
    showSnack(context, msg,
        tone: color == AppColors.red ? Tone.error : color == AppColors.green ? Tone.success : Tone.neutral);
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
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 96, height: 96,
                  decoration: const BoxDecoration(color: AppColors.yellowSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.hourglass_top_rounded, color: AppColors.yellow, size: 48),
                ),
              ),
              const SizedBox(height: 24),
              Text('Application Under Review', textAlign: TextAlign.center, style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(widget.submitted ? 'Hi ${widget.name}! Application submitted.' : widget.name,
                  textAlign: TextAlign.center, style: t.titleMedium?.copyWith(color: AppColors.ink2)),
              const SizedBox(height: 6),
              Text('Approval usually takes 24–48 hours.',
                  textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              if (widget.email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(widget.email, textAlign: TextAlign.center, style: t.bodySmall),
              ],
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    _infoRow(Icons.check_circle_outline_rounded, AppColors.green,
                        'Application received', 'We have your details'),
                    _infoRow(Icons.manage_search_rounded, AppColors.yellow,
                        'Under review', 'Usually takes 24–48 hours'),
                    _infoRow(Icons.notifications_active_outlined, AppColors.teal,
                        'Approval notification', 'You will get notified when approved'),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              BigButton('Check Approval Status',
                  icon: Icons.refresh_rounded, busy: _checking, onPressed: _checkStatus),
              const SizedBox(height: 12),
              BigButton('Contact support on WhatsApp',
                  icon: Icons.chat_outlined, outlined: true, onPressed: _contactSupport),
              const SizedBox(height: 4),
              TextButton(onPressed: _logout, child: const Text('Use Different Account')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String title, String sub) => ListTile(
        leading: IconTile(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
      );
}
