import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import '../widgets/ui.dart';

/// Test-only sample data for screenshots (no network when set).
class EarningsDemo {
  final Map<String, dynamic> balance;
  final List<Map<String, dynamic>> payouts;
  final List<Map<String, dynamic>> jobs;
  const EarningsDemo({required this.balance, this.payouts = const [], this.jobs = const []});
}

/// Earnings tab (same sections as the website "Earnings" page):
/// balance (payouts.php?action=balance), commission due, wallet top-up via
/// Razorpay (topup_order → Checkout → topup_confirm), withdrawal request
/// (payouts.php?action=request, UPI or bank) and withdrawal history.
/// The app also lists completed jobs with the commission split.
class EarningsScreen extends StatefulWidget {
  final String providerId;
  /// Scroll to the "Add money to wallet" card on open.
  final bool openTopUp;
  /// Shown as a bottom-navigation tab (no back arrow).
  final bool embedded;
  /// Bumped by the shell each time the tab is selected → reload.
  final int refreshTick;
  /// Bumped by the shell to jump to the top-up card.
  final int topUpTick;
  final Map<String, dynamic>? profile;
  final EarningsDemo? demo;
  const EarningsScreen({
    super.key,
    required this.providerId,
    this.openTopUp = false,
    this.embedded = false,
    this.refreshTick = 0,
    this.topUpTick = 0,
    this.profile,
    this.demo,
  });
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _balance = {};
  List<Map<String, dynamic>> _payouts = [];
  List<Map<String, dynamic>> _jobs = [];

  int get _due => toInt(_balance['commission_due']);

  // Wallet top-up
  final _topUpCtrl = TextEditingController();
  final _topUpKey = GlobalKey();
  Razorpay? _rzp;
  bool _toppingUp = false;
  int _topUpAmount = 0; // amount of the checkout in progress (₹)
  String _orderId = '';

  // Withdrawal
  String _wdType = 'upi';
  final _wdAmt = TextEditingController();
  final _wdUpi = TextEditingController();
  final _wdAcc = TextEditingController();
  final _wdIfsc = TextEditingController();
  final _wdBank = TextEditingController();
  bool _wdBusy = false;

  bool get _demo => widget.demo != null;

