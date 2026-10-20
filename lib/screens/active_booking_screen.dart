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
import '../widgets/active_job_card.dart';
import '../widgets/new_job_card.dart';
import '../widgets/ui.dart';

/// One booking, driven entirely by polling bookings.php?action=get&id=
/// (every 4 s while visible) and the backend status machine:
/// price_quoted → negotiating → negotiation_final → confirmed → active →
/// completed (payment pending → paid) | cancelled | released/taken.
class ActiveBookingScreen extends StatefulWidget {
  final String bookingId;
  /// Optional row we already have (shown until the first poll returns).
  final Map<String, dynamic>? initial;
  /// Test-only: show [initial] without polling the server (screenshots).
  final bool demo;
  const ActiveBookingScreen({super.key, required this.bookingId, this.initial, this.demo = false});

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
    if (widget.demo) {
      _loaded = true;
      if (str(_bk['status']) == 'price_quoted' || str(_bk['status']) == 'negotiation_final') {
        _quoteDeadline = DateTime.now().add(Duration(seconds: toInt(_bk['quote_expires_in'])));
      }
      return;
    }
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
    if (!widget.demo) LocationService.instance.onJob = false;
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
    if (_polling || _gone.isNotEmpty || widget.demo) return;
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
      final e = res.error == 'PAYMENT_PENDING'
          ? 'Wait for the customer to pay before requesting a review'
          : res.error.replaceFirst(RegExp(r'^CASH_NOT_ALLOWED:\s*'), '');
      if (!e.startsWith('TOO_EARLY')) _snack(e, AppColors.red);
      if (res.status == 402) await _poll(); // refresh cash_allowed
    } else {
      if (success != null) _snack(success, AppColors.green);
      if (refresh) await _poll();
    }
    return res;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    showSnack(context, msg,
        tone: color == AppColors.red
            ? Tone.error
            : color == AppColors.green
                ? Tone.success
                : color == AppColors.yellow
                    ? Tone.warning
                    : Tone.neutral);
  }

  Future<bool> _confirm(String title, String body, String yes,
      {Color color = AppColors.teal}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(96, 44)),
              child: Text(yes)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _release() async {
    final ok = await _confirm('Give up this job?',
        'It will go back to other providers.', 'Give up',
        color: AppColors.red);
    if (!ok) return;
    final res = await _run(() => ProviderApiService.releaseBooking(_id), refresh: false);
    if (res != null && res.ok && mounted) {
      _gone = 'released';
      _pollTimer?.cancel();
      _snack('Job released', AppColors.muted);
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
          title: const Text('Send final price'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Customer offered ₹$counter. Your quote was ₹$quote.\n'
                'Your final price must not be above your quote.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Your final price (₹)',
                errorText: err.isEmpty ? null : err,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () {
                final n = int.tryParse(ctrl.text.trim()) ?? 0;
                if (n <= 0) { setD(() => err = 'Invalid price'); return; }
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
        success: 'Final offer sent');
  }

  Future<void> _verifyStartOtp() async {
    final otp = _startOtpCtrl.text.trim();
    if (otp.length < 4) { setState(() => _otpError = 'Enter the OTP from the customer'); return; }
    setState(() => _otpError = '');
    final res = await _run(() => ProviderApiService.verifyStartOtp(_id, otp),
        success: '✅ OTP verified — job started');
    if (res != null && !res.ok && mounted) {
      setState(() => _otpError = res.error.isNotEmpty ? res.error : 'Wrong OTP');
    }
    if (res != null && res.ok) _startOtpCtrl.clear();
  }

  Future<void> _requestCompletionOtp() async {
    final res = await _run(() => ProviderApiService.requestCompletionOtp(_id));
    if (res == null || !mounted) return;
    if (res.ok) {
      _snack('🔑 Ask customer for the completion OTP now', AppColors.green);
    } else if (res.error.startsWith('TOO_EARLY')) {
      final mins = int.tryParse(res.error.split(':').last.trim()) ?? 0;
      final msg = 'Too early to complete — please wait ${mins > 0 ? mins : 'a few'} more min';
      _snack(msg, AppColors.yellow);
      setState(() => _hint = msg);
    }
  }

  Future<void> _complete() async {
    final otp = _doneOtpCtrl.text.trim();
    if (otp.length < 4) { setState(() => _otpError = 'Ask customer for the 4-digit completion OTP'); return; }
    setState(() => _otpError = '');
    final res = await _run(() => ProviderApiService.completeBooking(_id, otp),
        success: '🎉 Job completed!');
    if (res == null || !mounted) return;
    if (!res.ok) {
      final e = res.error;
      setState(() => _otpError = e == 'COMPLETION_OTP_NOT_REQUESTED'
          ? 'Request the completion OTP first'
          : e == 'COMPLETION_OTP_REQUIRED'
              ? 'Completion OTP required'
              : (e.isNotEmpty ? e : 'Wrong OTP'));
    } else {
      _doneOtpCtrl.clear();
      _showCompletedSheet();
    }
  }

  Future<void> _cashCollected() async {
    final ok = await _confirm('I collected cash',
        'Confirm you received the full amount in cash from the customer? '
        'The platform fee will be deducted from your wallet balance.',
        'Confirm', color: AppColors.green);
    if (!ok) return;
    await _run(() => ProviderApiService.cashCollected(_id),
        success: '💵 Cash payment recorded');
  }

  Future<void> _requestReview() async {
    final res = await _run(() => ProviderApiService.requestReview(_id),
        success: '⭐ Review request sent to customer');
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
    if (widget.demo) return;
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => EarningsScreen(providerId: _myId, openTopUp: true)));
    if (mounted) _poll();
  }

  /// Website showCompletedSheet().
  void _showCompletedSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎉', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 6),
          Text('Job Completed!', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('The customer can now pay online. If they pay you in cash, tap “I collected cash”.',
              textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text('Once the customer pays, you can ask for a review.',
              textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 18),
          BigButton('Done', outlined: true, onPressed: () => Navigator.pop(ctx)),
        ]),
      ),
    );
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
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(str(_bk['svc_name'], 'Job')),
          Text(_id, style: const TextStyle(fontSize: 12.5, color: Colors.white70, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _busy ? null : _poll),
        ],
      ),
      body: !_loaded && _bk.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _gone.isNotEmpty
              ? _endState(Icons.info_outline_rounded, AppColors.muted, 'Booking closed', _gone)
              : RefreshIndicator(
                  onRefresh: _poll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      if (_pollError.isNotEmpty)
                        Notice(_pollError, tone: Tone.error, margin: const EdgeInsets.only(bottom: 12)),
                      _headerCard(),
                      const SizedBox(height: 12),
                      _detailsCard(),
                      const SizedBox(height: 12),
                      _stateBody(),
                      if (_hint.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Notice(_hint, tone: Tone.warning),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _headerCard() {
    final t = Theme.of(context).textTheme;
    final amount = bookingAmount(_bk);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14)),
              child: Text(jobIcon(_bk), style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('₹$amount', style: t.headlineSmall?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w800)),
                Text(_priceCaption(), style: t.bodySmall),
              ]),
            ),
            StatusBadge(_status, paymentStatus: str(_bk['payment_status'])),
          ]),
          if (_status != 'cancelled') ...[
            const SizedBox(height: 18),
            JobStepper(status: _status, paid: _paid),
          ],
        ]),
      ),
    );
  }

  String _priceCaption() {
    switch (_status) {
      case 'price_quoted': return 'Your quote';
      case 'negotiating': return 'Your quote · customer is negotiating';
      case 'negotiation_final': return 'Your final price';
      case 'completed': return _paid ? 'Paid' : 'To collect';
      default: return 'Agreed price';
    }
  }

  Widget _detailsCard() {
    final summary = parseSummary(_bk['summary']);
    final name = str(_bk['contact_name'], str(_bk['customer_name'], 'Customer'));
    final phone = str(_bk['contact_phone'], str(_bk['customer_phone']));
    final area = [str(_bk['landmark']), str(_bk['address']), str(_bk['city'])]
        .where((s) => s.isNotEmpty).join(', ');
    final dist = toDoubleOrNull(_bk['distance_km']);
    final notes = str(_bk['notes']);
    final slot = slotWhen(_bk['slot_date'], _bk['slot_time']);
    // Website navBtn(): only once the job is confirmed (heading to the customer).
    final showNav = _status == 'confirmed';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          leading: Avatar(name: name, radius: 22),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(phone.isNotEmpty ? phone : 'Phone shown after the customer confirms'),
          trailing: phone.isNotEmpty
              ? IconButton.filledTonal(
                  tooltip: 'Call customer',
                  onPressed: _call,
                  icon: const Icon(Icons.call_rounded))
              : null,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (area.isNotEmpty) DetailLine(Icons.place_outlined, area),
            if (dist != null) DetailLine(Icons.near_me_outlined, '${dist.toStringAsFixed(1)} km away'),
            if (slot.isNotEmpty) DetailLine(Icons.schedule_rounded, slot),
            if (notes.isNotEmpty) DetailLine(Icons.sticky_note_2_outlined, notes),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              SummaryChips(summary),
            ],
            if (showNav) ...[
              const SizedBox(height: 14),
              BigButton('Navigate to Customer', icon: Icons.navigation_rounded, onPressed: _navigate),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _section(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _giveUp() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: BigButton('Give up this job',
            outlined: true, color: AppColors.red, onPressed: _busy ? null : _release),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.ink2)),
      );

  Widget _stateBody() {
    switch (_status) {
      case 'price_quoted':
        return _section([
          Notice('Waiting for customer to confirm your price ₹${toInt(_bk['quoted_price'])}',
              tone: Tone.info, icon: Icons.hourglass_top_rounded),
          _quoteLeft(),
          _giveUp(),
        ]);

      case 'negotiating':
        final counter = toInt(_bk['counter_price']);
        return _section([
          Notice('Customer offered ₹$counter (your quote ₹${toInt(_bk['quoted_price'])})',
              tone: Tone.warning, icon: Icons.forum_outlined),
          const SizedBox(height: 14),
          BigButton('Accept ₹$counter',
              icon: Icons.check_rounded,
              color: AppColors.green,
              busy: _busy,
              onPressed: () => _run(() => ProviderApiService.acceptCounter(_id), success: 'Accepted ✓')),
          const SizedBox(height: 10),
          BigButton('Send final price',
              icon: Icons.price_change_outlined, outlined: true, onPressed: _busy ? null : _sendFinalOffer),
          _giveUp(),
        ]);

      case 'negotiation_final':
        return _section([
          Notice('Final price ₹${toInt(_bk['final_price'])} sent — waiting for customer',
              tone: Tone.info, icon: Icons.hourglass_top_rounded),
          _quoteLeft(),
          _giveUp(),
        ]);

      case 'confirmed':
        return _section([
          _cashRuleNotice(),
          const Notice('Customer confirmed. Go to the customer and ask them for the Start OTP shown in their app.',
              tone: Tone.success),
          const SizedBox(height: 18),
          _label('Start OTP (from customer)'),
          OtpInput(controller: _startOtpCtrl, errorText: _otpError, enabled: !_busy),
          const SizedBox(height: 18),
          BigButton('Verify & Start Job', icon: Icons.key_rounded, busy: _busy, onPressed: _verifyStartOtp),
          _giveUp(),
        ]);

      case 'active':
        final requested = toInt(_bk['completion_otp_requested']) == 1;
        return _section([
          _jobTimer(),
          if (str(_bk['started_at']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('▶️ Work started at ${istTime(_bk['started_at'])}',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          _cashRuleNotice(),
          if (!requested) ...[
            const Notice('Job in progress. When the work is finished, tap below — the customer will get a completion OTP.',
                tone: Tone.info),
            const SizedBox(height: 14),
            BigButton('Work finished — request completion OTP',
                icon: Icons.task_alt_rounded, color: AppColors.green, busy: _busy, onPressed: _requestCompletionOtp),
          ] else ...[
            const Notice('The customer has received the Completion OTP. Ask them for it and enter it here.',
                tone: Tone.success),
            const SizedBox(height: 18),
            _label('Completion OTP (from customer)'),
            OtpInput(controller: _doneOtpCtrl, errorText: _otpError, enabled: !_busy),
            const SizedBox(height: 18),
            BigButton('Verify & Complete Job',
                icon: Icons.check_circle_rounded, color: AppColors.green, busy: _busy, onPressed: _complete),
            const SizedBox(height: 10),
            BigButton('Resend OTP to customer', outlined: true, onPressed: _busy ? null : _requestCompletionOtp),
          ],
        ]);

      case 'completed':
        return _paid ? _paidBody() : _paymentPendingBody();

      case 'cancelled':
        final reason = str(_bk['cancel_reason']);
        return _endCard(Icons.cancel_outlined, AppColors.red, 'Booking Cancelled',
            reason.isNotEmpty ? 'Reason: $reason' : 'This job was cancelled');

      default:
        return _section([Notice('Status: ${_status.replaceAll('_', ' ')}')]);
    }
  }

  // Told before the work starts: cash is only possible when the wallet can
  // cover the platform fee (it is deducted from the wallet on cash jobs).
  Widget _cashRuleNotice() {
    final fee = toInt(_bk['platform_fee']);
    if (toInt(_bk['cash_allowed'], 1) == 1 || fee <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Notice(
        'Online payment only for this job — your wallet balance is less than the platform fee ₹$fee. '
        'Tell the customer to pay online (do not collect cash), or add at least ₹$fee to your wallet to accept cash.',
        tone: Tone.error,
        icon: Icons.credit_card_rounded,
        action: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addMoney,
            icon: const Icon(Icons.add_card_rounded, size: 18),
            label: const Text('Add money'),
          ),
        ),
      ),
    );
  }

  Widget _paymentResult({required bool paid}) {
    final t = Theme.of(context).textTheme;
    final amt = bookingAmount(_bk);
    final method = str(_bk['payment_method']) == 'cash' ? 'in cash' : 'online';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: paid ? AppColors.greenSoft : AppColors.yellowSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(paid ? Icons.verified_rounded : Icons.hourglass_top_rounded,
            size: 36, color: paid ? AppColors.green : AppColors.yellow),
        const SizedBox(height: 6),
        Text(paid ? 'Payment Received' : 'Payment Pending', style: t.titleMedium),
        const SizedBox(height: 2),
        Text(paid ? '₹$amt paid $method' : '₹$amt — waiting for payment',
            style: t.bodyMedium?.copyWith(color: AppColors.muted)),
      ]),
    );
  }

  Widget _paymentPendingBody() {
    final amt = bookingAmount(_bk);
    return _section([
      _paymentResult(paid: false),
      if (toInt(_bk['cash_allowed'], 1) == 1) ...[
        const SizedBox(height: 12),
        Text('The customer can pay online in their app. If they paid you in cash, confirm it below.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        BigButton('💵 I collected cash ₹$amt', color: AppColors.green, busy: _busy, onPressed: _cashCollected),
      ] else ...[
        const SizedBox(height: 12),
        Notice('Online payment only. Your wallet balance is less than the platform fee '
            '₹${toInt(_bk['commission_amt'])} for this job, so cash can\'t be accepted. '
            'Ask the customer to pay online in their app, or add money to your wallet.',
            tone: Tone.error, icon: Icons.credit_card_rounded),
        const SizedBox(height: 12),
        BigButton('Add money to wallet', icon: Icons.add_card_rounded, outlined: true, onPressed: _addMoney),
      ],
      const SizedBox(height: 12),
      _moneyRows(),
      _workTimes(),
    ]);
  }

  Widget _paidBody() {
    final cash = str(_bk['payment_method']) == 'cash';
    final hasRating = toInt(_bk['rating']) > 0;
    return _section([
      _paymentResult(paid: true),
      if (!cash && str(_bk['provider_earns']).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('₹${toInt(_bk['provider_earns'])} added to your earnings balance',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ),
      if (cash && str(_bk['commission_amt']).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Commission ₹${toInt(_bk['commission_amt'])} deducted from your earnings balance',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ),
      const SizedBox(height: 12),
      _moneyRows(),
      _workTimes(),
      const SizedBox(height: 14),
      if (hasRating)
        Notice('Customer rated you ${toInt(_bk['rating'])}★'
            '${str(_bk['review']).isNotEmpty ? ' — "${str(_bk['review'])}"' : ''}', tone: Tone.success,
            icon: Icons.star_rounded)
      else
        BigButton(_reviewRequested ? 'Review requested' : '⭐ Ask Customer for Review',
            color: AppColors.brand, busy: _busy, onPressed: _reviewRequested ? null : _requestReview),
    ]);
  }

  Widget _moneyRows() => Column(children: [
        KeyValueRow('Job amount', '₹${toInt(_bk['amount'])}'),
        KeyValueRow('Platform commission (${toInt(_bk['commission_pct'])}%)', '− ₹${toInt(_bk['commission_amt'])}'),
        const Divider(height: 12),
        KeyValueRow('You earn', '₹${toInt(_bk['provider_earns'])}', bold: true, valueColor: AppColors.green),
      ]);

  /// "Customer has m:ss left to confirm" / "⌛ Time up — job will be released"
  Widget _quoteLeft() {
    final txt = quoteLeftText(_quoteDeadline);
    if (txt.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFB45309)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(txt,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
        ),
      ]),
    );
  }

  /// Started / closed / duration for a completed job.
  Widget _workTimes() {
    final st = str(_bk['started_at']), done = str(_bk['completed_at']);
    if (st.isEmpty && done.isEmpty) return const SizedBox.shrink();
    final dur = istDuration(st, done);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF3F7F8), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (st.isNotEmpty) Text('▶️ Started: ${istTime(st)}', style: Theme.of(context).textTheme.bodyMedium),
        if (done.isNotEmpty)
          Text('⏹️ Closed: ${istTime(done)}${dur.isNotEmpty ? ' · ⏱️ $dur' : ''}',
              style: Theme.of(context).textTheme.bodyMedium),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.timer_outlined, color: AppColors.teal2, size: 26),
        const SizedBox(width: 12),
        const Expanded(
            child: Text('Job in progress',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.teal2))),
        Text(t,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.teal2,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _endCard(IconData icon, Color color, String title, String body) => _section([
        Icon(icon, color: color, size: 48),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        BigButton('Back to jobs', icon: Icons.work_outline_rounded, onPressed: _exit),
      ]);

  Widget _endState(IconData icon, Color color, String title, String body) => ListView(
        padding: const EdgeInsets.all(24),
        children: [const SizedBox(height: 40), _endCard(icon, color, title, body)],
      );
}
