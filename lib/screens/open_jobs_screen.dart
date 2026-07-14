import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';
import 'active_booking_screen.dart';

class OpenJobsScreen extends StatefulWidget {
  final String providerId;
  final Map<String, dynamic>? providerData;
  const OpenJobsScreen({super.key, required this.providerId, this.providerData});
  @override
  State<OpenJobsScreen> createState() => _OpenJobsScreenState();
}

class _OpenJobsScreenState extends State<OpenJobsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _openJobs = [];
  List<Map<String, dynamic>> _acceptedJobs = [];
  String _filter = 'open';

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    try {
      final openJobs = await ProviderApiService.getOpenBookings(widget.providerId);
      final all = <String, dynamic>{for (int i=0; i<openJobs.length; i++) openJobs[i]['id']?.toString() ?? '$i': openJobs[i]};
      // Handle services as Map {SVC001:true} or List format
    final rawSvcs = widget.providerData?['services'];
    final providerServiceIds = <String>{};
    if (rawSvcs is Map) {
      rawSvcs.forEach((k,v){ if(v==true) providerServiceIds.add(k.toString()); });
    } else if (rawSvcs is List) {
      for (final s in rawSvcs) { providerServiceIds.add(s.toString()); }
    }

      List<Map<String, dynamic>> open = [];
      List<Map<String, dynamic>> accepted = [];

      for (final entry in all.entries) {
        final b = Map<String, dynamic>.from(entry.value as Map);
        // Check service match by svcId or name
        if (providerServiceIds.isNotEmpty) {
          final bSvcId = b['svcId']?.toString() ?? '';
          final bName = (b['service'] ?? '').toString().toLowerCase();
          final match = providerServiceIds.contains(bSvcId) ||
              providerServiceIds.any((id) => id.toLowerCase() == bName);
          if (!match) continue;
        }

        if ((b['status'] == 'searching' || b['status'] == 'pending') && b['acceptedBy'] == null) {
          open.add({...b, 'id': entry.key});
        } else if (b['status'] == 'accepted' && b['acceptedBy'] != null) {
          // Recently accepted jobs
          accepted.add({...b, 'id': entry.key});
        }
      }

      open.sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      accepted.sort((a, b) => (b['acceptedAt'] ?? '').compareTo(a['acceptedAt'] ?? ''));

      setState(() { _openJobs = open; _acceptedJobs = accepted.take(10).toList(); _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _acceptJob(Map<String, dynamic> booking) async {
    final bookingKey = booking['id'] as String;

    // Check booking still available via MySQL
    final bkCheck = await ProviderApiService.getBooking(bookingKey);
    if (bkCheck == null || bkCheck['status'] != 'active') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This booking is no longer available.'), backgroundColor: AppColors.red));
      _loadJobs();
      return;
    }

    final current = Map<String, dynamic>.from(snap.value as Map);
    if (current['acceptedBy'] != null || (current['status'] != 'searching' && current['status'] != 'pending')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This job was accepted by another provider.'), backgroundColor: AppColors.red));
      _loadJobs();
      return;
    }

    final providerInfo = {
      'id': widget.providerId,
      'name': widget.providerData?['name'] ?? '',
      'phone': widget.providerData?['phone'] ?? '',
    };

    // Accept + quote price via MySQL API
    await ProviderApiService.acceptBooking(bookingKey, quotedPrice);

    if (mounted) Navigator.push(context, MaterialPageRoute(
      builder: (_) => ActiveBookingScreen(
        bookingKey: bookingKey,
        booking: booking,
        providerId: widget.providerId,
      )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Open Jobs'),
        backgroundColor: AppColors.teal,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadJobs),
        ],
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            color: AppColors.teal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              _filterBtn('open', 'Open (${_openJobs.length})'),
              const SizedBox(width: 8),
              _filterBtn('accepted', 'Recently Accepted'),
            ]),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
                : RefreshIndicator(
                    onRefresh: _loadJobs,
                    color: AppColors.teal,
                    child: _filter == 'open' ? _buildOpenList() : _buildAcceptedList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterBtn(String key, String label) {
    final sel = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppColors.brand : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: sel ? Colors.white : Colors.white70)),
      ),
    );
  }

  Widget _buildOpenList() {
    if (_openJobs.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('📋', style: TextStyle(fontSize: 48)),
        SizedBox(height: 12),
        Text('No open jobs right now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.muted)),
        SizedBox(height: 8),
        Text('Check back later for new bookings', style: TextStyle(color: AppColors.muted)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _openJobs.length,
      itemBuilder: (_, i) => _jobCard(_openJobs[i], canAccept: true),
    );
  }

  Widget _buildAcceptedList() {
    if (_acceptedJobs.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('✅', style: TextStyle(fontSize: 48)),
        SizedBox(height: 12),
        Text('No recently accepted jobs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _acceptedJobs.length,
      itemBuilder: (_, i) => _jobCard(_acceptedJobs[i], canAccept: false),
    );
  }

  Widget _jobCard(Map<String, dynamic> b, {required bool canAccept}) {
    final acceptedBy = b['acceptedBy'];
    final isAcceptedByOther = !canAccept && acceptedBy != null &&
        (acceptedBy is Map) && acceptedBy['id'] != widget.providerId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        border: Border.all(
          color: isAcceptedByOther ? AppColors.muted.withOpacity(0.3) :
                 canAccept ? AppColors.green.withOpacity(0.3) : AppColors.teal.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(b['service'] ?? 'Service',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: isAcceptedByOther ? AppColors.muted : AppColors.ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isAcceptedByOther ? AppColors.muted : canAccept ? AppColors.green : AppColors.teal).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Text(
              isAcceptedByOther ? 'Accepted by other' : canAccept ? 'OPEN' : 'Accepted',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                color: isAcceptedByOther ? AppColors.muted : canAccept ? AppColors.green : AppColors.teal)),
          ),
        ]),
        const SizedBox(height: 8),
        _row(Icons.currency_rupee_rounded, '₹${b['price'] ?? b['priceVal'] ?? 0}'),
        _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
        _row(Icons.location_on_rounded, b['address'] ?? ''),
        _row(Icons.person_rounded, '${b['customer'] ?? ''} · ${b['phone'] ?? ''}'),

        if (canAccept) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _acceptJob(b),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Accept Job',
                style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: AppColors.teal),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.ink2))),
      ]),
    );
  }
}
