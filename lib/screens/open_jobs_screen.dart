import 'package:flutter/material.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

/// Open jobs list. Data comes from the dashboard's single poller of
/// bookings.php?action=open (already filtered server-side by the provider's
/// services and radius, with customer PII removed).
class OpenJobsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  final bool online;
  final bool approved;
  final bool loading;
  final String error;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic> job) onAccept;
  final Set<String> busyIds;

  const OpenJobsScreen({
    super.key,
    required this.jobs,
    required this.online,
    required this.approved,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onAccept,
    this.busyIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Open Jobs (${jobs.length})'),
        backgroundColor: AppColors.teal,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: loading ? null : onRefresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.teal,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (!approved)
              _note(Icons.hourglass_top_rounded, AppColors.yellow,
                  'Your account is pending approval. Jobs appear once you are approved.')
            else if (!online)
              _note(Icons.wifi_tethering_off_rounded, AppColors.muted,
                  'You are offline. Go online on the Overview tab to get new job alerts.'),
            if (error.isNotEmpty) _note(Icons.error_outline, AppColors.red, error),
            if (loading && jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.teal)),
              )
            else if (jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Column(children: [
                  Icon(Icons.work_off_outlined, size: 56, color: AppColors.muted),
                  SizedBox(height: 12),
                  Text('No open jobs right now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.muted)),
                  SizedBox(height: 6),
                  Text('Pull down to refresh', style: TextStyle(color: AppColors.muted)),
                ]),
              )
            else
              ...jobs.map((j) => _jobCard(j)),
          ],
        ),
      ),
    );
  }

  Widget _note(IconData icon, Color color, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _jobCard(Map<String, dynamic> b) {
    final id = str(b['id']);
    final busy = busyIds.contains(id);
    final est = toInt(b['est_price']);
    final dist = toDoubleOrNull(b['distance_km']);
    final area = [str(b['landmark']), str(b['address']), str(b['city'])]
        .where((s) => s.isNotEmpty).join(', ');
    final summary = parseSummary(b['summary']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        border: Border.all(color: AppColors.green.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(str(b['svc_name'], 'Service'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          if (dist != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.tealSoft, borderRadius: BorderRadius.circular(20)),
              child: Text('${dist.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.teal)),
            ),
        ]),
        const SizedBox(height: 8),
        if (est > 0) _row(Icons.currency_rupee_rounded, 'Customer estimate ₹$est'),
        _row(Icons.calendar_today_rounded,
            slotWhen(b['slot_date'], b['slot_time'])),
        if (area.isNotEmpty) _row(Icons.location_on_rounded, area),
        if (summary.isNotEmpty) _row(Icons.list_alt_rounded, summary.join(' · ')),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: busy || !online ? null : () => onAccept(b),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(online ? 'Accept & Quote' : 'Go online to accept',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: AppColors.teal),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.ink2))),
        ]),
      );
}
