import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/provider_api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';

class ActiveBookingScreen extends StatefulWidget {
  final String bookingKey;
  final Map<String, dynamic> booking;
  final String providerId;
  const ActiveBookingScreen({
    super.key,
    required this.bookingKey,
    required this.booking,
    required this.providerId,
  });
  @override
  State<ActiveBookingScreen> createState() => _ActiveBookingScreenState();
}

class _ActiveBookingScreenState extends State<ActiveBookingScreen> {
  String _status = 'accepted';
  bool _loading = false;
  bool _showOtpEntry = false;
  Map<String,dynamic> _liveBooking = {};
  bool _negotiationHandled = false;
  final List<TextEditingController> _otpCtrls = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(4, (_) => FocusNode());
  String _otpError = '';
  StreamSubscription? _statusWatcher;

  @override
  void initState() {
    super.initState();
    _status = widget.booking['status'] ?? 'accepted';
    _watchStatus();
  }

  @override
  void dispose() {
    _statusWatcher?.cancel();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  void _watchStatus() {
    _statusWatcher = Stream.periodic(const Duration(seconds: 3))
        .asyncMap((_) => ProviderApiService.getBooking(widget.bookingKey))
        .listen((data) {
      if (data == null || !mounted) return;
      final status = data['status']?.toString() ?? '';
      if (status.isNotEmpty) setState(() { _status = status; _liveBooking = data; });

      // Customer negotiating — show negotiation dialog to provider
      if (status == 'negotiating' && !_negotiationHandled) {
        _negotiationHandled = true;
        final counter = (data['counterPrice'] as num?)?.toInt();
        final custName = data['customerName']?.toString() ?? 'Customer';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showNegotiationDialog(counter, custName, data);
        });
      }

      // Customer paid — show success snackbar
      if (status == 'completed') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🎉 Payment received! Job completed.'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 4)));
      }
    });
  }

  // ── Negotiation dialog shown to provider when customer counters ──────────
  void _showNegotiationDialog(int? counterPrice, String custName, Map<String,dynamic> bk) {
    final finalCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.handshake_rounded, color: AppColors.brand, size: 24),
            SizedBox(width: 8),
            Text('Price Negotiation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(custName, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // Show customer's counter if they sent one
          if (counterPrice != null && counterPrice > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brand.withOpacity(0.3))),
              child: Column(children: [
                const Text('CUSTOMER COUNTER OFFER',
                  style: TextStyle(fontSize:10, fontWeight:FontWeight.w800,
                    color:AppColors.muted, letterSpacing:.5)),
                const SizedBox(height:6),
                Text('₹$counterPrice',
                  style: const TextStyle(fontSize:32, fontWeight:FontWeight.w900, color:AppColors.brand)),
              ])),
            const SizedBox(height:14),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.yellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.yellow, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Customer wants to negotiate the price.',
                  style: TextStyle(fontSize:12, color:AppColors.ink))),
              ])),
            const SizedBox(height:14),
          ],
          // Final offer input
          TextField(
            controller: finalCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Your final offer (₹)',
              prefixText: '₹ ',
              hintText: counterPrice != null ? 'e.g. ${counterPrice + 10}' : 'Enter final price',
              helperText: 'This is your ONE final offer — choose wisely',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.teal, width: 2))),
          ),
        ]),
        actions: [
          // Decline — release job, customer searches another
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _declineNegotiation();
            },
            child: const Text('Decline', style: TextStyle(color: AppColors.red))),
          // Accept customer's counter price
          if (counterPrice != null && counterPrice > 0)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _acceptCounterPrice(counterPrice);
              },
              child: Text('Accept ₹$counterPrice',
                style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700))),
          // Send final offer
          ElevatedButton(
            onPressed: () async {
              final fp = int.tryParse(finalCtrl.text.trim()) ?? 0;
              if (fp <= 0) return;
              Navigator.pop(ctx);
              await _sendFinalOffer(fp);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Send Final Offer',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  // Provider accepts customer's counter price
  Future<void> _acceptCounterPrice(int price) async {
    try {
      await ProviderApiService.acceptCounter(widget.bookingKey);
      // Notify customer
      await _notifyCustomer(
        event: 'price_confirmed',
        title: 'Price Accepted! ✅',
        body:  'Provider accepted ₹$price. Booking confirmed!',
        extra: {'confirmedPrice': price.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Accepted ₹$price — booking confirmed!'),
          backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
  }

  // Provider sends final offer (one time only)
  Future<void> _sendFinalOffer(int finalPrice) async {
    try {
      await ProviderApiService.sendFinalOffer(widget.bookingKey, finalPrice);
      // Notify customer
      await _notifyCustomer(
        event: 'negotiation_final',
        title: "Provider's Final Offer 💰",
        body:  "Provider's final price: ₹$finalPrice. Accept or search another provider.",
        extra: {'finalPrice': finalPrice.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Final offer ₹$finalPrice sent to customer'),
          backgroundColor: AppColors.teal));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
  }

  // Provider declines negotiation — release job for another provider
  Future<void> _declineNegotiation() async {
    try {
      await ProviderApiService.cancelBooking(widget.bookingKey);
      // Notify customer to search another
      await _notifyCustomer(
        event: 'provider_declined',
        title: 'Provider Declined',
        body:  'The provider declined negotiation. Searching for another provider...',
        extra: {},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
  }

  // Helper — notify customer via FCM
  Future<void> _notifyCustomer({
    required String event,
    required String title,
    required String body,
    required Map<String,String> extra,
  }) async {
    try {
      final custId = (_liveBooking['customerId'] ?? widget.booking['customerId'])?.toString() ?? '';
      if (custId.isEmpty) return;
      final custProfile = await ProviderApiService.getBooking(widget.bookingKey);
      final token = custProfile?['customer_fcm_token']?.toString() ?? '';
      if (token.isEmpty) return;
      await http.post(
        Uri.parse('https://notifybooking-mlchyp6tra-as.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event':    event,
          'fcmToken': token,
          'data':     {'title': title, 'body': body, ...extra},
        }),
      );
    } catch (_) {}
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _loading = true);
    // Status update handled by MySQL API actions
    setState(() { _status = newStatus; _loading = false; });
  }

  Future<void> _initiateOTP() async {
    setState(() => _loading = true);
    final otp = (1000 + Random().nextInt(9000)).toString();

    // customerId MUST be written — customer listener filters by this field
    final custId = widget.booking['customerId']?.toString() ?? '';
    // OTP generated and stored by MySQL verify_otp API

    // Notify customer — OTP required (push notification)
    try {
      final custId = widget.booking['customerId']?.toString() ?? '';
      if (custId.isNotEmpty) {
        final fcmToken = ''; // FCM sent by MySQL API
        if (fcmToken.isNotEmpty) {
          await http.post(
            Uri.parse('https://notifybooking-mlchyp6tra-as.a.run.app'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event': 'otp_requested',
              'fcmToken': fcmToken,
              'data': {
                'otp': otp,
                'service': widget.booking['service']?.toString() ?? '',
              },
            }),
          );
        }
      }
    } catch (_) {}
    // OTP status stored in MySQL

    setState(() { _status = 'otp_sent'; _showOtpEntry = true; _loading = false; });
  }

  Future<void> _verifyOTP() async {
    final entered = _otpCtrls.map((c) => c.text).join('');
    if (entered.length < 4) {
      setState(() => _otpError = 'Please enter all 4 digits');
      return;
    }
    // Verify OTP via MySQL API
    final otpResult = await ProviderApiService.verifyOtp(widget.bookingKey, entered);
    final correctOtp = otpResult != null ? entered : '';

    if (entered != correctOtp) {
      setState(() => _otpError = 'Incorrect OTP. Ask customer to check their app.');
      HapticFeedback.heavyImpact();
      for (final c in _otpCtrls) c.clear();
      _otpFocus[0].requestFocus();
      return;
    }

    setState(() { _loading = true; _otpError = ''; });

    // OTP verified — MySQL API already updated booking status to payment_pending

    // Provider stats updated by MySQL API

    setState(() { _loading = false; _status = 'payment_pending'; });

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('OTP Verified! ✅', style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text('Service verified! Waiting for customer to complete payment.'),
          actions: [
            TextButton(
              onPressed: () {
                // Close dialog
                Navigator.pop(context);
                // Close OTP screen and go back to dashboard
                if (mounted) Navigator.pop(context);
              },
              child: const Text('OK', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
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
    final lat = widget.booking['lat'];
    final lng = widget.booking['lng'];

    // Use GPS coordinates if available and valid
    if (lat != null && lng != null) {
      final latD = (lat is num) ? lat.toDouble() : double.tryParse(lat.toString()) ?? 0.0;
      final lngD = (lng is num) ? lng.toDouble() : double.tryParse(lng.toString()) ?? 0.0;
      if (latD != 0.0 && lngD != 0.0) {
        launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latD,$lngD&travelmode=driving'));
        return;
      }
    }
    // Fallback to address
    final address = Uri.encodeComponent(widget.booking['address'] ?? '');
    if (address.isNotEmpty) {
      launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$address&travelmode=driving'));
    }
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
        child: Column(children: [
          // Status banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0D3D47), AppColors.teal],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const Text('🔧', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bk['service'] ?? 'Service',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('Status: ${_statusLabel(_status)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
              Text('₹${bk['price'] ?? bk['priceVal'] ?? 0}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),

          const SizedBox(height: 16),

          // Customer details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Customer Details',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 12),
              _detailRow(Icons.person_rounded, 'Name', bk['customer'] ?? ''),
              _detailRow(Icons.phone_rounded, 'Phone', bk['phone'] ?? ''),
              _detailRow(Icons.calendar_today_rounded, 'Date & Time',
                '${bk['date'] ?? ''} at ${bk['time'] ?? ''}'),
              _detailRow(Icons.location_on_rounded, 'Address', bk['address'] ?? ''),
              _detailRow(Icons.currency_rupee_rounded, 'Amount',
                '₹${bk['price'] ?? bk['priceVal'] ?? 0}'),
            ]),
          ),

          // Summary chips
          if ((bk['summary'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Selected Services',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6,
                  children: (bk['summary'] as List).map((s) {
                    final parts = s.toString().split(' > ');
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.teal.withOpacity(0.3))),
                      child: Text(parts.length > 1 ? parts.sublist(1).join(' › ') : s.toString(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
                    );
                  }).toList()),
              ]),
            ),
          ],

          const SizedBox(height: 16),

          // Call & Navigate buttons
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
                icon: const Icon(Icons.navigation_rounded, color: AppColors.brand),
                label: const Text('Navigate', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: AppColors.brand),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Action buttons
          // Price quoted — waiting for customer response
          if (_status == 'price_quoted') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.teal.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.hourglass_top_rounded, color: AppColors.teal, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('Waiting for customer to accept your price...',
                  style: TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600))),
              ])),
          ],

          // Negotiating — waiting for dialog or watching
          if (_status == 'negotiating') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.brand.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.handshake_rounded, color: AppColors.brand, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Customer is negotiating the price...',
                  style: TextStyle(fontSize: 13, color: AppColors.brand, fontWeight: FontWeight.w600))),
                TextButton(
                  onPressed: () {
                    final counter = (_liveBooking['counterPrice'] as num?)?.toInt();
                    final custName = _liveBooking['customerName']?.toString() ?? 'Customer';
                    _showNegotiationDialog(counter, custName, _liveBooking);
                  },
                  child: const Text('Respond', style: TextStyle(fontWeight: FontWeight.w800))),
              ])),
          ],

          // Final offer sent — waiting for customer
          if (_status == 'negotiation_final') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.yellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.yellow.withOpacity(0.4))),
              child: Row(children: [
                const Icon(Icons.price_check_rounded, color: AppColors.yellow, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Final offer sent',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  Text('₹${(_liveBooking['finalPrice'] as num?)?.toInt() ?? 0} — waiting for customer to accept',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ])),
              ])),
          ],

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
                child: const Text('Start Service',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),

          if (_status == 'active')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _initiateOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Text('Complete Job (Get OTP)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),

          // OTP entry
          // Payment pending banner
          if (_status == 'payment_pending') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.yellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.yellow.withOpacity(0.4))),
              child: const Column(children: [
                Row(children: [
                  Icon(Icons.hourglass_top_rounded, color: AppColors.yellow, size: 22),
                  SizedBox(width: 10),
                  Expanded(child: Text('Awaiting Customer Payment',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink))),
                ]),
                SizedBox(height: 8),
                Text('OTP verified! Waiting for customer to complete payment via the app. You will be notified when payment is done.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
              ]),
            ),
          ],

          if (_status == 'otp_sent' || _showOtpEntry) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.green.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
              ),
              child: Column(children: [
                const Icon(Icons.lock_rounded, color: AppColors.green, size: 36),
                const SizedBox(height: 12),
                const Text('Enter OTP from Customer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 6),
                Text('Ask ${bk['customer'] ?? 'customer'} to read you the 4-digit code from their app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) => Container(
                    width: 60, height: 64,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    child: TextField(
                      controller: _otpCtrls[i],
                      focusNode: _otpFocus[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.line, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.green, width: 2),
                        ),
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 3) _otpFocus[i + 1].requestFocus();
                        if (v.isEmpty && i > 0) _otpFocus[i - 1].requestFocus();
                        final all = _otpCtrls.map((c) => c.text).join('');
                        if (all.length == 4) _verifyOTP();
                      },
                    ),
                  )),
                ),
                if (_otpError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF5F5),
                      borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.red)),
                    child: Text(_otpError,
                      style: const TextStyle(fontSize: 12, color: AppColors.red, fontWeight: FontWeight.w600)),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : const Text('Verify OTP & Complete',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
                // Resend OTP button — in case customer didn't receive
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _loading ? null : () async {
                      // Clear existing OTP fields
                      for (final c in _otpCtrls) c.clear();
                      setState(() { _otpError = ''; });
                      // Regenerate OTP
                      await _initiateOTP();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('New OTP sent to customer ✅'),
                            backgroundColor: AppColors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.teal, size: 18),
                    label: const Text('Resend OTP to Customer',
                      style: TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
          Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ])),
      ]),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'accepted': return 'Accepted — Ready to Start';
      case 'active': return 'In Progress';
      case 'otp_sent': return 'Waiting for OTP Verification';
      case 'payment_pending': return '⏳ Awaiting Customer Payment';
      case 'completed': return '✅ Completed — Payment Received';
      default: return s;
    }
  }
}
