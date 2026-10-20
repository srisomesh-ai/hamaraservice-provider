import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/location_service.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';
import 'earnings_screen.dart';

/// One booking, driven entirely by polling bookings.php?action=get&id=
/// (every 4 s while visible) and the backend status machine:
/// price_quoted → negotiating → negotiation_final → confirmed → active →
/// completed (payment pending → paid) | cancelled | released/taken.
class ActiveBookingScreen extends StatefulWidget {
  final String bookingId;
  /// Optional row we already have (shown until the first poll returns).
  final Map<String, dynamic>? initial;
  const ActiveBookingScreen({super.key, required this.bookingId, this.initial});

  @override
  State<ActiveBookingScreen> createState() => _ActiveBookingScreenState();
}

class _ActiveBookingScreenState extends State<ActiveBookingScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> _bk = {};
  bool _loaded = false;
  bool _busy = false;          // an action is in flight → disable buttons
  bool _polling = false;
  String _pollError = '';
  String _gone = '';           // non-empty → booking is no longer ours
  String _myId = '';
  String _hint = '';           // inline info under action buttons
  bool _reviewRequested = false;

  Timer? _pollTimer;
  Timer? _clock;
  // OTP inputs live in State for the whole screen: polling never recreates or
  // clears them, so whatever the provider is typing survives every refresh.
  final _startOtpCtrl = TextEditingController();
  final _doneOtpCtrl = TextEditingController();
  String _otpError = '';
  String _renderKey = '';      // visible booking fields; rebuild only when it changes
  DateTime? _quoteDeadline;    // customer must confirm the quote before this

  String get _id => widget.bookingId;
  String get _status => str(_bk['status']);
  bool get _paid => str(_bk['payment_status']) == 'paid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initial != null) _bk = Map<String, dynamic>.from(widget.initial!);
    SharedPreferences.getInstance().then((p) {
      _myId = p.getString('provider_id') ?? '';
      _poll();
    });
    _startPolling();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_status == 'active' || _quoteDeadline != null)) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _clock?.cancel();
    _startOtpCtrl.dispose();
    _doneOtpCtrl.dispose();
    LocationService.instance.onJob = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _poll();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_polling || _gone.isNotEmpty) return;
    _polling = true;
    try {
      final res = await ProviderApiService.getBooking(_id);
      if (!mounted) return;
      if (res.unauthorized) return;
      if (!res.ok) {
        if (res.status == 404) {
          _setGone('This booking no longer exists.');
        } else {
          setState(() => _pollError = res.error);
        }
        return;
      }
      final data = res.map ?? {};
      final status = str(data['status']);
      final pid = str(data['provider_id']);
      // Unassigned providers only get {id, status:'searching'|'taken'}
      if (status == 'taken' || status == 'searching' ||
          (pid.isNotEmpty && _myId.isNotEmpty && pid != _myId)) {
        _setGone(status == 'searching'
            ? 'This job is no longer assigned to you (the quote time ran out, it was released, or the customer chose another provider).'
            : 'Another provider took this job.');
        return;
      }
      // Quote window: recomputed from the server on every poll.
      final quoteLive = (status == 'price_quoted' || status == 'negotiation_final') &&
          data['quote_expires_in'] != null;
      _quoteDeadline = quoteLive
          ? DateTime.now().add(Duration(seconds: toInt(data['quote_expires_in'])))
          : null;
      final key = _keyOf(data);
      final changed = key != _renderKey || !_loaded || _pollError.isNotEmpty;
      final prevStatus = _status;
      _bk = data;
      if (toInt(data['review_requested']) == 1) _reviewRequested = true;
      if (changed) {
        setState(() {
          _renderKey = key;
          _loaded = true;
          _pollError = '';
          // A real status change ends the previous step's OTP error.
          if (prevStatus != status) _otpError = '';
        });
      }
      LocationService.instance.onJob = status == 'confirmed' || status == 'active';
      if (status == 'cancelled') _pollTimer?.cancel();
      if (status == 'completed' && _paid) {
        // Nothing more will change server-side except a review; slow down.
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } finally {
      _polling = false;
    }
  }

  /// Fields that change what this screen shows. Polls that return the same
  /// values do not rebuild anything.
  String _keyOf(Map<String, dynamic> b) => [
        b['id'], b['status'], b['payment_status'], b['payment_method'],
        b['completion_otp_requested'], b['quoted_price'], b['counter_price'],
        b['final_price'], b['confirmed_price'], b['amount'], b['started_at'],
        b['completed_at'], b['rating'], b['review'], b['review_requested'],
        b['cash_allowed'], b['commission_amt'], b['provider_earns'],
        b['contact_phone'], b['customer_phone'], b['address'], b['slot_date'],
        b['slot_time'], b['cancel_reason'],
      ].join('|');

  /// The booking is no longer ours (taken / released / quote expired):
  /// leave the job screen with a message.
  void _setGone(String msg) {
    _pollTimer?.cancel();
    _quoteDeadline = null;
    LocationService.instance.onJob = false;
    if (!mounted) return;
    setState(() { _gone = msg; _loaded = true; });
    _snack(msg, AppColors.muted);
    _exit();
  }

  // ── Actions ────────────────────────────────────────────────

  /// Runs an API action once (no double submit), shows server errors,
  /// refreshes the booking on success.
  Future<ApiResult?> _run(Future<ApiResult> Function() call,
      {String? success, bool refresh = true}) async {
    if (_busy) return null;
    setState(() { _busy = true; _hint = ''; });
    HapticFeedback.lightImpact();
    final res = await call();
    if (!mounted) return res;
    setState(() => _busy = false);
    if (res.unauthorized) return res;
    if (!res.ok) {
      // 402 CASH_NOT_ALLOWED: … → show the text after the prefix
      _snack(res.error.replaceFirst(RegExp(r'^CASH_NOT_ALLOWED:\s*'), ''), AppColors.red);
      if (res.status == 402) await _poll(); // refresh cash_allowed
    } else {
      if (success != null) _snack(success, AppColors.green);
      if (refresh) await _poll();
    }
    return res;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating));
  }

  Future<bool> _confirm(String title, String body, String yes,
      {Color color = AppColors.teal}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No', style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: color, minimumSize: const Size(100, 44)),
              child: Text(yes, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _release({String label = 'Withdraw'}) async {
    final ok = await _confirm('$label from this job?',
        'The job goes back to other providers. This cannot be undone.', label,
        color: AppColors.red);
    if (!ok) return;
    final res = await _run(() => ProviderApiService.releaseBooking(_id), refresh: false);
    if (res != null && res.ok && mounted) {
      _gone = 'released';
      _pollTimer?.cancel();
      _snack('You released this job.', AppColors.muted);
      _exit();
    }
  }

  Future<void> _sendFinalOffer() async {
    final quote = toInt(_bk['quoted_price']);
    final counter = toInt(_bk['counter_price']);
    final ctrl = TextEditingController(text: quote > 0 ? '$quote' : '');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String err = '';
        return StatefulBuilder(builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Send final offer', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Customer offered ₹$counter. Your quote was ₹$quote.\n'
                'Your final offer must be ₹$quote or less.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Final price',
                errorText: err.isEmpty ? null : err,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.muted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () {
                final n = int.tryParse(ctrl.text.trim()) ?? 0;
                if (n <= 0) { setD(() => err = 'Enter a price'); return; }
                if (quote > 0 && n > quote) { setD(() => err = 'Must be ≤ ₹$quote'); return; }
                Navigator.pop(ctx, n);
              },
              child: const Text('Send'),
            ),
          ],
        ));
      },
    );
    ctrl.dispose();
    if (v == null) return;
    await _run(() => ProviderApiService.sendFinalOffer(_id, v),
        success: 'Final offer of ₹$v sent');
  }

  Future<void> _verifyStartOtp() async {
    final otp = _startOtpCtrl.text.trim();
    if (otp.length < 4) { setState(() => _otpError = 'Enter the 4-digit OTP'); return; }
    setState(() => _otpError = '');
    final res = await _run(() => ProviderApiService.verifyStartOtp(_id, otp),
        success: 'OTP verified — job started');
    if (res != null && !res.ok && mounted) {
      setState(() => _otpError = res.error);
    }
    if (res != null && res.ok) _startOtpCtrl.clear();
  }

  Future<void> _requestCompletionOtp() async {
    final res = await _run(() => ProviderApiService.requestCompletionOtp(_id));
    if (res == null || !mounted) return;
    if (res.ok) {
      _snack('Completion OTP sent to the customer. Ask them for it.', AppColors.green);
    } else if (res.error.startsWith('TOO_EARLY')) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final mins = int.tryParse(res.error.split(':').last.trim()) ?? 0;
      setState(() => _hint = 'You can finish in $mins min');
    }
  }

  Future<void> _complete() async {
    final otp = _doneOtpCtrl.text.trim();
    if (otp.length < 4) { setState(() => _otpError = 'Enter the 4-digit completion OTP'); return; }
    setState(() => _otpError = '');
    final res = await _run(() => ProviderApiService.completeBooking(_id, otp),
        success: 'Job completed');
    if (res == null || !mounted) return;
    if (!res.ok) {
      final e = res.error;
      setState(() => _otpError = e == 'COMPLETION_OTP_NOT_REQUESTED'
          ? 'Request the completion OTP first'
          : e == 'COMPLETION_OTP_REQUIRED'
              ? 'Enter the completion OTP'
              : e);
    } else {
      _doneOtpCtrl.clear();
    }
  }

  Future<void> _cashCollected() async {
    final amt = toInt(_bk['amount']);
    final ok = await _confirm('Confirm cash received',
        'Confirm you received ₹$amt in cash from the customer. '
        'The platform fee (₹${toInt(_bk['commission_amt'])}) will be deducted from your wallet balance.',
        'Yes, received', color: AppColors.green);
    if (!ok) return;
    await _run(() => ProviderApiService.cashCollected(_id),
        success: 'Cash payment recorded');
  }

  Future<void> _requestReview() async {
    final res = await _run(() => ProviderApiService.requestReview(_id),
        success: 'Review request sent to the customer');
    if (res != null && res.ok && mounted) setState(() => _reviewRequested = true);
  }

  Future<void> _call() async {
    final phone = str(_bk['contact_phone'], str(_bk['customer_phone']));
    if (phone.isEmpty) { _snack('Customer phone not available', AppColors.red); return; }
    if (!await launchUrl(Uri.parse('tel:$phone'))) {
      _snack('Could not open the dialer', AppColors.red);
    }
  }

  Future<void> _navigate() async {
    final lat = toDoubleOrNull(_bk['lat']);
    final lng = toDoubleOrNull(_bk['lng']);
    final Uri uri;
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    } else {
      final q = Uri.encodeComponent([str(_bk['address']), str(_bk['city'])]
          .where((s) => s.isNotEmpty).join(', '));
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open Maps', AppColors.red);
    }
  }

  Future<void> _addMoney() async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => EarningsScreen(providerId: _myId, openTopUp: true)));
    if (mounted) _poll();
  }

  void _exit() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((r) => r.isFirst);
    } else {
      nav.pushReplacement(MaterialPageRoute(
          builder: (_) => DashboardScreen(providerId: _myId)));
    }
  }

  // ── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(str(_bk['svc_name'], 'Booking')),
        backgroundColor: AppColors.teal,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _busy ? null : _poll),
        ],
      ),
      body: !_loaded && _bk.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : _gone.isNotEmpty
              ? _endState(Icons.info_outline_rounded, AppColors.muted, 'Booking closed', _gone)
              : RefreshIndicator(
                  onRefresh: _poll,
                  color: AppColors.teal,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_pollError.isNotEmpty) _banner(_pollError, AppColors.red),
                      _statusHeader(),
                      const SizedBox(height: 12),
                      _detailsCard(),
                      const SizedBox(height: 12),
                      _stateBody(),
                      if (_hint.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _banner(_hint, AppColors.yellow),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _stateBody() {
    switch (_status) {
      case 'price_quoted':
        return _section([
          _waiting('Waiting for customer to accept ₹${toInt(_bk['quoted_price'])}'),
          _quoteLeft(),
          const SizedBox(height: 12),
          _outlined('Withdraw', Icons.undo_rounded, AppColors.red, () => _release()),
        ]);

      case 'negotiating':
        final counter = toInt(_bk['counter_price']);
        return _section([
          Text('Customer offered ₹$counter',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.brand)),
          Text('Your quote: ₹${toInt(_bk['quoted_price'])}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 14),
          _primary('Accept ₹$counter', Icons.check_rounded, AppColors.green,
              () => _run(() => ProviderApiService.acceptCounter(_id),
                  success: 'Price agreed — booking confirmed')),
          const SizedBox(height: 10),
          _outlined('Send final offer', Icons.price_change_rounded, AppColors.teal, _sendFinalOffer),
          const SizedBox(height: 10),
          _outlined('Decline', Icons.close_rounded, AppColors.red, () => _release(label: 'Decline')),
        ]);

      case 'negotiation_final':
        return _section([
          _waiting('Final offer ₹${toInt(_bk['final_price'])} sent. Waiting for the customer to confirm.'),
          _quoteLeft(),
          const SizedBox(height: 12),
          _outlined('Withdraw', Icons.undo_rounded, AppColors.red, () => _release()),
        ]);

      case 'confirmed':
        return _section([
          _customerBlock(),
          const SizedBox(height: 16),
          const Text('Enter START OTP from customer',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const Text('Ask the customer for the 4-digit code shown in their app.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 10),
          _otpField(_startOtpCtrl),
          const SizedBox(height: 10),
          _primary('Verify & start job', Icons.play_arrow_rounded, AppColors.teal, _verifyStartOtp),
          const SizedBox(height: 10),
          _outlined('Release job', Icons.undo_rounded, AppColors.red, () => _release(label: 'Release')),
        ]);

      case 'active':
        final requested = toInt(_bk['completion_otp_requested']) == 1;
        return _section([
          _jobTimer(),
          if (str(_bk['started_at']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('▶️ Work started at ${istTime(_bk['started_at'])}',
                style: const TextStyle(fontSize: 13, color: AppColors.ink2)),
          ],
          const SizedBox(height: 12),
          _customerBlock(compact: true),
          const SizedBox(height: 16),
          if (!requested)
            _primary('Job done — request completion OTP', Icons.task_alt_rounded,
                AppColors.green, _requestCompletionOtp)
          else ...[
            const Text('Enter completion OTP from customer',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const Text('The code was sent to the customer\'s app.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 10),
            _otpField(_doneOtpCtrl),
            const SizedBox(height: 10),
            _primary('Complete job', Icons.check_circle_rounded, AppColors.green, _complete),
            TextButton(
              onPressed: _busy ? null : _requestCompletionOtp,
              child: const Text('Re-send OTP to customer',
                  style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
            ),
          ],
        ]);

      case 'completed':
        return _paid ? _paidBody() : _paymentPendingBody();

      case 'cancelled':
        final reason = str(_bk['cancel_reason']);
        return _endCard(Icons.cancel_rounded, AppColors.red, 'Booking cancelled',
            reason.isNotEmpty ? 'Reason: $reason' : 'The customer cancelled this booking.');

      default:
        return _section([_waiting('Status: $_status')]);
    }
  }

  Widget _paymentPendingBody() {
    final amt = toInt(_bk['amount']);
    return _section([
      const Text('Collect payment',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 8),
      Text('₹$amt', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.green)),
      const SizedBox(height: 8),
      _moneyRows(),
      _workTimes(),
      const SizedBox(height: 14),
      if (toInt(_bk['cash_allowed'], 1) == 1) ...[
        _primary('Customer paid cash — confirm ₹$amt received', Icons.payments_rounded,
            AppColors.green, _cashCollected),
        const SizedBox(height: 10),
        _waiting('Or wait — if the customer pays online in the app, this screen updates automatically.'),
      ] else ...[
        _banner('💳 Online payment only — your wallet balance is less than the platform fee '
            '₹${toInt(_bk['commission_amt'])} for this job, so cash can\'t be accepted. '
            'Ask the customer to pay online in their app, or add money to your wallet.',
            AppColors.red),
        _primary('Add money to wallet', Icons.account_balance_wallet_rounded,
            AppColors.teal, _addMoney),
        const SizedBox(height: 10),
        _waiting('Waiting for the customer to pay online — this screen updates automatically.'),
      ],
    ]);
  }

  Widget _paidBody() {
    final cash = str(_bk['payment_method']) == 'cash';
    final hasRating = toInt(_bk['rating']) > 0;
    return _section([
      const Row(children: [
        Icon(Icons.verified_rounded, color: AppColors.green),
        SizedBox(width: 8),
        Text('Paid — job finished',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green)),
      ]),
      const SizedBox(height: 10),
      Text('You earned ₹${toInt(_bk['provider_earns'])}',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.ink)),
      Text(cash ? 'Paid in cash — platform fee deducted from your wallet' : 'Paid online — added to your wallet',
          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 10),
      _moneyRows(),
      _workTimes(),
      const SizedBox(height: 14),
      if (hasRating)
        _banner('Customer rated you ${toInt(_bk['rating'])}★'
            '${str(_bk['review']).isNotEmpty ? ' — "${str(_bk['review'])}"' : ''}', AppColors.green)
      else
        _outlined(_reviewRequested ? 'Review requested' : 'Request review',
            Icons.star_rounded, AppColors.yellow,
            _reviewRequested ? null : _requestReview),
      const SizedBox(height: 10),
      _primary('Back to dashboard', Icons.home_rounded, AppColors.teal, _exit),
    ]);
  }

  Widget _moneyRows() => Column(children: [
        _kv('Job amount', '₹${toInt(_bk['amount'])}'),
        _kv('Platform commission (${toInt(_bk['commission_pct'])}%)', '− ₹${toInt(_bk['commission_amt'])}'),
        _kv('You earn', '₹${toInt(_bk['provider_earns'])}', bold: true),
      ]);

  /// "Customer has m:ss left to confirm" / "⌛ Time up — job will be released"
  Widget _quoteLeft() {
    final dl = _quoteDeadline;
    if (dl == null) return const SizedBox.shrink();
    var left = (dl.difference(DateTime.now()).inMilliseconds / 1000).round();
    if (left < 0) left = 0;
    final t = left > 0
        ? 'Customer has ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left to confirm'
        : '⌛ Time up — job will be released';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(t,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
    );
  }

  /// Started / closed / duration for a completed job.
  Widget _workTimes() {
    final st = str(_bk['started_at']), done = str(_bk['completed_at']);
    if (st.isEmpty && done.isEmpty) return const SizedBox.shrink();
    final dur = istDuration(st, done);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFF5F8F9), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (st.isNotEmpty)
          Text('▶️ Started: ${istTime(st)}', style: const TextStyle(fontSize: 12.5, color: AppColors.ink2)),
        if (done.isNotEmpty)
          Text('⏹️ Closed: ${istTime(done)}${dur.isNotEmpty ? ' · ⏱️ $dur' : ''}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink2)),
      ]),
    );
  }

  Widget _jobTimer() {
    final started = parseIst(_bk['started_at']);
    var d = started == null ? Duration.zero : DateTime.now().difference(started);
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.timer_rounded, color: AppColors.teal, size: 28),
        const SizedBox(width: 12),
        const Expanded(
            child: Text('Job in progress',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.teal))),
        Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.teal)),
      ]),
    );
  }

  Widget _customerBlock({bool compact = false}) {
    final name = str(_bk['contact_name'], str(_bk['customer_name'], 'Customer'));
    final phone = str(_bk['contact_phone'], str(_bk['customer_phone']));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(
          backgroundColor: AppColors.tealSoft,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
              style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
            if (phone.isNotEmpty)
              Text(phone, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _outlined('Call', Icons.call_rounded, AppColors.green, phone.isEmpty ? null : _call)),
        const SizedBox(width: 10),
        Expanded(child: _outlined('Navigate', Icons.directions_rounded, AppColors.teal, _navigate)),
      ]),
    ]);
  }

  Widget _statusHeader() {
    final lc = _statusLabelColor();
    final String label = lc.key;
    final Color color = lc.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))),
        Text(_id, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    );
  }

  MapEntry<String, Color> _statusLabelColor() {
    MapEntry<String, Color> e(String l, Color c) => MapEntry(l, c);
    switch (_status) {
      case 'price_quoted': return e('Quote sent', AppColors.yellow);
      case 'negotiating': return e('Customer is negotiating', AppColors.brand);
      case 'negotiation_final': return e('Final offer sent', AppColors.yellow);
      case 'confirmed': return e('Confirmed — go to customer', AppColors.teal);
      case 'active': return e('In progress', AppColors.teal);
      case 'completed':
        return _paid ? e('Completed & paid', AppColors.green) : e('Awaiting payment', AppColors.yellow);
      case 'cancelled': return e('Cancelled', AppColors.red);
      default: return e(_status, AppColors.muted);
    }
  }

  Widget _detailsCard() {
    final summary = parseSummary(_bk['summary']);
    final price = toInt(_bk['confirmed_price']) > 0
        ? toInt(_bk['confirmed_price'])
        : toInt(_bk['final_price']) > 0
            ? toInt(_bk['final_price'])
            : toInt(_bk['quoted_price']);
    final area = [str(_bk['landmark']), str(_bk['address']), str(_bk['city'])]
        .where((s) => s.isNotEmpty).join(', ');
    final dist = toDoubleOrNull(_bk['distance_km']);
    final notes = str(_bk['notes']);
    return _section([
      _row(Icons.home_repair_service_rounded, str(_bk['svc_name'], 'Service')),
      if (price > 0) _row(Icons.currency_rupee_rounded, '₹$price'),
      _row(Icons.calendar_today_rounded, slotWhen(_bk['slot_date'], _bk['slot_time'])),
      if (area.isNotEmpty) _row(Icons.location_on_rounded, area),
      if (dist != null) _row(Icons.near_me_rounded, '${dist.toStringAsFixed(1)} km away'),
      if (notes.isNotEmpty) _row(Icons.sticky_note_2_rounded, notes),
      if (summary.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: summary.map(_chip).toList()),
      ],
    ]);
  }

  // ── small widgets ──

  Widget _section(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
        ]),
      );

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
          Text(v, style: TextStyle(fontSize: 14, color: AppColors.ink,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
        ]),
      );

  Widget _chip(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.teal.withOpacity(0.3)),
        ),
        child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
      );

  Widget _waiting(String text) => Row(children: [
        const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink2))),
      ]);

  Widget _banner(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _otpField(TextEditingController ctrl) => TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 10),
        decoration: InputDecoration(
          counterText: '',
          hintText: '• • • •',
          errorText: _otpError.isEmpty ? null : _otpError,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _primary(String label, IconData icon, Color color, VoidCallback? onTap) =>
      ElevatedButton.icon(
        onPressed: _busy || onTap == null ? null : onTap,
        icon: _busy
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, color: Colors.white, size: 20),
        label: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _outlined(String label, IconData icon, Color color, VoidCallback? onTap) =>
      OutlinedButton.icon(
        onPressed: _busy || onTap == null ? null : onTap,
        icon: Icon(icon, color: color, size: 18),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _endCard(IconData icon, Color color, String title, String body) => _section([
        Icon(icon, color: color, size: 48),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 16),
        _primary('Back to dashboard', Icons.home_rounded, AppColors.teal, _exit),
      ]);

  Widget _endState(IconData icon, Color color, String title, String body) => ListView(
        padding: const EdgeInsets.all(24),
        children: [const SizedBox(height: 40), _endCard(icon, color, title, body)],
      );
}
