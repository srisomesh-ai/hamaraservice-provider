import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';

// Commission rates per service (matching web admin)
const Map<String, double> _commissionRates = {
  'House Maid': 10,
  'Deep Cleaning': 12,
  'Bathroom Cleaning': 10,
  'Kitchen Cleaning': 12,
  'Sofa / Carpet Cleaning': 12,
  'Laundry / Ironing': 10,
  'Pest Control': 10,
  'Gardener': 10,
  'AC Service': 12,
  'AC Cleaning': 12,
  'AC Repair': 18,
  'Appliance Repair': 18,
  'Home Appliance Repair': 18,
  'Electrician': 20,
  'Plumber': 20,
  'Carpenter': 12,
  'Painter': 12,
  'Solar Panel': 12,
  'Water Purifier': 15,
  'CCTV': 15,
  'Car / Bike Wash': 10,
  'Car Wash': 10,
  'Bike Wash': 10,
  'Car Mechanic': 15,
  'Driver': 15,
  'Doctor Visit': 15,
  'Nurse Visit': 15,
  'Lab Test': 15,
  'Fitness Trainer': 15,
  'Massage': 15,
  'Women Beauty': 15,
  'Men Haircut': 10,
  'Babysitter': 10,
  'Elderly Care': 10,
  'Security Guard': 10,
  'Civil / Mason': 12,
};

double _getCommission(String service) {
  for (final key in _commissionRates.keys) {
    if (service.toLowerCase().contains(key.toLowerCase()) ||
        key.toLowerCase().contains(service.toLowerCase())) {
      return _commissionRates[key]!;
    }
  }
  return 10; // default 10%
}

class EarningsScreen extends StatefulWidget {
  final String providerId;
  const EarningsScreen({super.key, required this.providerId});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _loading = true;
  double _totalCustomerPaid = 0;
  double _totalCommission = 0;
  double _totalNetEarned = 0;
  double _totalWithdrawn = 0;
  double _availableBalance = 0;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _withdrawals = [];
  bool _requesting = false;
  final _amountCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      double totalPaid = 0;
      double totalComm = 0;
      double totalNet = 0;
      double withdrawn = 0;
      List<Map<String, dynamic>> jobs = [];
      List<Map<String, dynamic>> withdrawals = [];

      // Load completed bookings
      final bookSnap = await FirebaseDatabase.instance.ref('bookings').get();
      if (bookSnap.exists) {
        final all = Map<String, dynamic>.from(bookSnap.value as Map);
        for (final entry in all.entries) {
          final b = Map<String, dynamic>.from(entry.value as Map);
          if ((b['providerId'] == widget.providerId ||
                  (b['acceptedBy'] is Map && b['acceptedBy']['id'] == widget.providerId)) &&
              b['status'] == 'completed' &&
              b['paymentStatus'] == 'paid') {
            final paid = ((b['amountPaid'] ?? b['priceVal'] ?? b['price'] ?? 0) as num).toDouble();
            final serviceName = b['service'] as String? ?? '';
            final commRate = _getCommission(serviceName);
            final commAmt = (paid * commRate / 100).roundToDouble();
            final netEarned = paid - commAmt;

            totalPaid += paid;
            totalComm += commAmt;
            totalNet += netEarned;

            jobs.add({
              'id': entry.key,
              'service': serviceName,
              'customer': b['customer'] ?? '',
              'date': b['date'] ?? '',
              'paid': paid,
              'commRate': commRate,
              'commAmt': commAmt,
              'netEarned': netEarned,
              'completedAt': b['completedAt'] ?? b['paidAt'] ?? '',
              'paymentMethod': b['paymentMethod'] ?? 'cash',
            });
          }
        }
        jobs.sort((a, b) =>
            (b['completedAt'] as String).compareTo(a['completedAt'] as String));
      }

      // Load withdrawal requests
      final payoutSnap = await FirebaseDatabase.instance.ref('payout_requests').get();
      if (payoutSnap.exists) {
        final all = Map<String, dynamic>.from(payoutSnap.value as Map);
        for (final entry in all.entries) {
          final p = Map<String, dynamic>.from(entry.value as Map);
          if (p['providerId'] == widget.providerId) {
            final amt = ((p['amount'] ?? 0) as num).toDouble();
            // Deduct both pending AND approved from available balance
            if (p['status'] == 'approved' || p['status'] == 'pending') withdrawn += amt;
            withdrawals.add({...p, 'id': entry.key});
          }
        }
        withdrawals.sort((a, b) =>
            (b['requestedAt'] ?? '').compareTo(a['requestedAt'] ?? ''));
      }

      final available = totalNet - withdrawn;

      // Sync totalEarned to provider profile
      await FirebaseDatabase.instance.ref('providers/${widget.providerId}').update({
        'totalEarned': available > 0 ? available : 0,
        'totalGrossEarned': totalNet,
      });

