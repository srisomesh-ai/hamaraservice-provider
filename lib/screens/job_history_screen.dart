import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import '../widgets/active_job_card.dart';
import '../widgets/new_job_card.dart';
import '../widgets/ui.dart';
import 'active_booking_screen.dart';

const _engaged = {'price_quoted', 'negotiating', 'negotiation_final', 'confirmed', 'active'};

/// All my bookings (bookings.php?action=history&role=provider) in three tabs.
class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key});
  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    final res = await ProviderApiService.getBookingHistory();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _all = res.list;
      } else if (!res.unauthorized) {
        _error = res.error;
      }
    });
  }

  bool _isOpen(Map<String, dynamic> b) {
    final s = str(b['status']);
    return _engaged.contains(s) || (s == 'completed' && str(b['payment_status']) != 'paid');
  }

  @override
  Widget build(BuildContext context) {
    final open = _all.where(_isOpen).toList();
    final done = _all.where((b) => str(b['status']) == 'completed' && !_isOpen(b)).toList();
    final cancelled = _all.where((b) => str(b['status']) == 'cancelled').toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Job history'),
          bottom: TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(text: 'Active (${open.length})'),
              Tab(text: 'Completed (${done.length})'),
              const Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _list(open, 'No active jobs'),
          _list(done, 'No completed jobs yet'),
          _list(cancelled, 'No cancelled jobs'),
        ]),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> list, String empty) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error.isNotEmpty) Notice(_error, tone: Tone.error, margin: const EdgeInsets.only(bottom: 12)),
          if (_loading && _all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            EmptyState(icon: Icons.receipt_long_outlined, title: empty)
          else
            ...list.map(_tile),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    final st = str(b['status']);
    final amount = bookingAmount(b);
    final when = slotWhen(b['slot_date'], b['slot_time']);
    final dur = istDuration(b['started_at'], b['completed_at']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: st == 'cancelled'
              ? null
              : () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ActiveBookingScreen(bookingId: str(b['id']), initial: b)));
                  if (mounted) _load();
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(jobIcon(b), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Text(str(b['svc_name'], 'Service'), style: t.titleSmall)),
                StatusBadge(st, paymentStatus: str(b['payment_status'])),
              ]),
              const SizedBox(height: 8),
              if (str(b['other_party']).isNotEmpty) DetailLine(Icons.person_outline_rounded, str(b['other_party'])),
              if (when.isNotEmpty) DetailLine(Icons.schedule_rounded, when),
              if (str(b['address']).isNotEmpty) DetailLine(Icons.place_outlined, str(b['address']), maxLines: 2),
              if (dur.isNotEmpty) DetailLine(Icons.timer_outlined, 'Worked $dur'),
              if (st == 'cancelled' && str(b['cancel_reason']).isNotEmpty)
                DetailLine(Icons.info_outline_rounded, str(b['cancel_reason'])),
              const SizedBox(height: 6),
              Row(children: [
                Text(amount > 0 ? '₹$amount' : '—',
                    style: t.titleMedium?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (st == 'completed' && toInt(b['provider_earns']) > 0)
                  Text('You earned ₹${toInt(b['provider_earns'])}',
                      style: t.bodyMedium?.copyWith(color: AppColors.green, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
