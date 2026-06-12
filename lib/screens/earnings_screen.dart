import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';

class EarningsScreen extends StatefulWidget {
  final String providerId;
  const EarningsScreen({super.key, required this.providerId});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _loading = true;
  double _totalEarned = 0;
  double _withdrawn = 0;
  double _available = 0;
  List<Map<String, dynamic>> _payouts = [];
  List<Map<String, dynamic>> _completedBookings = [];
  bool _requesting = false;
  final _amountCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final provSnap = await FirebaseDatabase.instance.ref('providers/${widget.providerId}').get();
      final bookSnap = await FirebaseDatabase.instance.ref('bookings').get();
      final payoutSnap = await FirebaseDatabase.instance.ref('payout_requests').get();

      double totalEarned = 0;
      double withdrawn = 0;
      List<Map<String, dynamic>> completed = [];
      List<Map<String, dynamic>> payouts = [];

      if (provSnap.exists) {
        final data = Map<String, dynamic>.from(provSnap.value as Map);
        totalEarned = ((data['totalEarned'] ?? 0) as num).toDouble();
      }

      if (bookSnap.exists) {
        final all = Map<String, dynamic>.from(bookSnap.value as Map);
        for (final entry in all.entries) {
          final b = Map<String, dynamic>.from(entry.value as Map);
          if (b['providerId'] == widget.providerId && b['status'] == 'completed') {
            completed.add({...b, 'id': entry.key});
          }
        }
        completed.sort((a, b) => (b['completedAt'] ?? '').compareTo(a['completedAt'] ?? ''));
      }

      if (payoutSnap.exists) {
        final all = Map<String, dynamic>.from(payoutSnap.value as Map);
        for (final entry in all.entries) {
          final p = Map<String, dynamic>.from(entry.value as Map);
          if (p['providerId'] == widget.providerId) {
            payouts.add({...p, 'id': entry.key});
            if (p['status'] == 'approved') {
              withdrawn += ((p['amount'] ?? 0) as num).toDouble();
            }
          }
        }
        payouts.sort((a, b) => (b['requestedAt'] ?? '').compareTo(a['requestedAt'] ?? ''));
      }

      setState(() {
        _totalEarned = totalEarned;
        _withdrawn = withdrawn;
        _available = totalEarned - withdrawn;
        _completedBookings = completed;
        _payouts = payouts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestWithdrawal() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid amount'), backgroundColor: AppColors.red));
      return;
    }
    if (amount > _available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount exceeds available balance'), backgroundColor: AppColors.red));
      return;
    }

    setState(() => _requesting = true);
    try {
      await FirebaseDatabase.instance.ref('payout_requests').push().set({
        'providerId': widget.providerId,
        'amount': amount,
        'bankDetails': _bankCtrl.text.trim(),
        'upiId': _upiCtrl.text.trim(),
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
      });

      _amountCtrl.clear();
      _bankCtrl.clear();
      _upiCtrl.clear();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Withdrawal request submitted!'), backgroundColor: AppColors.green));
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
    setState(() => _requesting = false);
  }

  void _showWithdrawDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Request Withdrawal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text('Available: ₹${_available.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankCtrl,
            decoration: InputDecoration(
              labelText: 'Bank Account / UPI ID',
              hintText: 'Account number or UPI',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _requesting ? null : _requestWithdrawal,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _requesting
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Earnings'), backgroundColor: AppColors.teal),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.teal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  // Stats
                  Row(children: [
                    _statCard('Total Earned', '₹${_totalEarned.toStringAsFixed(0)}', Icons.currency_rupee_rounded, AppColors.teal),
                    const SizedBox(width: 10),
                    _statCard('Withdrawn', '₹${_withdrawn.toStringAsFixed(0)}', Icons.account_balance_rounded, AppColors.muted),
                    const SizedBox(width: 10),
                    _statCard('Available', '₹${_available.toStringAsFixed(0)}', Icons.wallet_rounded, AppColors.green),
                  ]),

                  const SizedBox(height: 16),

                  // Withdraw button
                  if (_available > 0)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showWithdrawDialog,
                        icon: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                        label: Text('Request Withdrawal · ₹${_available.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // How it works
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                    ),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('HOW EARNINGS WORK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.teal, letterSpacing: 0.5)),
                      SizedBox(height: 8),
                      Text('Customer pays → Admin credits your wallet → Request withdrawal → Admin approves → Money in your bank within 24 hrs',
                        style: TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.5)),
                    ]),
                  ),

                  // Withdrawal requests
                  if (_payouts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft,
                      child: Text('Withdrawal History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink))),
                    const SizedBox(height: 10),
                    ..._payouts.map((p) {
                      final status = p['status'] ?? 'pending';
                      final color = status == 'approved' ? AppColors.green :
                                    status == 'rejected' ? AppColors.red : AppColors.yellow;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('₹${p['amount'] ?? 0}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            Text(p['bankDetails'] ?? p['upiId'] ?? '',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            Text((p['requestedAt'] ?? '').toString().substring(0, 10),
                              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(status.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                          ),
                        ]),
                      );
                    }).toList(),
                  ],

                  // Completed bookings
                  if (_completedBookings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft,
                      child: Text('Completed Jobs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink))),
                    const SizedBox(height: 10),
                    ..._completedBookings.take(20).map((b) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b['service'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                          Text('${b['customer'] ?? ''} · ${b['date'] ?? ''}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                        ])),
                        Text('₹${b['price'] ?? 0}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green)),
                      ]),
                    )).toList(),
                  ],

                  const SizedBox(height: 20),
                ]),
              ),
            ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
      ),
    );
  }
}
