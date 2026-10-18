import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

/// Own reviews: reviews.php?action=provider (id omitted → the logged-in provider).
class RatingsScreen extends StatefulWidget {
  final String providerId;
  const RatingsScreen({super.key, required this.providerId});
  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _reviews = [];
  double _avg = 0;

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
      _avg = list.isEmpty ? 0 : total / list.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('My Ratings'), backgroundColor: AppColors.teal),
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
                  if (_reviews.isEmpty && _error.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Column(children: [
                        Icon(Icons.star_outline_rounded, size: 64, color: AppColors.yellow),
                        SizedBox(height: 16),
                        Text('No reviews yet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        SizedBox(height: 8),
                        Text('Complete bookings to get reviews', style: TextStyle(color: AppColors.muted)),
                      ]),
                    ),
                  if (_reviews.isNotEmpty) ...[
                    _summary(),
                    const SizedBox(height: 16),
                    ..._reviews.map(_reviewCard),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _summary() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF0D3D47), AppColors.teal],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [
          Text(_avg.toStringAsFixed(1),
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => Icon(
                i < _avg.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                color: AppColors.yellow, size: 28)),
          ),
          const SizedBox(height: 4),
          Text('${_reviews.length} review${_reviews.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
        ]),
      );

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
