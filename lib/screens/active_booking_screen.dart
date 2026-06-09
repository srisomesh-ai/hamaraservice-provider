import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';

class ActiveBookingScreen extends StatefulWidget {
  final String bookingKey;
  final Map<String, dynamic> booking;
  const ActiveBookingScreen({super.key, required this.bookingKey, required this.booking});
  @override
  State<ActiveBookingScreen> createState() => _ActiveBookingScreenState();
}

class _ActiveBookingScreenState extends State<ActiveBookingScreen> {
  String _status = 'accepted';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _status = widget.booking['status'] ?? 'accepted';
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _loading = true);
    await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingKey}').update({
      'status': newStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    setState(() { _status = newStatus; _loading = false; });
  }

  Future<void> _completeBooking() async {
    setState(() => _loading = true);
    await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingKey}').update({
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    });
    // Move to bookings history
    await FirebaseDatabase.instance.ref('bookings/${widget.bookingKey}').update({
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    });
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Job Completed! 🎉', style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text('Great work! The booking has been marked as completed.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
              },
              child: const Text('Done', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
  }

  void _callCustomer() {
    final phone = widget.booking['phone'] ?? '';
    if (phone.isNotEmpty) launchUrl(Uri.parse('tel:$phone'));
  }

  void _openMaps() {
    final address = Uri.encodeComponent(widget.booking['address'] ?? '');
    launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$address'));
  }

  @override
  Widget build(BuildContext context) {
    final bk = widget.booking;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Active Booking'),
        backgroundColor: AppColors.teal,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D3D47), AppColors.teal],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Text('🔧', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bk['service'] ?? 'Service',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('Status: $_status', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ])),
                Text('₹${bk['price'] ?? bk['priceVal'] ?? 0}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),

            const SizedBox(height: 16),

            // Customer details
            _card('Customer Details', [
              _detailRow('👤', 'Name', bk['customer'] ?? ''),
              _detailRow('📞', 'Phone', bk['phone'] ?? ''),
              _detailRow('📅', 'Date & Time', '${bk['date'] ?? ''} at ${bk['time'] ?? ''}'),
              _detailRow('📍', 'Address', bk['address'] ?? ''),
            ]),

            const SizedBox(height: 12),

            // Summary chips
            if ((bk['summary'] as List?)?.isNotEmpty == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Selected Services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6,
                    children: (bk['summary'] as List).map((s) {
                      final parts = s.toString().split(' > ');
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.teal.withOpacity(0.3))),
                        child: Text(parts.length > 1 ? parts.sublist(1).join(' › ') : s.toString(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
                      );
                    }).toList()),
                ]),
              ),

            const SizedBox(height: 16),

            // Action buttons
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _callCustomer,
                  icon: const Icon(Icons.phone_rounded, color: AppColors.teal),
                  label: const Text('Call', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: const BorderSide(color: AppColors.teal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openMaps,
                  icon: const Icon(Icons.map_rounded, color: AppColors.brand),
                  label: const Text('Navigate', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: const BorderSide(color: AppColors.brand),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 12),

            if (_status == 'accepted')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : () => _updateStatus('active'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('🚀 Start Service', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),

            if (_status == 'active')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _completeBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Text('✅ Mark as Complete', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _detailRow(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ])),
      ]),
    );
  }
}