      setState(() {
        _totalCustomerPaid = totalPaid;
        _totalCommission = totalComm;
        _totalNetEarned = totalNet;
        _totalWithdrawn = withdrawn;
        _availableBalance = available;
        _jobs = jobs;
        _withdrawals = withdrawals;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestWithdrawal() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid amount'), backgroundColor: AppColors.red));
      return;
    }
    if (amount > _availableBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount exceeds available balance'), backgroundColor: AppColors.red));
      return;
    }
    if (_bankCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter bank account or UPI ID'), backgroundColor: AppColors.red));
      return;
    }

    setState(() => _requesting = true);
    try {
      // Load provider name first
      final provSnap = await FirebaseDatabase.instance.ref('providers/${widget.providerId}').get();
      final provData = provSnap.exists ? Map<String, dynamic>.from(provSnap.value as Map) : <String, dynamic>{};
      final provName = provData['name']?.toString() ?? '';
      final provPhone = provData['phone']?.toString() ?? '';

      await FirebaseDatabase.instance.ref('payout_requests').push().set({
        'providerId': widget.providerId,
        'providerName': provName,
        'providerPhone': provPhone,
        'amount': amount,
        'bankDetails': _bankCtrl.text.trim(),
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
        'availableBalance': _availableBalance,
      });

      _amountCtrl.clear();
      _bankCtrl.clear();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Withdrawal request submitted! Admin will process within 24 hours.'),
              backgroundColor: AppColors.green, duration: Duration(seconds: 4)));
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20, right: 20, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Request Withdrawal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text('Available: Rs.${_availableBalance.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14, color: AppColors.green, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('How it works:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.teal)),
                SizedBox(height: 4),
                Text('1. Submit request here\n2. Admin reviews on web panel\n3. Admin approves and transfers\n4. Money in your account within 24 hrs',
                    style: TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (Rs.)',
                hintText: 'Max: Rs.${_availableBalance.toStringAsFixed(0)}',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixText: 'Rs. ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankCtrl,
              decoration: InputDecoration(
                labelText: 'Bank Account / UPI ID',
                hintText: 'e.g. 9876543210@upi or account number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requesting ? null : _requestWithdrawal,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _requesting
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Submit Withdrawal Request', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
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

                  // Summary cards
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF0A2E36), AppColors.teal],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(children: [
                      const Text('Earnings Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 16),
                      Row(children: [
                        _summaryCard('Customer Paid', 'Rs.${_totalCustomerPaid.toStringAsFixed(0)}', Icons.payments_rounded, Colors.white),
                        const SizedBox(width: 10),
                        _summaryCard('Platform Fee', 'Rs.${_totalCommission.toStringAsFixed(0)}', Icons.percent_rounded, Colors.white70),
                        const SizedBox(width: 10),
                        _summaryCard('Your Earnings', 'Rs.${_totalNetEarned.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, AppColors.green),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 14),

                  // Balance card
                  Row(children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.green.withOpacity(0.3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Available Balance', style: TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w600)),
                          Text('Rs.${_availableBalance.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.green)),
                          Text('Withdrawn: Rs.${_totalWithdrawn.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                        ]),
                      ),
                    ),
                    if (_availableBalance > 0) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _showWithdrawDialog,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.account_balance_rounded, color: Colors.white, size: 28),
                            SizedBox(height: 4),
                            Text('Withdraw', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                          ]),
                        ),
                      ),
                    ],
                  ]),

                  const SizedBox(height: 14),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text('Withdrawals are processed by admin within 24 hours of approval.',
                          style: TextStyle(fontSize: 12, color: AppColors.teal))),
                    ]),
                  ),

                  // Withdrawal history
                  if (_withdrawals.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft,
                        child: Text('Withdrawal Requests', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink))),
                    const SizedBox(height: 10),
                    ..._withdrawals.map((w) {
                      final status = w['status'] ?? 'pending';
                      final color = status == 'approved' ? AppColors.green : status == 'rejected' ? AppColors.red : AppColors.yellow;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                        child: Row(children: [
                          Container(width: 40, height: 40,
                              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.account_balance_rounded, color: color, size: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Rs.${w['amount'] ?? 0}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            Text(w['bankDetails'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            Text((w['requestedAt'] ?? '').toString().substring(0, 10),
                                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                          ),
                        ]),
                      );
                    }).toList(),
                  ],

                  // Job breakdown
                  if (_jobs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Job Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      Text('${_jobs.length} completed', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 10),
                    ..._jobs.map((j) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: AppColors.greenSoft,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(j['service'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                              Text('${j['customer']} - ${j['date']}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('Rs.${(j['netEarned'] as double).toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.green)),
                              const Text('net earned', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                            ]),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            _earningDetail('Customer Paid', 'Rs.${(j['paid'] as double).toStringAsFixed(0)}', AppColors.teal),
                            Container(width: 1, height: 30, color: AppColors.line),
                            _earningDetail('Platform Fee\n(${(j['commRate'] as double).toStringAsFixed(0)}%)', 'Rs.${(j['commAmt'] as double).toStringAsFixed(0)}', AppColors.red),
                            Container(width: 1, height: 30, color: AppColors.line),
                            _earningDetail('Your Share', 'Rs.${(j['netEarned'] as double).toStringAsFixed(0)}', AppColors.green),
                          ]),
                        ),
                      ]),
                    )).toList(),
                  ],

                  if (_jobs.isEmpty && _withdrawals.isEmpty)
                    Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(height: 40),
                      const Text('Rs.0', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.muted)),
                      const Text('No completed jobs yet', style: TextStyle(fontSize: 15, color: AppColors.muted)),
                      const Text('Complete bookings to start earning!', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    ])),

                  const SizedBox(height: 20),
                ]),
              ),
            ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7), fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _earningDetail(String label, String value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ]),
    );
  }
}
