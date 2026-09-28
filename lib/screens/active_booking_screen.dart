import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../services/provider_api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import '../utils/parse.dart';
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
  // True once the server has sent the completion OTP to the customer
  bool _completionRequested = false;
  Map<String,dynamic> _liveBooking = {};
  bool _negotiationHandled = false;
  bool _completedNotified = false;
  final List<TextEditingController> _otpCtrls = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(4, (_) => FocusNode());
  String _otpError = '';
  StreamSubscription? _statusWatcher;

  @override
  void initState() {
    super.initState();
    _status = (widget.booking['status'] ?? 'accepted').toString();
    _completedNotified = _status == 'completed';
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
      final prevStatus = _status;
      if (status.isNotEmpty) setState(() { _status = status; _liveBooking = data; });

      // Allow the negotiation dialog again if the customer negotiates later
      if (status != 'negotiating') _negotiationHandled = false;
      // Completion OTP is only relevant while the job is active
      if (status != 'active' && _completionRequested) {
        setState(() => _completionRequested = false);
      }

      // Customer negotiating — show negotiation dialog to provider
      if (status == 'negotiating' && !_negotiationHandled) {
        _negotiationHandled = true;
        final counter = _counterPrice(data);
        final custName = _customerName(data);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showNegotiationDialog(counter, custName, data);
        });
      }

      // Job completed — notify once (not on every poll)
      if (status == 'completed' && !_completedNotified) {
        _completedNotified = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🎉 Job completed!'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 4)));
      }

      if (status == 'cancelled' && prevStatus != 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This booking was cancelled.'),
          backgroundColor: AppColors.red));
      }
    }, onError: (_) {});
  }

  // ── Field helpers (MySQL snake_case with legacy camelCase fallbacks) ─────
  Map<String, dynamic> get _bk => {...widget.booking, ..._liveBooking};

  int? _counterPrice(Map<String, dynamic> b) {
    final v = asInt(b['counter_price'] ?? b['counterPrice']);
    return v > 0 ? v : null;
  }

  String _customerName(Map<String, dynamic> b) {
    final n = (b['customer_name'] ?? b['customerName'] ?? b['customer'] ?? '').toString();
    return n.isNotEmpty ? n : 'Customer';
  }

  int _priceOf(Map<String, dynamic> b) {
    for (final k in ['confirmed_price', 'final_price', 'quoted_price', 'quotedPrice', 'price', 'priceVal']) {
      final v = asInt(b[k]);
      if (v > 0) return v;
    }
    return 0;
  }

  void _showError(String fallback) {
    if (!mounted) return;
    final msg = ProviderApiService.lastError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.isNotEmpty ? msg : fallback),
      backgroundColor: AppColors.red));
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
      final ok = await ProviderApiService.acceptCounter(widget.bookingKey);
      if (!ok) {
        _showError('Could not accept the counter offer. Please try again.');
        return;
      }
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
      final ok = await ProviderApiService.sendFinalOffer(widget.bookingKey, finalPrice);
      if (!ok) {
        _showError('Could not send final offer. Please try again.');
        return;
      }
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
      final ok = await ProviderApiService.cancelBooking(widget.bookingKey);
      if (!ok) {
        _showError('Could not decline. Please try again.');
        return;
      }
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
      final custId = (_liveBooking['customer_id'] ?? _liveBooking['customerId'] ??
          widget.booking['customer_id'] ?? widget.booking['customerId'])?.toString() ?? '';
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

  // ── Completion: server generates the completion OTP and pushes it to the
  // customer. The provider never sees it; the customer reads it out once
  // satisfied and the provider enters it below.
  Future<void> _requestCompletion({bool resend = false}) async {
    setState(() => _loading = true);
    bool ok = false;
    try {
      ok = await ProviderApiService.requestCompletionOtp(widget.bookingKey);
    } catch (e) {
      ProviderApiService.lastError = 'Network error. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (ok) {
        _completionRequested = true;
        _otpError = '';
      }
    });
    if (!ok) {
      final err = ProviderApiService.lastError;
      if (err.startsWith('TOO_EARLY')) {
        final parts = err.split(':');
        final mins = parts.length > 1 ? parts[1] : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Please wait $mins more min before completing.'),
          backgroundColor: AppColors.red));
      } else {
        _showError('Could not request completion OTP. Please try again.');
      }
      return;
    }
    for (final c in _otpCtrls) c.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(resend
          ? 'Completion OTP re-sent to customer ✅'
          : 'Completion OTP sent to customer. Ask them for it.'),
      backgroundColor: AppColors.green,
      duration: const Duration(seconds: 3)));
  }

  /// Start OTP (status 'confirmed') -> bookings.php verify_otp
  /// Completion OTP (status 'active') -> bookings.php complete
  Future<void> _verifyOTP() async {
    if (_loading) return;
    final entered = _otpCtrls.map((c) => c.text).join('');
    if (entered.length < 4) {
      setState(() => _otpError = 'Please enter all 4 digits');
      return;
    }
    final isCompletion = _status == 'active';
    setState(() { _loading = true; _otpError = ''; });

    bool ok = false;
    try {
      if (isCompletion) {
        ok = await ProviderApiService.completeBooking(widget.bookingKey, entered);
      } else {
        ok = (await ProviderApiService.verifyOtp(widget.bookingKey, entered)) != null;
      }
    } catch (e) {
      ProviderApiService.lastError = 'Network error. Please try again.';
    }
    if (!mounted) return;

    if (!ok) {
      final err = ProviderApiService.lastError;
      setState(() {
        _loading = false;
        _otpError = err.toLowerCase().contains('invalid')
            ? 'Incorrect OTP. Ask customer to check their app.'
            : (err.isNotEmpty ? err : 'Could not verify OTP. Please try again.');
      });
      HapticFeedback.heavyImpact();
      for (final c in _otpCtrls) c.clear();
      _otpFocus[0].requestFocus();
      return;
    }

    for (final c in _otpCtrls) c.clear();
    setState(() {
      _loading = false;
      _completionRequested = false;
      _status = isCompletion ? 'completed' : 'active';
      if (isCompletion) _completedNotified = true;
    });

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isCompletion ? 'Job Completed! 🎉' : 'OTP Verified! ✅',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(isCompletion
              ? 'The customer has been asked to pay. Payment status will update on your dashboard.'
              : 'Service started. When the work is finished, tap "Complete Job".'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dCtx);
                // After completion go back to the dashboard
                if (isCompletion && mounted) Navigator.pop(context);
              },
              child: const Text('OK', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
  }

  void _callCustomer() {
    final b = _bk;
    final phone = (b['customer_phone'] ?? b['phone'] ?? '').toString();
    if (phone.isNotEmpty) {
      launchUrl(Uri.parse('tel:$phone'));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Customer phone is shared once the booking is confirmed.'),
        backgroundColor: AppColors.muted));
    }
  }

  void _openMaps() {
    final lat = _bk['lat'];
    final lng = _bk['lng'];

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
    final address = Uri.encodeComponent((_bk['address'] ?? '').toString());
    if (address.isNotEmpty) {
      launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$address&travelmode=driving'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bk = _bk;
    final price = _priceOf(bk);
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
                Text((bk['svc_name'] ?? bk['service'] ?? 'Service').toString(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('Status: ${_statusLabel(_status)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
              Text('₹$price',
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
              _detailRow(Icons.person_rounded, 'Name', _customerName(bk)),
              _detailRow(Icons.phone_rounded, 'Phone',
                (bk['customer_phone'] ?? bk['phone'] ?? '').toString()),
              _detailRow(Icons.calendar_today_rounded, 'Date & Time',
                '${bk['slot_date'] ?? bk['date'] ?? ''} at ${bk['slot_time'] ?? bk['time'] ?? ''}'),
              _detailRow(Icons.location_on_rounded, 'Address', (bk['address'] ?? '').toString()),
              _detailRow(Icons.currency_rupee_rounded, 'Amount', '₹$price'),
            ]),
          ),

          // Summary chips
          if (bk['summary'] is List && (bk['summary'] as List).isNotEmpty) ...[
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
                    final counter = _counterPrice(_liveBooking);
                    final custName = _customerName(_liveBooking);
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
                  Text('₹${asInt(_liveBooking['final_price'] ?? _liveBooking['finalPrice'])} — waiting for customer to accept',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ])),
              ])),
          ],

          // Confirmed — provider travels to customer, then enters the Start OTP
          // the customer generates in their app (bookings.php verify_otp).
          if (_status == 'confirmed' || _status == 'accepted') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.green.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('Job confirmed! Head to the customer. When you arrive, ask them to generate the Start OTP in their app.',
                  style: TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600))),
              ])),
          ],

          // Active — request completion OTP (server sends it to the customer)
          if (_status == 'active' && !_completionRequested)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _requestCompletion(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Text('Complete Job',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),

          // Completed — payment status
          if (_status == 'completed' || _status == 'payment_pending') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (bk['payment_status'] == 'paid') ? AppColors.greenSoft : AppColors.yellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (bk['payment_status'] == 'paid')
                    ? AppColors.green.withOpacity(0.4)
                    : AppColors.yellow.withOpacity(0.4))),
              child: Column(children: [
                Row(children: [
                  Icon(bk['payment_status'] == 'paid' ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                    color: bk['payment_status'] == 'paid' ? AppColors.green : AppColors.yellow, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(bk['payment_status'] == 'paid' ? 'Payment Received' : 'Awaiting Customer Payment',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink))),
                ]),
                const SizedBox(height: 8),
                Text(bk['payment_status'] == 'paid'
                    ? 'The customer has paid ₹$price.'
                    : 'Job completed. Waiting for the customer to pay ₹$price. You will be notified when payment is done.',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
              ]),
            ),
          ],

          // OTP entry: Start OTP while confirmed, Completion OTP once requested
          if (_status == 'confirmed' || _status == 'accepted' ||
              (_status == 'active' && _completionRequested)) ...[
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
                Text(_status == 'active' ? 'Enter Completion OTP' : 'Enter Start OTP',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 6),
                Text(_status == 'active'
                    ? 'Ask ${_customerName(bk)} to read you the 4-digit completion code from their app once they are satisfied.'
                    : 'Ask ${_customerName(bk)} to generate the Start OTP in their app and read you the 4-digit code.',
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
                        : Text(_status == 'active' ? 'Verify OTP & Complete Job' : 'Verify OTP & Start Job',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
                // Resend completion OTP — server re-sends the same OTP to the customer
                if (_status == 'active') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _loading ? null : () {
                        setState(() { _otpError = ''; });
                        _requestCompletion(resend: true);
                      },
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.teal, size: 18),
                      label: const Text('Resend OTP to Customer',
                        style: TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
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
      case 'price_quoted': return 'Quote Sent — Waiting for Customer';
      case 'negotiating': return 'Customer Negotiating';
      case 'negotiation_final': return 'Final Offer Sent';
      case 'confirmed': return 'Confirmed — Head to Customer';
      case 'cancelled': return 'Cancelled';
      case 'searching': return 'Released';
      case 'accepted': return 'Accepted — Ready to Start';
      case 'active': return 'In Progress';
      case 'otp_sent': return 'Waiting for OTP Verification';
      case 'payment_pending': return '⏳ Awaiting Customer Payment';
      case 'completed': return '✅ Completed';
      default: return s;
    }
  }
}
