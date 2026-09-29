import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';
import '../utils/parse.dart';
import 'active_booking_screen.dart';
import 'quote_dialog.dart';

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
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  // Jobs this provider has taken that are still in progress
  static const _myActiveStatuses = {
    'price_quoted', 'negotiating', 'negotiation_final', 'accepted', 'confirmed', 'active',
  };

  Future<void> _loadJobs() async {
    try {
      final results = await Future.wait([
        ProviderApiService.getOpenBookings(widget.providerId),
        ProviderApiService.getBookingHistory(widget.providerId)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      final openJobs = results[0];
      final history = results[1];
      final all = <String, dynamic>{for (int i=0; i<openJobs.length; i++) openJobs[i]['id']?.toString() ?? '$i': openJobs[i]};
      // services may be a List of ids, a List of maps (svc_id/svcId/id) or a Map {id: true}
      final providerServiceIds = serviceIdsOf(widget.providerData?['services']);

      List<Map<String, dynamic>> open = [];
      List<Map<String, dynamic>> accepted = [];

      for (final entry in all.entries) {
        final b = Map<String, dynamic>.from(entry.value as Map);
        // Check service match by svc_id or name
        if (providerServiceIds.isNotEmpty) {
          final bSvcId = bookingServiceIdOf(b);
          final bName = (b['svc_name'] ?? b['service'] ?? '').toString().toLowerCase();
          final match = providerServiceIds.contains(bSvcId) ||
              providerServiceIds.any((id) => id.toLowerCase() == bName);
          if (!match) continue;
        }

        if ((b['status'] == 'searching' || b['status'] == 'pending') && b['acceptedBy'] == null) {
          open.add({...b, 'id': entry.key});
        }
      }

      // Recently accepted: this provider's own in-progress jobs from history
      for (final b in history) {
        final st = (b['status'] ?? '').toString();
        if (_myActiveStatuses.contains(st) && (b['id']?.toString() ?? '').isNotEmpty) {
          accepted.add(Map<String, dynamic>.from(b));
        }
      }

      open.sort((a, b) => (b['created_at'] ?? b['createdAt'] ?? '').toString()
          .compareTo((a['created_at'] ?? a['createdAt'] ?? '').toString()));
      String acceptedAt(Map<String, dynamic> m) =>
          (m['accepted_at'] ?? m['updated_at'] ?? m['created_at'] ?? '').toString();
      accepted.sort((a, b) => acceptedAt(b).compareTo(acceptedAt(a)));

      if (!mounted) return;
      setState(() { _openJobs = open; _acceptedJobs = accepted.take(10).toList(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {Color color = AppColors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _acceptJob(Map<String, dynamic> booking) async {
    if (_accepting) return;
    final bookingKey = (booking['id'] ?? '').toString();
    if (bookingKey.isEmpty) return;

    // Provider must be approved and online to take jobs.
    // Use the freshest cached profile (the dashboard refreshes it).
    Map<String, dynamic>? prov = widget.providerData;
    try {
      prov = await ProviderApiService.getCachedProvider() ?? prov;
    } catch (_) {}
    if (!mounted) return;
    if ((prov?['status'] ?? '').toString() != 'approved') {
      _snack('Your account is not approved yet.');
      return;
    }
    final avail = prov?['available'];
    if (!(avail == 1 || avail == true || avail == '1')) {
      _snack('Go online from the Overview tab to accept jobs.');
      return;
    }

    setState(() => _accepting = true);
    try {
      // Check booking is still open
      final bkCheck = await ProviderApiService.getBooking(bookingKey);
      final st = bkCheck?['status']?.toString() ?? '';
      if (bkCheck == null || (st != 'searching' && st != 'pending')) {
        _snack(bkCheck == null
            ? 'This booking is no longer available.'
            : 'This job was accepted by another provider.');
        _loadJobs();
        return;
      }
      if (!mounted) return;

      // Ask for the quote (same dialog as the dashboard alert)
      final price = await showQuoteDialog(context, widget.providerId, booking);
      if (price == null || price <= 0) return;

      final ok = await ProviderApiService.acceptBooking(bookingKey, price);
      if (!ok) {
        final msg = ProviderApiService.lastError;
        _snack(msg == 'Booking not available'
            ? 'This job was accepted by another provider.'
            : (msg.isNotEmpty ? msg : 'Could not accept job. Please try again.'));
        _loadJobs();
        return;
      }

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ActiveBookingScreen(
            bookingKey: bookingKey,
            booking: {...booking, 'status': 'price_quoted', 'quoted_price': price, 'quotedPrice': price},
            providerId: widget.providerId,
          )));
      }
      _loadJobs();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
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
              _filterBtn('accepted', 'Recently Accepted (${_acceptedJobs.length})'),
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

  void _openMyJob(Map<String, dynamic> b) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ActiveBookingScreen(
        bookingKey: (b['id'] ?? '').toString(),
        booking: b,
        providerId: widget.providerId,
      ))).then((_) { if (mounted) _loadJobs(); });
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'price_quoted': return 'Quote Sent';
      case 'negotiating': return 'Negotiating';
      case 'negotiation_final': return 'Final Offer';
      case 'confirmed': return 'Confirmed';
      case 'active': return 'In Progress';
      default: return 'Accepted';
    }
  }

  Widget _jobCard(Map<String, dynamic> b, {required bool canAccept}) {
    // Open jobs show the customer's price hint; own jobs show the agreed/quoted price.
    final shownPrice = canAccept
        ? asInt(b['price'] ?? b['priceVal'])
        : [b['confirmed_price'], b['final_price'], b['quoted_price'], b['price'], b['priceVal']]
            .map((v) => asInt(v))
            .firstWhere((v) => v > 0, orElse: () => 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        border: Border.all(
          color: canAccept ? AppColors.green.withOpacity(0.3) : AppColors.teal.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text((b['svc_name'] ?? b['service'] ?? 'Service').toString(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: AppColors.ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (canAccept ? AppColors.green : AppColors.teal).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Text(
              canAccept ? 'OPEN' : _statusLabel((b['status'] ?? '').toString()),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                color: canAccept ? AppColors.green : AppColors.teal)),
          ),
        ]),
        const SizedBox(height: 8),
        _row(Icons.currency_rupee_rounded, shownPrice > 0
            ? '₹$shownPrice'
            : 'You quote the price'),
        _row(Icons.calendar_today_rounded, '${b['slot_date'] ?? b['date'] ?? ''} at ${b['slot_time'] ?? b['time'] ?? ''}'),
        _row(Icons.location_on_rounded, (b['address'] ?? '').toString()),
        _row(Icons.person_rounded, (b['customer_name'] ?? b['other_party'] ?? b['customer'] ?? '').toString()),

        if (!canAccept) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _openMyJob(b),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 42),
                side: const BorderSide(color: AppColors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('View and Manage',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.teal)),
            ),
          ),
        ],

        if (canAccept) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _accepting ? null : () => _acceptJob(b),
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
