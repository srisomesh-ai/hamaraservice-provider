import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

/// Own reviews: reviews.php?action=provider&id=<own id>.
/// Shows the average (profile `rating`, else computed), a 5★…1★ breakdown
/// and every review (stars, date, customer, service, comment).
class RatingsScreen extends StatefulWidget {
  final String providerId;
  /// Average from the provider profile (0 = unknown → computed from the list).
  final double rating;
  const RatingsScreen({super.key, required this.providerId, this.rating = 0});
  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _reviews = [];
  double _avg = 0;
  final List<int> _counts = List.filled(6, 0); // index 1..5

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    final res = await ProviderApiService.getMyReviews();
    if (!mounted) return;
    if (!res.ok) {
      setState(() { _loading = false; _error = res.unauthorized ? '' : res.error; });
      return;
    }
    final list = res.list;
    final total = list.fold<double>(0, (s, r) => s + toDouble(r['rating']));
    setState(() {
      _reviews = list;
      _counts.fillRange(0, 6, 0);
      for (final r in list) {
        final k = toInt(r['rating']);
        if (k >= 1 && k <= 5) _counts[k]++;
      }
      _avg = widget.rating > 0
          ? widget.rating
          : list.isEmpty ? 0 : total / list.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('My Ratings & Reviews'), backgroundColor: AppColors.teal),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.teal,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(_error,
                          style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                    ),
                  if (_error.isEmpty) ...[
                    _summary(),
                    const SizedBox(height: 16),
                  ],
                  if (_reviews.isEmpty && _error.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Column(children: [
                        Icon(Icons.star_outline_rounded, size: 64, color: AppColors.yellow),
                        SizedBox(height: 16),
                        Text('No reviews yet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        SizedBox(height: 8),
                        Text('Finish jobs and ask customers to rate you.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                      ]),
                    ),
                  ..._reviews.map(_reviewCard),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _summary() {
    final n = _reviews.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0D3D47), AppColors.teal],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        SizedBox(
          width: 104,
          child: Column(children: [
            Text(_avg > 0 ? _avg.toStringAsFixed(1) : '—',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => Icon(
                  i < _avg.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: AppColors.yellow, size: 16)),
            ),
            const SizedBox(height: 4),
            Text('$n review${n == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            for (var st = 5; st >= 1; st--) _bar(st, n),
          ]),
        ),
      ]),
    );
  }

  Widget _bar(int star, int total) {
    final c = _counts[star];
    final frac = total == 0 ? 0.0 : c / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 24,
          child: Text('$star★', style: const TextStyle(fontSize: 11.5, color: Colors.white)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 7,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFF5A623)),
            ),
          ),
        ),
        SizedBox(
          width: 26,
          child: Text('$c', textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final rating = toInt(r['rating']).clamp(0, 5);
    final name = str(r['customer_name'], 'Customer');
    final comment = str(r['comment']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.tealSoft,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.teal)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text(str(r['svc_name']), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
          Row(children: List.generate(5, (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: AppColors.yellow, size: 16))),
        ]),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(comment, style: const TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.4)),
        ],
        const SizedBox(height: 6),
        Text(fmtDate(r['created_at']), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    );
  }
}
