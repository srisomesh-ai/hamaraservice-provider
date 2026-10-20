import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

/// Wallet: payouts.php?action=balance, payout history, completed jobs,
/// withdrawal requests (payouts.php?action=request) and wallet top-up via
/// Razorpay (payouts.php?action=topup_order → Checkout → topup_confirm).
class EarningsScreen extends StatefulWidget {
  final String providerId;
  /// Scroll to / highlight the "Add money to wallet" card on open.
  final bool openTopUp;
  const EarningsScreen({super.key, required this.providerId, this.openTopUp = false});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _balance = {};
  List<Map<String, dynamic>> _payouts = [];
  List<Map<String, dynamic>> _jobs = [];

  int get _available => toInt(_balance['available']);
  int get _due => toInt(_balance['commission_due']);

  // Wallet top-up
  final _topUpCtrl = TextEditingController();
  final _topUpKey = GlobalKey();
  final _listCtrl = ScrollController();
  Razorpay? _rzp;
  bool _toppingUp = false;
  int _topUpAmount = 0; // amount of the checkout in progress (₹)
  String _orderId = '';

  @override
  void initState() {
    super.initState();
    try {
      _rzp = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaySuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPayError)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    } catch (e) {
      debugPrint('Razorpay init failed: $e');
    }
    _load().then((_) {
      if (widget.openTopUp) {
        if (_due > 0 && _topUpCtrl.text.isEmpty) {
          _topUpCtrl.text = '${_due < 100 ? 100 : _due}';
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _topUpKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350));
          }
        });
      }
    });
  }

  @override
  void dispose() {
    try { _rzp?.clear(); } catch (_) {}
    _topUpCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color,
          behavior: SnackBarBehavior.floating));
  }

  Future<void> _startTopUp() async {
    if (_toppingUp) return;
    final amount = int.tryParse(_topUpCtrl.text.trim()) ?? 0;
    if (amount < 100) { _snack('Minimum top-up is ₹100', AppColors.red); return; }
    if (_rzp == null) { _snack('Payments are not available on this device', AppColors.red); return; }
    FocusScope.of(context).unfocus();
    setState(() => _toppingUp = true);
    final res = await ProviderApiService.topupOrder(amount);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _toppingUp = false);
      if (!res.unauthorized) _snack(res.error.isNotEmpty ? res.error : 'Could not start payment', AppColors.red);
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
      _snack('Could not open the payment page: $e', AppColors.red);
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
      _snack('✅ ₹$_topUpAmount added to your wallet', AppColors.green);
    } else if (!res.unauthorized) {
      _snack(res.error.isNotEmpty ? res.error : 'Verification pending — your wallet will update shortly',
          AppColors.yellow);
    }
    _load();
  }

  void _onPayError(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _toppingUp = false);
    final cancelled = r.code == Razorpay.PAYMENT_CANCELLED;
    final msg = (r.message ?? '').trim();
    _snack(cancelled
        ? 'Payment cancelled'
        : 'Payment failed: ${msg.isNotEmpty && !msg.startsWith('{') ? msg : 'please try again'}',
        cancelled ? AppColors.muted : AppColors.red);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    if (!mounted) return;
    setState(() => _toppingUp = false);
    _snack('Complete the payment in ${r.walletName ?? 'your wallet app'}. '
        'Your balance updates once it is confirmed.', AppColors.teal);
    Future.delayed(const Duration(seconds: 8), () { if (mounted) _load(); });
  }

  Future<void> _load() async {
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

  void _openWithdraw() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _WithdrawSheet(available: _available),
    ).then((submitted) {
      if (submitted == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Withdrawal request submitted. Admin will process it shortly.'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 4),
        ));
        _load();
      }
    });
  }

  /// Pay dues = add money to the wallet (prefilled with the amount owed).
  void _payDues() {
    _topUpCtrl.text = '${_due < 100 ? 100 : _due}';
    final ctx = _topUpKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Earnings'), backgroundColor: AppColors.teal),
      body: _loading && _balance.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.teal,
              child: ListView(
                controller: _listCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty) _note(_error, AppColors.red),
                  if (_due > 0) _duesCard(),
                  _balanceCard(),
                  const SizedBox(height: 12),
                  _topUpCard(),
                  const SizedBox(height: 12),
                  Row(children: [
                    _stat('Total earned', '₹${toInt(_balance['total_earned'])}', AppColors.green),
                    const SizedBox(width: 10),
                    _stat('Withdrawn', '₹${toInt(_balance['withdrawn'])}', AppColors.teal),
                    const SizedBox(width: 10),
                    _stat('In process', '₹${toInt(_balance['in_process'])}', AppColors.yellow),
                  ]),
                  const SizedBox(height: 12),
                  _note('Online-paid jobs add your share to the wallet. Cash jobs deduct the '
                      'platform fee from your wallet — cash is only allowed while your wallet '
                      'covers that fee. Withdrawals are processed by admin.',
                      AppColors.teal),
                  if (_payouts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _heading('Withdrawal requests'),
                    ..._payouts.map(_payoutTile),
                  ],
                  if (_jobs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _heading('Completed jobs (${_jobs.length})'),
                    ..._jobs.map(_jobTile),
                  ],
                  if (_jobs.isEmpty && _payouts.isEmpty && !_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Column(children: [
                        Text('₹0', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.muted)),
                        Text('No completed jobs yet', style: TextStyle(fontSize: 15, color: AppColors.muted)),
                      ]),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _duesCard() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.red.withOpacity(0.5), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.red),
            const SizedBox(width: 8),
            Text('Commission due ₹$_due',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.red)),
          ]),
          const SizedBox(height: 4),
          const Text('Pay dues to keep receiving jobs',
              style: TextStyle(fontSize: 13, color: AppColors.ink2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _payDues,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.red),
              minimumSize: const Size(140, 40),
            ),
            child: const Text('Add money to wallet', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _balanceCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF0A2E36), AppColors.teal],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Available to withdraw',
                  style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
              Text('₹$_available',
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
              Text('${toInt(_balance['completed_bookings'])} completed jobs',
                  style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: _available >= 100 ? _openWithdraw : null,
            icon: const Icon(Icons.account_balance_rounded, size: 18, color: Colors.white),
            label: const Text('Withdraw', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              disabledBackgroundColor: Colors.white24,
              minimumSize: const Size(120, 46),
            ),
          ),
        ]),
      );

  Widget _topUpCard() {
    final cur = int.tryParse(_topUpCtrl.text.trim()) ?? 0;
    return Container(
      key: _topUpKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.teal.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.add_card_rounded, color: AppColors.teal),
          SizedBox(width: 8),
          Text('Add money to wallet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        ]),
        const SizedBox(height: 4),
        const Text('Keep enough balance to cover the platform fee so customers can pay you in cash.',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [200, 500, 1000].map((a) {
          final sel = cur == a;
          return ChoiceChip(
            label: Text('₹$a'),
            selected: sel,
            selectedColor: AppColors.tealSoft,
            labelStyle: TextStyle(
                fontWeight: FontWeight.w700, color: sel ? AppColors.teal : AppColors.ink2),
            onSelected: _toppingUp ? null : (_) => setState(() => _topUpCtrl.text = '$a'),
          );
        }).toList()),
        const SizedBox(height: 10),
        TextField(
          controller: _topUpCtrl,
          enabled: !_toppingUp,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Amount (min ₹100)',
            prefixText: '₹ ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _toppingUp ? null : _startTopUp,
          icon: _toppingUp
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
          label: Text(cur >= 100 ? 'Add ₹$cur to wallet' : 'Add money to wallet',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    );
  }

  Widget _payoutTile(Map<String, dynamic> w) {
    final status = str(w['status'], 'pending');
    final color = status == 'approved'
        ? AppColors.green
        : status == 'rejected' ? AppColors.red : AppColors.yellow;
    final dest = str(w['account_type']) == 'bank'
        ? '${str(w['bank_name'], 'Bank')} ••${str(w['account_last4'])}'
        : 'UPI ${str(w['upi_id'])}';
    final note = str(w['note']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Icon(Icons.account_balance_rounded, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('₹${toInt(w['amount'])}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            Text(dest, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            Text('Requested ${fmtDate(w['requested_at'])}'
                '${str(w['processed_at']).isNotEmpty ? ' · processed ${fmtDate(w['processed_at'])}' : ''}',
                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            if (note.isNotEmpty)
              Text(note, style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(status.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ),
      ]),
    );
  }

  Widget _jobTile(Map<String, dynamic> j) {
    final paid = str(j['payment_status']) == 'paid';
    final method = str(j['payment_method']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(j['svc_name'], 'Service'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('${str(j['other_party'])} · ${fmtDate(j['completed_at'] ?? j['slot_date'])}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${toInt(j['provider_earns'])}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.green)),
            Text(paid ? (method == 'cash' ? 'cash' : 'online') : 'payment pending',
                style: TextStyle(fontSize: 10, color: paid ? AppColors.muted : AppColors.yellow)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _mini('Job amount', '₹${toInt(j['amount'])}', AppColors.teal),
          _mini('Commission (${toInt(j['commission_pct'])}%)', '₹${toInt(j['commission_amt'])}', AppColors.red),
          _mini('Your share', '₹${toInt(j['provider_earns'])}', AppColors.green),
        ]),
      ]),
    );
  }

  Widget _mini(String label, String value, Color color) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ]),
        ),
      );

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
      );

  Widget _note(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      );
}

