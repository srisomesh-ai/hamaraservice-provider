import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/provider_api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import '../utils/parse.dart';

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

  // Live GPS tracking (bookings.php?action=track) while confirmed/active
  static const _trackStatuses = {'confirmed', 'active'};
  Timer? _trackTimer;
  bool _trackSending = false;
  bool _trackDenied = false;

  bool _customerRated = false;
  bool _markingPaid = false;

  @override
  void initState() {
    super.initState();
    _status = (widget.booking['status'] ?? 'accepted').toString();
    _completedNotified = _status == 'completed';
    _customerRated = asInt(widget.booking['customer_rating']) > 0;
    _watchStatus();
    _syncTracking();
  }

  @override
  void dispose() {
    _statusWatcher?.cancel();
    _trackTimer?.cancel();
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
      if (status.isNotEmpty) {
        setState(() {
          _status = status;
          _liveBooking = data;
          if (asInt(data['customer_rating']) > 0) _customerRated = true;
        });
      }
      _syncTracking();

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
      // The server pushes the confirmation to the customer.
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
      // The server pushes the final offer to the customer.
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
      final ok = await ProviderApiService.releaseBooking(widget.bookingKey);
      if (!ok) {
        _showError('Could not decline. Please try again.');
        return;
      }
      // The server returns the booking to 'searching' and notifies the customer.
      _stopTracking();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
  }

  // Statuses in which the provider may still back out (release) of the job
  static const _releasable = {'price_quoted', 'negotiating', 'negotiation_final', 'confirmed', 'accepted'};

  /// Backs out of the job before work starts — the booking goes back to
  /// other providers (bookings.php?action=release).
  Future<void> _confirmRelease() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Release this job?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('The customer will be matched with another provider. '
            'Frequent releases may affect your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Job')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Release', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (yes == true) await _declineNegotiation();
  }

  /// Genuine cancellation with a reason (bookings.php?action=cancel).
  Future<void> _confirmCancel() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel booking', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. Customer asked to cancel',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          TextButton(
            onPressed: () {
              final r = reasonCtrl.text.trim();
              if (r.isEmpty) return;
              Navigator.pop(ctx, r);
            },
            child: const Text('Cancel Booking', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      final ok = await ProviderApiService.cancelBooking(widget.bookingKey, reason: reason);
      if (!ok) {
        _showError('Could not cancel the booking. Please try again.');
        return;
      }
      _stopTracking();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Network error. Please try again.');
    }
  }

  // ── Live location tracking ────────────────────────────────────────────
  void _syncTracking() {
    if (_trackStatuses.contains(_status)) {
      if (_trackTimer == null && !_trackDenied) {
        _sendLocation();
        _trackTimer = Timer.periodic(const Duration(seconds: 15), (_) => _sendLocation());
      }
    } else {
      _stopTracking();
    }
  }

  void _stopTracking() {
    _trackTimer?.cancel();
    _trackTimer = null;
  }

  Future<void> _sendLocation() async {
    if (_trackSending || !mounted || !_trackStatuses.contains(_status)) return;
    _trackSending = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        // Don't keep prompting every 15 s.
        _trackDenied = true;
        _stopTracking();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));
      if (!mounted || !_trackStatuses.contains(_status)) return;
      await ProviderApiService.trackLocation(widget.bookingKey, pos.latitude, pos.longitude);
    } catch (_) {
      // Next tick retries.
    } finally {
      _trackSending = false;
    }
  }

  // ── Cash payment confirmation ─────────────────────────────────────────
  Future<void> _confirmCashReceived(int price) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm cash received', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Confirm that you received ₹$price in cash from the customer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
            child: const Text('Yes, received', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _markingPaid = true);
    bool ok = false;
    try {
      ok = await ProviderApiService.markPaid(widget.bookingKey);
    } catch (_) {
      ProviderApiService.lastError = 'Network error. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _markingPaid = false;
      if (ok) _liveBooking = {..._liveBooking, 'payment_status': 'paid'};
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cash payment confirmed ✅'), backgroundColor: AppColors.green));
    } else {
      _showError('Could not confirm the payment. Please try again.');
    }
  }

  // ── Rate the customer (once, after completion) ─────────────────────────
  Future<void> _showRateCustomerDialog() async {
    int rating = 5;
    final commentCtrl = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Rate ${_customerName(_bk)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                onPressed: () => setD(() => rating = i + 1),
                icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: AppColors.yellow, size: 32),
              )),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Comment (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
              child: const Text('Submit', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
    final comment = commentCtrl.text.trim();
    commentCtrl.dispose();
    if (submit != true || !mounted) return;
    bool ok = false;
    try {
      ok = await ProviderApiService.rateCustomer(widget.bookingKey, rating, comment: comment);
    } catch (_) {
      ProviderApiService.lastError = 'Network error. Please try again.';
    }
    if (!mounted) return;
    if (ok) {
      setState(() => _customerRated = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Thanks for rating the customer!'), backgroundColor: AppColors.green));
    } else {
      final err = ProviderApiService.lastError.toLowerCase();
      if (err.contains('already')) setState(() => _customerRated = true);
      _showError('Could not submit the rating. Please try again.');
    }
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
      final tooMany = ProviderApiService.lastStatus == 429;
      setState(() {
        _loading = false;
        if (tooMany) {
          // Server regenerated the OTP after too many wrong tries.
          _otpError = err.isNotEmpty
              ? err
              : 'Too many wrong OTP attempts. A new OTP has been sent to the customer.';
        } else {
          _otpError = err.toLowerCase().contains('invalid')
              ? 'Incorrect OTP. Ask customer to check their app.'
              : (err.isNotEmpty ? err : 'Could not verify OTP. Please try again.');
        }
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
    _syncTracking();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isCompletion ? 'Job Completed! 🎉' : 'OTP Verified! ✅',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(isCompletion
              ? 'The customer has been asked to pay. If they pay in cash, confirm it on this screen.'
              : 'Service started. When the work is finished, tap "Complete Job".'),
          actions: [
            if (isCompletion && !_customerRated)
              TextButton(
                onPressed: () {
                  Navigator.pop(dCtx);
                  _showRateCustomerDialog();
                },
                child: const Text('Rate Customer', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
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
        leading: const {'completed', 'cancelled', 'searching'}.contains(_status)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context))
            : null,
        actions: [
          if (_releasable.contains(_status) || _status == 'active')
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'release') _confirmRelease();
                if (v == 'cancel') _confirmCancel();
              },
              itemBuilder: (_) => [
                if (_releasable.contains(_status))
                  const PopupMenuItem(value: 'release', child: Text("Release job (can't do it)")),
                if (_status == 'confirmed' || _status == 'accepted' || _status == 'active')
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel booking…')),
              ],
            ),
        ],
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

          // Cash payment: customer says they paid in cash — provider confirms
          if (bk['payment_status'] == 'cash_pending' &&
              (_status == 'active' || _status == 'completed' || _status == 'payment_pending')) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.yellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.yellow.withOpacity(0.4))),
              child: Column(children: [
                const Row(children: [
                  Icon(Icons.payments_rounded, color: AppColors.yellow, size: 22),
                  SizedBox(width: 10),
                  Expanded(child: Text('Customer chose to pay in cash',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink))),
                ]),
                const SizedBox(height: 8),
                Text('Collect ₹$price and confirm once you have received it.',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _markingPaid ? null : () => _confirmCashReceived(price),
                    icon: _markingPaid
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : const Icon(Icons.check_circle_rounded, color: Colors.white),
                    label: const Text('Confirm cash received',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ]),
            ),
          ],

          // Completed — payment status
          if ((_status == 'completed' || _status == 'payment_pending') &&
              bk['payment_status'] != 'cash_pending') ...[
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

          // Completed — rate the customer (once)
          if (_status == 'completed') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _customerRated
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.star_rounded, color: AppColors.yellow, size: 18),
                      SizedBox(width: 6),
                      Text('You rated this customer',
                        style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
                    ])
                  : OutlinedButton.icon(
                      onPressed: _showRateCustomerDialog,
                      icon: const Icon(Icons.star_rounded, color: AppColors.yellow),
                      label: const Text('Rate Customer',
                        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        side: const BorderSide(color: AppColors.yellow),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
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
