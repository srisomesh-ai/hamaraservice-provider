import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/support_contact.dart';
import '../utils/theme.dart';

class SupportScreen extends StatefulWidget {
  final String providerName;
  final String providerEmail;
  final String providerId;
  const SupportScreen({
    super.key,
    this.providerName = '',
    this.providerEmail = '',
    this.providerId = '',
  });
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _msgCtrl = TextEditingController();
  String _selectedType = 'complaint';
  bool _submitting = false;
  bool _submitted = false;

  final List<Map<String, dynamic>> _types = [
    {'key': 'complaint',   'icon': '⚠️', 'label': 'Complaint'},
    {'key': 'suggestion',  'icon': '💡', 'label': 'Suggestion'},
    {'key': 'add_service', 'icon': '➕', 'label': 'Add Service'},
    {'key': 'payment',     'icon': '💰', 'label': 'Payment Issue'},
    {'key': 'technical',   'icon': '🔧', 'label': 'Technical Issue'},
    {'key': 'other',       'icon': '📝', 'label': 'Other'},
  ];

  Future<void> _submitRequest() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your issue'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _submitting = true);
    final type = _types.firstWhere((t) => t['key'] == _selectedType,
        orElse: () => _types.last)['label'] as String;
    final uri = supportMailto(
      subject: 'Provider support: $type${widget.providerId.isNotEmpty ? ' (${widget.providerId})' : ''}',
      body: '$msg\n\n---\nProvider: ${widget.providerName}\n'
          'Email: ${widget.providerEmail}\nProvider ID: ${widget.providerId}\n',
    );
    bool opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {}
    if (!mounted) return;
    setState(() { _submitting = false; _submitted = opened; });
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No email app found. Please write to $kSupportEmail'),
        backgroundColor: AppColors.red));
    }
  }

  Future<void> _open(Uri uri, {bool external = false}) async {
    bool ok = false;
    try {
      ok = await launchUrl(uri,
          mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open. Please write to $kSupportEmail'),
        backgroundColor: AppColors.red));
    }
  }

  void _callSupport() => _open(Uri.parse('tel:+91$kSupportPhone'));
  void _whatsappSupport() => _open(
      Uri.parse('https://wa.me/91$kSupportPhone?text=${Uri.encodeComponent('Hi, I need help with my provider account')}'),
      external: true);
  void _emailSupport() => _open(supportMailto(
      subject: 'Provider support${widget.providerId.isNotEmpty ? ' (${widget.providerId})' : ''}',
      body: ''));

  @override
  void dispose() { _msgCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: AppColors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Quick contact
            const Text('CONTACT US', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: AppColors.muted, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Row(children: [
              if (hasSupportPhone) ...[
                _contactBtn('📞', 'Call', AppColors.teal, _callSupport),
                const SizedBox(width: 10),
                _contactBtn('💬', 'WhatsApp', const Color(0xFF25D366), _whatsappSupport),
                const SizedBox(width: 10),
              ],
              _contactBtn('📧', 'Email $kSupportEmail', AppColors.brand, _emailSupport),
            ]),

            const SizedBox(height: 24),

            // Submit request
            const Text('RAISE A REQUEST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: AppColors.muted, letterSpacing: 0.8)),
            const SizedBox(height: 10),

            if (_submitted) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.green.withOpacity(0.3)),
                ),
                child: Column(children: [
                  const Text('✅', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text('Email app opened',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.green)),
                  const SizedBox(height: 6),
                  const Text('Send the email from your mail app. We usually reply within 24 hours.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _submitted = false),
                    child: const Text('Submit Another', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Request type
                  const Text('Type of Request',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _types.map((t) {
                      final sel = t['key'] == _selectedType;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedType = t['key'] as String),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.tealSoft : AppColors.bg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? AppColors.teal : AppColors.line,
                              width: sel ? 2 : 1),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(t['icon'] as String, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(t['label'] as String,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: sel ? AppColors.teal : AppColors.ink2)),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Message
                  const Text('Describe your issue',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _msgCtrl,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Tell us what happened or what you need...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Provider info (auto-filled)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.person_rounded, color: AppColors.muted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '${widget.providerName} · ${widget.providerEmail}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      )),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _submitting
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : const Text('Send via Email',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 24),

            // FAQ
            const Text('QUICK HELP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: AppColors.muted, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            _faqItem('How do I get approved?',
              'After registering, admin reviews your profile and approves within 24 hours.'),
            _faqItem('How do I add more services?',
              'Go to Dashboard → My Services → Edit My Services to add or remove services.'),
            _faqItem('When will I get paid?',
              'Online payments are added to your wallet; withdraw from Earnings. Cash jobs add the platform commission to your dues.'),
            _faqItem('My booking alert is not showing',
              'Keep the app open and Online, allow location, and make sure your services are enabled in My Services.'),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _contactBtn(String emoji, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _faqItem(String q, String a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: ExpansionTile(
        title: Text(q, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        iconColor: AppColors.teal,
        collapsedIconColor: AppColors.muted,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(a, style: const TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