class _WithdrawSheet extends StatefulWidget {
  final int available;
  const _WithdrawSheet({required this.available});
  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  String _type = 'upi';
  final _amount = TextEditingController();
  final _upi = TextEditingController();
  final _acct = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();
  bool _submitting = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_amount, _upi, _acct, _ifsc, _bank]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    String err = '';
    if (amount < 100) {
      err = 'Minimum withdrawal is ₹100';
    } else if (amount > widget.available) {
      err = 'Amount exceeds available balance (₹${widget.available})';
    } else if (_type == 'upi' &&
        !RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(_upi.text.trim())) {
      err = 'Enter a valid UPI ID (e.g. name@okbank)';
    } else if (_type == 'bank') {
      final acct = _acct.text.replaceAll(RegExp(r'\s'), '');
      final ifsc = _ifsc.text.trim().toUpperCase();
      if (!RegExp(r'^\d{6,18}$').hasMatch(acct)) {
        err = 'Enter a valid account number';
      } else if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) {
        err = 'Enter a valid IFSC code';
      } else if (_bank.text.trim().isEmpty) {
        err = 'Enter the bank name';
      }
    }
    if (err.isNotEmpty) {
      setState(() => _error = err);
      return;
    }
    setState(() { _submitting = true; _error = ''; });
    final res = await ProviderApiService.requestPayout({
      'amount': amount,
      'account_type': _type,
      if (_type == 'upi') 'upi_id': _upi.text.trim(),
      if (_type == 'bank') ...{
        'account_no': _acct.text.replaceAll(RegExp(r'\s'), ''),
        'ifsc': _ifsc.text.trim().toUpperCase(),
        'bank_name': _bank.text.trim(),
      },
    });
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() { _submitting = false; _error = res.error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Request Withdrawal',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('Available: ₹${widget.available}',
              style: const TextStyle(fontSize: 14, color: AppColors.green, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _input(_amount, 'Amount (₹)', keyboard: TextInputType.number, prefix: '₹ '),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _typeBtn('upi', 'UPI', Icons.qr_code_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _typeBtn('bank', 'Bank account', Icons.account_balance_rounded)),
          ]),
          const SizedBox(height: 12),
          if (_type == 'upi')
            _input(_upi, 'UPI ID', hint: 'name@okbank')
          else ...[
            _input(_acct, 'Account number', keyboard: TextInputType.number),
            const SizedBox(height: 10),
            _input(_ifsc, 'IFSC code', hint: 'SBIN0001234', caps: true),
            const SizedBox(height: 10),
            _input(_bank, 'Bank name'),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_error, style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Withdrawal Request',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _typeBtn(String key, String label, IconData icon) {
    final sel = _type == key;
    return GestureDetector(
      onTap: () => setState(() { _type = key; _error = ''; }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? AppColors.teal : AppColors.line, width: sel ? 2 : 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: sel ? AppColors.teal : AppColors.muted),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? AppColors.teal : AppColors.ink2)),
        ]),
      ),
    );
  }

  Widget _input(TextEditingController c, String label,
          {String? hint, String? prefix, TextInputType? keyboard, bool caps = false}) =>
      TextField(
        controller: c,
        keyboardType: keyboard,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}
