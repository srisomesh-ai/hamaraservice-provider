import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';
import '../utils/parse.dart';

class RatingsScreen extends StatefulWidget {
  final String providerId;
  const RatingsScreen({super.key, required this.providerId});
  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _reviews = [];
  double _avgRating = 0;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await ProviderApiService.getReviews(widget.providerId);
      double total = 0;
      for (final r in reviews) total += asDouble(r['rating']);
      final avg = reviews.isEmpty ? 0.0 : total / reviews.length;
      if (!mounted) return;
      setState(() { _reviews = reviews; _avgRating = avg; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('My Ratings'), backgroundColor: AppColors.teal),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : _reviews.isEmpty
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('⭐', style: TextStyle(fontSize: 64)),
                  SizedBox(height: 16),
                  Text('No reviews yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.muted)),
                  SizedBox(height: 8),
                  Text('Complete bookings to get reviews', style: TextStyle(color: AppColors.muted)),
                ]))
              : RefreshIndicator(
                  onRefresh: _loadReviews,
                  color: AppColors.teal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      // Rating summary
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D3D47), AppColors.teal],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Column(children: [
                            Text(_avgRating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white)),
                            Row(children: List.generate(5, (i) => Icon(
                              i < _avgRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: AppColors.yellow, size: 28))),
                            const SizedBox(height: 4),
                            Text('${_reviews.length} review${_reviews.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 13, color: Colors.white70)),
                          ]),
                        ]),
                      ),

                      const SizedBox(height: 16),

                      // Reviews list
                      ..._reviews.map((r) {
                        final rating = asInt(r['rating'] ?? r['stars']);
                        final custName = (r['customer_name'] ?? r['customerName'] ?? r['customer'] ?? '').toString();
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
                                radius: 20, backgroundColor: AppColors.tealSoft,
                                child: Text(initialOf(custName, 'C'),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.teal)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(custName.isNotEmpty ? custName : 'Customer',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                                Text((r['svc_name'] ?? r['service'] ?? '').toString(),
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                              ])),
                              Row(children: List.generate(5, (i) => Icon(
                                i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: AppColors.yellow, size: 16))),
                            ]),
                            if ((r['review'] ?? r['comment'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text((r['review'] ?? r['comment'] ?? '').toString(),
                                style: const TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.4)),
                            ],
                            const SizedBox(height: 6),
                            Text(dateOnly(r['created_at'] ?? r['completed_at'] ?? r['createdAt']),
                              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ]),
                        );
                      }).toList(),

                      const SizedBox(height: 20),
                    ]),
                  ),
                ),
    );
  }
}