  @override
  void initState() {
    super.initState();
    _wdUpi.text = str(widget.profile?['upi_id']);
    if (_demo) {
      _balance = widget.demo!.balance;
      _payouts = widget.demo!.payouts;
      _jobs = widget.demo!.jobs;
      _loading = false;
      return;
    }
    try {
      _rzp = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaySuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPayError)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    } catch (e) {
      debugPrint('Razorpay init failed: $e');
    }
    _load().then((_) {
      if (widget.openTopUp || widget.topUpTick > 0) _focusTopUp();
    });
  }

  @override
  void didUpdateWidget(EarningsScreen old) {
    super.didUpdateWidget(old);
    if (_demo) return;
    if (old.refreshTick != widget.refreshTick) _load();
    if (old.topUpTick != widget.topUpTick) _focusTopUp();
    if (_wdUpi.text.isEmpty && str(widget.profile?['upi_id']).isNotEmpty) {
      _wdUpi.text = str(widget.profile?['upi_id']);
    }
  }

  @override
  void dispose() {
    try { _rzp?.clear(); } catch (_) {}
    for (final c in [_topUpCtrl, _wdAmt, _wdUpi, _wdAcc, _wdIfsc, _wdBank]) {
      c.dispose();
    }
    super.dispose();
  }

  void _focusTopUp() {
    if (_due > 0 && _topUpCtrl.text.isEmpty) {
      _topUpCtrl.text = '${_due < 100 ? 100 : _due}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _topUpKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
      }
    });
  }

  Future<void> _startTopUp() async {
    if (_toppingUp || _demo) return;
    final amount = int.tryParse(_topUpCtrl.text.trim()) ?? 0;
    if (amount < 100) { showSnack(context, 'Minimum top-up is ₹100', tone: Tone.error); return; }
    if (_rzp == null) {
      showSnack(context, 'Payment page could not load — check your internet', tone: Tone.error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _toppingUp = true);
    final res = await ProviderApiService.topupOrder(amount);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _toppingUp = false);
      if (!res.unauthorized) {
        showSnack(context, res.error.isNotEmpty ? res.error : 'Could not start payment', tone: Tone.error);
      }
      return;
    }
    final o = res.map ?? {};
    final me = await ProviderApiService.getCachedProvider() ?? {};
    _topUpAmount = amount;
    _orderId = str(o['order_id']);
    try {
      _rzp!.open({
        'key': str(o['key_id']),
        'amount': toInt(o['amount'], amount * 100),
        'currency': str(o['currency'], 'INR'),
        'order_id': str(o['order_id']),
        'name': 'HamaraService',
        'description': 'Provider wallet top-up',
        'prefill': {
          'name': str(me['name']),
          'email': str(me['email']),
          'contact': str(me['phone']),
        },
        'theme': {'color': '#0F4C5C'},
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _toppingUp = false);
      showSnack(context, 'Could not open the payment page: $e', tone: Tone.error);
    }
  }

  Future<void> _onPaySuccess(PaymentSuccessResponse r) async {
    final res = await ProviderApiService.topupConfirm(
      orderId: (r.orderId ?? '').isNotEmpty ? r.orderId! : _orderId,
      paymentId: r.paymentId ?? '',
      signature: r.signature ?? '',
    );
    if (!mounted) return;
    setState(() => _toppingUp = false);
    if (res.ok) {
      _topUpCtrl.clear();
      showSnack(context, '✅ ₹$_topUpAmount added to your wallet', tone: Tone.success);
    } else if (!res.unauthorized) {
      showSnack(context, res.error.isNotEmpty ? res.error : 'Verification pending — it will update shortly',
          tone: Tone.warning);
    }
    _load();
  }

  void _onPayError(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _toppingUp = false);
    final cancelled = r.code == Razorpay.PAYMENT_CANCELLED;
    final msg = (r.message ?? '').trim();
    showSnack(context,
        cancelled
            ? 'Payment cancelled'
            : 'Payment failed: ${msg.isNotEmpty && !msg.startsWith('{') ? msg : 'try again'}',
        tone: cancelled ? Tone.neutral : Tone.error);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    if (!mounted) return;
    setState(() => _toppingUp = false);
    showSnack(context, 'Complete the payment in ${r.walletName ?? 'your wallet app'}. '
        'Your balance updates once it is confirmed.');
    Future.delayed(const Duration(seconds: 8), () { if (mounted) _load(); });
  }

  Future<void> _load() async {
    if (_demo) return;
    setState(() { _loading = true; _error = ''; });
    final results = await Future.wait([
      ProviderApiService.getBalance(),
      ProviderApiService.getPayoutHistory(),
      ProviderApiService.getBookingHistory(),
    ]);
    if (!mounted) return;
    final bal = results[0], pay = results[1], hist = results[2];
    setState(() {
      _loading = false;
      if (bal.ok) _balance = bal.map ?? {};
      if (pay.ok) _payouts = pay.list;
      if (hist.ok) {
        _jobs = hist.list.where((b) => str(b['status']) == 'completed').toList();
      }
      final firstErr = [bal, pay, hist].where((r) => !r.ok && !r.unauthorized).map((r) => r.error);
      _error = firstErr.isEmpty ? '' : firstErr.first;
    });
  }

  /// Same checks and messages as the website requestPayout().
  Future<void> _requestPayout() async {
    if (_wdBusy || _demo) return;
    final amt = int.tryParse(_wdAmt.text.trim()) ?? 0;
    if (amt < 100) { showSnack(context, 'Minimum withdrawal is ₹100', tone: Tone.error); return; }
    final body = <String, dynamic>{'amount': amt, 'account_type': _wdType};
    if (_wdType == 'upi') {
      body['upi_id'] = _wdUpi.text.trim();
      if (!'${body['upi_id']}'.contains('@')) {
        showSnack(context, 'Enter a valid UPI ID', tone: Tone.error);
        return;
      }
    } else {
      body['account_no'] = _wdAcc.text.replaceAll(RegExp(r'\s'), '');
      body['ifsc'] = _wdIfsc.text.trim().toUpperCase();
      body['bank_name'] = _wdBank.text.trim();
      if (!RegExp(r'^\d{6,20}$').hasMatch('${body['account_no']}')) {
        showSnack(context, 'Enter a valid account number', tone: Tone.error);
        return;
      }
      if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch('${body['ifsc']}')) {
        showSnack(context, 'Enter a valid IFSC', tone: Tone.error);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => _wdBusy = true);
    final res = await ProviderApiService.requestPayout(body);
    if (!mounted) return;
    setState(() => _wdBusy = false);
    if (res.ok) {
      showSnack(context, '✅ Withdrawal requested', tone: Tone.success);
      _wdAmt.clear();
      _load();
    } else if (!res.unauthorized) {
      showSnack(context, res.error.isNotEmpty ? res.error : 'Request failed', tone: Tone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading && _balance.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error.isNotEmpty)
                    Notice(_error, tone: Tone.error, margin: const EdgeInsets.only(bottom: 12)),
                  _balanceCard(),
                  if (_due > 0 || toDouble(_balance['pending_earned']) < 0) ...[
                    const SizedBox(height: 12),
                    Notice(
                        'Commission due on cash jobs: ₹${_due > 0 ? _due : toDouble(_balance['pending_earned']).abs().round()}. '
                        'If dues grow too large you cannot accept new jobs.',
                        tone: Tone.error,
                        icon: Icons.warning_amber_rounded),
                  ],
                  SectionTitle('Add money to wallet', key: _topUpKey),
                  _topUpCard(),
                  const SectionTitle('Request withdrawal'),
                  _withdrawCard(),
                  const SectionTitle('Withdrawal history'),
                  if (_payouts.isEmpty)
                    const Card(child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No withdrawals yet'))
                  else
                    Card(
                      child: Column(children: [
                        for (var i = 0; i < _payouts.length; i++) ...[
                          if (i > 0) const Divider(indent: 72),
                          _payoutTile(_payouts[i]),
                        ],
                      ]),
                    ),
                  if (_jobs.isNotEmpty) ...[
                    SectionTitle('Completed jobs (${_jobs.length})'),
                    Card(
                      child: Column(children: [
                        for (var i = 0; i < _jobs.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          _jobTile(_jobs[i]),
                        ],
                      ]),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _balanceCard() {
    final t = Theme.of(context).textTheme;
    Widget mini(String label, dynamic v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(money(v),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.teal2, AppColors.teal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Text('Available balance', style: t.bodyMedium?.copyWith(color: Colors.white70)),
        ]),
        const SizedBox(height: 6),
        Text(money(_balance['available']),
            style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        Text('${toInt(_balance['completed_bookings'])} completed jobs',
            style: t.bodySmall?.copyWith(color: Colors.white70)),
        const SizedBox(height: 16),
        Container(height: 1, color: Colors.white24),
        const SizedBox(height: 14),
        Row(children: [
          mini('Total earned', _balance['total_earned']),
          mini('In process', _balance['in_process']),
          mini('Withdrawn', _balance['withdrawn']),
        ]),
      ]),
    );
  }

  Widget _topUpCard() {
    final cur = int.tryParse(_topUpCtrl.text.trim()) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('For cash jobs the platform fee is taken from your wallet. '
              'Keep enough balance to accept cash payments.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [200, 500, 1000].map((a) => ChoiceChip(
                label: Text('₹$a'),
                selected: cur == a,
                showCheckmark: false,
                onSelected: _toppingUp ? null : (_) => setState(() => _topUpCtrl.text = '$a'),
              )).toList()),
          const SizedBox(height: 12),
          TextField(
            controller: _topUpCtrl,
            enabled: !_toppingUp,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Amount (₹, minimum 100)', hintText: 'e.g. 500', prefixText: '₹ '),
          ),
          const SizedBox(height: 12),
          BigButton(cur >= 100 ? 'Add ₹$cur to wallet' : 'Add Money',
              icon: Icons.add_rounded, color: AppColors.green, busy: _toppingUp, onPressed: _startTopUp),
        ]),
      ),
    );
  }

  Widget _withdrawCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _wdAmt,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Amount (₹, minimum 100)', prefixText: '₹ '),
          ),
          const SizedBox(height: 14),
          Text('Send to', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'upi', label: Text('UPI'), icon: Icon(Icons.qr_code_2_rounded)),
              ButtonSegment(value: 'bank', label: Text('Bank account'), icon: Icon(Icons.account_balance_rounded)),
            ],
            selected: {_wdType},
            onSelectionChanged: (s) => setState(() => _wdType = s.first),
          ),
          const SizedBox(height: 14),
          if (_wdType == 'upi')
            TextField(
              controller: _wdUpi,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'name@bank'),
            )
          else ...[
            TextField(
              controller: _wdAcc,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Account number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wdIfsc,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'IFSC', hintText: 'SBIN0001234'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wdBank,
              decoration: const InputDecoration(labelText: 'Bank name'),
            ),
          ],
          const SizedBox(height: 14),
          BigButton('Request Withdrawal', icon: Icons.north_east_rounded, busy: _wdBusy, onPressed: _requestPayout),
          const SizedBox(height: 10),
          Text('Withdrawals are reviewed and transferred by HamaraService. '
              'Commission on cash jobs is deducted from your balance.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _payoutTile(Map<String, dynamic> p) {
    final status = str(p['status'], 'pending');
    final dest = str(p['account_type']) == 'bank'
        ? '${str(p['bank_name'], 'Bank')} ••${str(p['account_last4'])}'
        : str(p['upi_id'], 'UPI');
    final when = str(p['requested_at']);
    final note = str(p['note']);
    return ListTile(
      leading: const IconTile(Icons.north_east_rounded),
      title: Text(money(p['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        '$dest · ${when.length > 16 ? when.substring(0, 16) : when}',
        if (note.isNotEmpty) note,
      ].join('\n')),
      trailing: StatusBadge(status, label: status),
    );
  }

  Widget _jobTile(Map<String, dynamic> j) {
    final paid = str(j['payment_status']) == 'paid';
    final method = str(j['payment_method']);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(j['svc_name'], 'Service'), style: t.titleSmall),
              Text([str(j['other_party']), fmtDate(j['completed_at'] ?? j['slot_date'])]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: t.bodySmall),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${toInt(j['provider_earns'])}',
                style: t.titleMedium?.copyWith(color: AppColors.green, fontWeight: FontWeight.w700)),
            Text(paid ? (method == 'cash' ? 'Paid in cash' : 'Paid online') : 'Payment pending',
                style: t.bodySmall?.copyWith(color: paid ? AppColors.muted : AppColors.yellow)),
          ]),
        ]),
        const SizedBox(height: 6),
        Text('Job ₹${toInt(j['amount'])} · Commission (${toInt(j['commission_pct'])}%) ₹${toInt(j['commission_amt'])}',
            style: t.bodySmall),
      ]),
    );
  }
}

/// ₹1,23,456 (Indian grouping, like the website's money()).
String money(dynamic v) {
  final n = toDouble(v).round();
  final neg = n < 0;
  var s = n.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$s';
}
