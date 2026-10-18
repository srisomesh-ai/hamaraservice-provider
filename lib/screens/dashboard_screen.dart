import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import '../widgets/accept_job.dart';
import 'active_booking_screen.dart';
import 'earnings_screen.dart';
import 'login_screen.dart';
import 'open_jobs_screen.dart';
import 'profile_edit_screen.dart';
import 'ratings_screen.dart';
import 'services_screen.dart';
import 'support_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String providerId;
  final int initialTab;
  const DashboardScreen({super.key, required this.providerId, this.initialTab = 0});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Booking statuses in which the provider is engaged with a customer.
const _engagedStatuses = {
  'price_quoted', 'negotiating', 'negotiation_final', 'confirmed', 'active',
};

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late int _tab = widget.initialTab;
  bool _loading = true;
  bool _available = false;
  bool _toggling = false;
  bool _foreground = true;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _balance;

  // Job discovery (ONE poller)
  Timer? _jobsTimer;
  bool _jobsFetching = false;
  List<Map<String, dynamic>> _openJobs = [];
  String _openError = '';
  final Set<String> _dismissed = {};
  final Set<String> _acceptingIds = {};

  // Incoming popup
  Map<String, dynamic>? _incoming;
  Timer? _countdownTimer;
  int _countdown = 30;
  final _audio = AudioPlayer();

  // Current job
  Timer? _activeTimer;
  Map<String, dynamic>? _active;

  // History
  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = false;
  String _historyError = '';

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  String get _pid => widget.providerId;
  bool get _approved => str(_profile?['status'], 'pending') == 'approved';
  bool get _engaged => _active != null && _engagedStatuses.contains(str(_active!['status']));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _audio.setReleaseMode(ReleaseMode.loop);
    _init();
  }

  Future<void> _init() async {
    final cached = await ProviderApiService.getCachedProvider();
    if (cached != null && mounted) {
      setState(() {
        _profile = cached;
        _available = toBool(cached['available']);
        _loading = false;
      });
    }
    await _refreshAll();
    if (!mounted) return;
    setState(() => _loading = false);
    NotificationService.registerToken();
    NotificationService.appReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => NotificationService.consumePending());
    _startActivePolling();
    if (_tab == 1) _loadHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _jobsTimer?.cancel();
    _activeTimer?.cancel();
    _countdownTimer?.cancel();
    _stopAlert();
    _audio.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      _refreshAll();
      _startActivePolling();
    } else {
      _jobsTimer?.cancel();
      _jobsTimer = null;
      _activeTimer?.cancel();
      _activeTimer = null;
      _stopAlert();
    }
    _syncJobPoller();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadProfile(), _loadActive(), _loadBalance()]);
    _syncJobPoller();
  }

  Future<void> _loadProfile() async {
    final res = await ProviderApiService.getMyProfile();
    if (!mounted || !res.ok) return;
    final p = res.map!;
    setState(() {
      _profile = p;
      if (!_toggling) _available = toBool(p['available']);
    });
    LocationService.instance.online = _available && _approved;
  }

  Future<void> _loadBalance() async {
    final res = await ProviderApiService.getBalance();
    if (mounted && res.ok) setState(() => _balance = res.map);
  }

  // ── Current job ─────────────────────────────────────────────
  void _startActivePolling() {
    _activeTimer?.cancel();
    _activeTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadActive());
  }

  Future<void> _loadActive() async {
    final res = await ProviderApiService.getActiveBooking();
    if (!mounted || !res.ok) return;
    setState(() => _active = res.map);
    LocationService.instance.onJob = _active != null &&
        ['confirmed', 'active'].contains(str(_active!['status']));
  }

  Future<void> _openBooking(String id, {Map<String, dynamic>? initial}) async {
    if (id.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ActiveBookingScreen(bookingId: id, initial: initial)));
    if (!mounted) return;
    _loadActive();
    _loadBalance();
    if (_tab == 1) _loadHistory();
  }

  // ── Job discovery: single poller ────────────────────────────
  void _syncJobPoller() {
    final shouldRun = _available && _approved && _foreground;
    if (!shouldRun) {
      _jobsTimer?.cancel();
      _jobsTimer = null;
      if (_incoming != null) _closeIncoming(dismiss: false);
      return;
    }
    if (_jobsTimer != null) return;
    _fetchOpenJobs();
    _jobsTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchOpenJobs());
  }

  Future<void> _fetchOpenJobs() async {
    if (_jobsFetching) return;
    _jobsFetching = true;
    try {
      final res = await ProviderApiService.getOpenBookings();
      if (!mounted) return;
      if (!res.ok) {
        if (!res.unauthorized) setState(() => _openError = res.error);
        if (res.status == 403) {
          // Not approved / suspended: stop polling and reflect it.
          _jobsTimer?.cancel();
          _jobsTimer = null;
          setState(() => _available = false);
          LocationService.instance.online = false;
        }
        return;
      }
      final jobs = res.list;
      setState(() {
        _openJobs = jobs;
        _openError = '';
      });
      _maybeShowIncoming(jobs);
    } finally {
      _jobsFetching = false;
    }
  }

  void _maybeShowIncoming(List<Map<String, dynamic>> jobs) {
    final ids = jobs.map((j) => str(j['id'])).toSet();
    // Popup job disappeared (taken by someone else / cancelled)
    if (_incoming != null && !ids.contains(str(_incoming!['id']))) {
      if (!_acceptingIds.contains(str(_incoming!['id']))) {
        _closeIncoming(dismiss: true);
        _snack('That job is no longer available.', AppColors.muted);
      }
      return;
    }
    if (_incoming != null || _engaged || !_available) return;
    // Don't ring while another screen (booking, earnings…) is on top.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    for (final j in jobs) {
      final id = str(j['id']);
      if (id.isEmpty || _dismissed.contains(id)) continue;
      setState(() {
        _incoming = j;
        _countdown = 30;
      });
      _startAlert();
      break;
    }
  }

  void _startAlert() {
    try {
      Vibration.vibrate(pattern: [0, 600, 200, 600, 200, 600], repeat: 0);
    } catch (_) {}
    _audio.play(AssetSource('sounds/alert.mp3')).catchError((_) {});
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 1) {
        t.cancel();
        _closeIncoming(dismiss: true); // expired → never show again
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _stopAlert() {
    try { Vibration.cancel(); } catch (_) {}
    try { _audio.stop(); } catch (_) {}
  }

  void _closeIncoming({required bool dismiss}) {
    _countdownTimer?.cancel();
    _stopAlert();
    final id = str(_incoming?['id']);
    if (dismiss && id.isNotEmpty) _dismissed.add(id);
    if (mounted) setState(() => _incoming = null);
  }

  Future<void> _accept(Map<String, dynamic> job) async {
    final id = str(job['id']);
    if (id.isEmpty || _acceptingIds.contains(id)) return;
    if (_incoming != null && str(_incoming!['id']) == id) {
      _countdownTimer?.cancel();
      _stopAlert();
    }
    setState(() => _acceptingIds.add(id));
    final ok = await acceptJobWithQuote(context, job, _profile);
    if (!mounted) return;
    setState(() => _acceptingIds.remove(id));
    if (_incoming != null && str(_incoming!['id']) == id) _closeIncoming(dismiss: true);
    if (!ok) {
      _fetchOpenJobs();
      return;
    }
    _dismissed.add(id);
    setState(() => _openJobs.removeWhere((j) => str(j['id']) == id));
    await _loadActive();
    if (!mounted) return;
    _openBooking(id);
  }

  // ── Online / offline ────────────────────────────────────────
  Future<void> _toggleAvailability(bool val) async {
    if (_toggling) return;
    if (val && !_approved) {
      _snack('Your account is not approved yet.', AppColors.red);
      return;
    }
    setState(() => _toggling = true);
    if (val) {
      final pos = await LocationService.currentPosition(ask: true);
      if (pos != null) {
        await ProviderApiService.sendLocation(pos.latitude, pos.longitude);
      } else if (mounted) {
        _snack('Location unavailable — jobs will be matched by your saved area. '
            'Enable location for better matches.', AppColors.yellow);
      }
    }
    final res = await ProviderApiService.setAvailable(val);
    if (!mounted) return;
    setState(() => _toggling = false);
    if (!res.ok) {
      if (!res.unauthorized) {
        _snack(res.status == 403 ? (res.error.isNotEmpty ? res.error : 'Account not approved yet')
            : res.error, AppColors.red);
      }
      return;
    }
    setState(() => _available = val);
    LocationService.instance.online = val;
    if (!val) {
      _closeIncoming(dismiss: false);
      setState(() => _openJobs = []);
    }
    _syncJobPoller();
  }

  Future<void> _logout() async {
    _jobsTimer?.cancel();
    _activeTimer?.cancel();
    _closeIncoming(dismiss: false);
    LocationService.instance.stopAll();
    NotificationService.appReady = false;
    await ProviderApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  // ── History ────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    setState(() { _historyLoading = true; _historyError = ''; });
    final res = await ProviderApiService.getBookingHistory();
    if (!mounted) return;
    setState(() {
      _historyLoading = false;
      if (res.ok) {
        _history = res.list;
      } else if (!res.unauthorized) {
        _historyError = res.error;
      }
    });
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) {
          setState(() => _tab = i);
          if (i == 1) _loadHistory();
          if (i == 2 && _approved) _fetchOpenJobs();
        },
        selectedItemColor: AppColors.teal,
        unselectedItemColor: AppColors.muted,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
          const BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Bookings'),
          BottomNavigationBarItem(
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.work_outline_rounded),
              if (_openJobs.isNotEmpty)
                Positioned(
                  right: -2, top: -2,
                  child: Container(
                    width: 9, height: 9,
                    decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                  ),
                ),
            ]),
            label: 'Open Jobs',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
      body: _loading && _profile == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : Stack(children: [
              IndexedStack(index: _tab, children: [
                _buildOverview(),
                _buildBookings(),
                OpenJobsScreen(
                  jobs: _openJobs,
                  online: _available,
                  approved: _approved,
                  loading: _jobsFetching,
                  error: _openError,
                  busyIds: _acceptingIds,
                  onRefresh: () async {
                    if (_approved) await _fetchOpenJobs();
                  },
                  onAccept: _accept,
                ),
                _buildProfile(),
              ]),
              if (_incoming != null) _buildIncomingAlert(),
            ]),
    );
  }

  // ── OVERVIEW ───────────────────────────────────────────────
  Widget _buildOverview() {
    final name = str(_profile?['name'], 'Provider');
    final photo = photoUrl(_profile?['photo']);
    final available = toInt(_balance?['available']);
    final due = toInt(_balance?['commission_due']);
    final rating = toDouble(_profile?['rating']);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: AppColors.teal,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 150,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.teal,
            actions: [
              IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF0A2E36), AppColors.teal],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 60, 16),
                    child: Row(children: [
                      _avatar(name, photo, 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                            Text(str(_profile?['email']), style: const TextStyle(fontSize: 11, color: Colors.white60)),
                            const SizedBox(height: 4),
                            _statusPill(),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (!_approved) ...[
                  _notice(Icons.info_outline_rounded, AppColors.yellow,
                      'Your account is ${str(_profile?['status'], 'pending')}. You can go online once approved.'),
                  const SizedBox(height: 12),
                ],
                if (due > 0) ...[
                  _duesCard(due),
                  const SizedBox(height: 12),
                ],
                if (_active != null) ...[
                  _currentJobCard(_active!),
                  const SizedBox(height: 12),
                ],
                _availabilityCard(),
                const SizedBox(height: 12),
                _earningsCard(available),
                const SizedBox(height: 12),
                Row(children: [
                  _statTile('Jobs Done', '${toInt(_profile?['completed_bookings'])}', Icons.work_rounded, AppColors.teal),
                  const SizedBox(width: 10),
                  _statTile('Rating', rating > 0 ? rating.toStringAsFixed(1) : '–', Icons.star_rounded, AppColors.yellow),
                  const SizedBox(width: 10),
                  _statTile('Reviews', '${toInt(_profile?['review_count'])}', Icons.reviews_rounded, AppColors.brand),
                ]),
                if (_available && _openJobs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _tapCard(Icons.notifications_active_rounded, AppColors.brand,
                      '${_openJobs.length} open job${_openJobs.length == 1 ? '' : 's'} near you',
                      'Tap to view', () => setState(() => _tab = 2)),
                ],
                const SizedBox(height: 12),
                _tapCard(Icons.miscellaneous_services_rounded, const Color(0xFF8B5CF6),
                    'My Services', 'Choose services and set your prices', () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ServicesScreen(providerId: _pid)));
                  if (r == true) _loadProfile();
                }),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final approved = _approved;
    final color = approved ? AppColors.green : AppColors.yellow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(approved ? 'Approved' : str(_profile?['status'], 'pending').toUpperCase(),
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _duesCard(int due) => GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => EarningsScreen(providerId: _pid))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.red.withOpacity(0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Commission due: ₹$due',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.red)),
                const Text('Pay dues to keep receiving jobs',
                    style: TextStyle(fontSize: 12, color: AppColors.ink2)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.red),
          ]),
        ),
      );

  Widget _currentJobCard(Map<String, dynamic> b) {
    final status = str(b['status']);
    final unpaid = status == 'completed' && str(b['payment_status']) != 'paid';
    final label = unpaid ? 'Awaiting payment' : _statusLabel(status);
    return ScaleTransition(
      scale: _pulseAnim,
      child: GestureDetector(
        onTap: () => _openBooking(str(b['id']), initial: b),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.brand, Color(0xFFF59E0B)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            const Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CURRENT JOB',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 1)),
                Text(str(b['svc_name'], 'Service'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
              ]),
            ),
            const Text('Open', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }

  Widget _availabilityCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _available ? AppColors.green.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _available ? AppColors.green.withOpacity(0.4) : AppColors.line),
      ),
      child: Row(children: [
        Icon(_available ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
            color: _available ? AppColors.green : AppColors.muted, size: 26),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_available ? 'You are Online' : 'You are Offline',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: _available ? AppColors.green : AppColors.ink)),
            Text(_available ? 'Receiving job alerts while the app is open'
                    : 'Go online to receive job alerts',
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        ),
        _toggling
            ? const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
            : Switch(
                value: _available,
                onChanged: _approved ? _toggleAvailability : null,
                activeColor: AppColors.green),
      ]),
    );
  }

  Widget _earningsCard(int available) => GestureDetector(
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => EarningsScreen(providerId: _pid)));
          _loadBalance();
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF388E3C)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Available Balance',
                    style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
                Text('₹$available',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                Text('Total earned ₹${toInt(_balance?['total_earned'] ?? _profile?['total_earned'])} · Tap for details',
                    style: const TextStyle(fontSize: 11, color: Colors.white60)),
              ]),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ]),
        ),
      );

  // ── BOOKINGS (history) ─────────────────────────────────────
  Widget _buildBookings() {
    bool isOpen(Map<String, dynamic> b) {
      final s = str(b['status']);
      return _engagedStatuses.contains(s) ||
          (s == 'completed' && str(b['payment_status']) != 'paid');
    }
    final open = _history.where(isOpen).toList();
    final done = _history.where((b) => str(b['status']) == 'completed' && !isOpen(b)).toList();
    final cancelled = _history.where((b) => str(b['status']) == 'cancelled').toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings'),
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.teal,
          bottom: TabBar(
            indicatorColor: AppColors.brand,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Active (${open.length})'),
              Tab(text: 'Completed (${done.length})'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _bookingList(open, 'No active bookings'),
          _bookingList(done, 'No completed bookings yet'),
          _bookingList(cancelled, 'No cancelled bookings'),
        ]),
      ),
    );
  }

  Widget _bookingList(List<Map<String, dynamic>> list, String emptyMsg) {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppColors.teal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_historyError.isNotEmpty) _notice(Icons.error_outline, AppColors.red, _historyError),
          if (_historyLoading && _history.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator(color: AppColors.teal)),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(children: [
                const Icon(Icons.receipt_long_rounded, size: 56, color: AppColors.muted),
                const SizedBox(height: 12),
                Text(emptyMsg, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.muted)),
              ]),
            )
          else
            ...list.map(_bookingCard),
        ],
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final status = str(b['status']);
    final paid = str(b['payment_status']) == 'paid';
    final color = _statusColor(status, paid);
    final price = toInt(b['amount']) > 0
        ? toInt(b['amount'])
        : toInt(b['confirmed_price']) > 0 ? toInt(b['confirmed_price']) : toInt(b['quoted_price']);
    final label = status == 'completed' ? (paid ? 'Paid' : 'Awaiting payment') : _statusLabel(status);
    return GestureDetector(
      onTap: status == 'cancelled' ? null : () => _openBooking(str(b['id']), initial: b),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(str(b['svc_name'], 'Service'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
          const SizedBox(height: 6),
          if (str(b['other_party']).isNotEmpty)
            _line(Icons.person_rounded, str(b['other_party'])),
          _line(Icons.calendar_today_rounded,
              '${fmtDate(b['slot_date'])} ${str(b['slot_time'])}${price > 0 ? ' · ₹$price' : ''}'),
          if (str(b['address']).isNotEmpty) _line(Icons.location_on_rounded, str(b['address'])),
          if (status == 'completed' && toInt(b['provider_earns']) > 0)
            _line(Icons.account_balance_wallet_rounded, 'You earned ₹${toInt(b['provider_earns'])}'),
          if (status == 'cancelled' && str(b['cancel_reason']).isNotEmpty)
            _line(Icons.info_outline_rounded, str(b['cancel_reason'])),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.ink2))),
        ]),
      );

  // ── PROFILE ────────────────────────────────────────────────
  Widget _buildProfile() {
    final name = str(_profile?['name'], 'Provider');
    final photo = photoUrl(_profile?['photo']);
    final rating = toDouble(_profile?['rating']);
    return CustomScrollView(slivers: [
      SliverAppBar(
        expandedHeight: 200,
        pinned: true,
        backgroundColor: AppColors.teal,
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout)],
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0A2E36), AppColors.teal],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: SafeArea(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _avatar(name, photo, 44),
                const SizedBox(height: 8),
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                Text(str(_profile?['email']), style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _statusPill(),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProfileEditScreen(providerId: _pid, providerData: _profile)));
                  if (r == true) _loadProfile();
                },
                icon: const Icon(Icons.edit_rounded, size: 14, color: AppColors.teal),
                label: const Text('Edit', style: TextStyle(color: AppColors.teal, fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.teal),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _statTile('Jobs Done', '${toInt(_profile?['completed_bookings'])}', Icons.work_rounded, AppColors.teal),
              const SizedBox(width: 10),
              _statTile('Rating', rating > 0 ? rating.toStringAsFixed(1) : '–', Icons.star_rounded, AppColors.yellow),
              const SizedBox(width: 10),
              _statTile('Earned', '₹${toInt(_profile?['total_earned'])}', Icons.currency_rupee_rounded, AppColors.green),
            ]),
            const SizedBox(height: 16),
            _infoCard(Icons.phone_rounded, 'Phone', str(_profile?['phone'], 'Not set')),
            const SizedBox(height: 10),
            _infoCard(Icons.location_city_rounded, 'City', str(_profile?['city'], 'Not set')),
            const SizedBox(height: 10),
            _infoCard(Icons.radar_rounded, 'Service radius', '${toInt(_profile?['radius_km'], 10)} km'),
            const SizedBox(height: 10),
            _infoCard(Icons.work_history_rounded, 'Experience', str(_profile?['experience'], 'Not set')),
            const SizedBox(height: 10),
            _infoCard(Icons.badge_rounded, 'Provider ID', _pid),
            const SizedBox(height: 16),
            _menuTile('Earnings and Withdrawals', Icons.account_balance_wallet_rounded, AppColors.green,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => EarningsScreen(providerId: _pid)))),
            const SizedBox(height: 10),
            _menuTile('My Ratings and Reviews', Icons.star_rounded, AppColors.yellow,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => RatingsScreen(providerId: _pid)))),
            const SizedBox(height: 10),
            _menuTile('My Services', Icons.build_rounded, AppColors.teal, () async {
              final r = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ServicesScreen(providerId: _pid)));
              if (r == true) _loadProfile();
            }),
            const SizedBox(height: 10),
            _menuTile('Help and Support', Icons.headset_mic_rounded, AppColors.muted,
                () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SupportScreen(
                        providerName: str(_profile?['name']),
                        providerEmail: str(_profile?['email']),
                        providerId: _pid)))),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: AppColors.red, size: 18),
              label: const Text('Sign Out',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 15)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: AppColors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    ]);
  }

  // ── INCOMING ALERT ─────────────────────────────────────────
  Widget _buildIncomingAlert() {
    final bk = _incoming!;
    final id = str(bk['id']);
    final busy = _acceptingIds.contains(id);
    final est = toInt(bk['est_price']);
    final dist = toDoubleOrNull(bk['distance_km']);
    final area = [str(bk['landmark']), str(bk['address']), str(bk['city'])]
        .where((s) => s.isNotEmpty).join(', ');
    final summary = parseSummary(bk['summary']);
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0A2E36), AppColors.teal]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(children: [
                  const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('New Job Alert!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text('Send your quote before it expires',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ]),
                  ),
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _countdown <= 10 ? Colors.red.withOpacity(0.85) : AppColors.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text('$_countdown',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        _alertRow(Icons.home_repair_service_rounded, 'Service', str(bk['svc_name'], 'Service'), AppColors.teal),
                        if (est > 0) ...[
                          const Divider(height: 16, color: AppColors.line),
                          _alertRow(Icons.currency_rupee_rounded, 'Price', 'Customer estimate ₹$est', AppColors.green),
                        ],
                        const Divider(height: 16, color: AppColors.line),
                        _alertRow(Icons.calendar_today_rounded, 'When',
                            '${fmtDate(bk['slot_date'])}${str(bk['slot_time']).isNotEmpty ? ' at ${str(bk['slot_time'])}' : ''}',
                            AppColors.brand),
                        if (area.isNotEmpty) ...[
                          const Divider(height: 16, color: AppColors.line),
                          _alertRow(Icons.location_on_rounded, 'Area', area, AppColors.red),
                        ],
                        if (dist != null) ...[
                          const Divider(height: 16, color: AppColors.line),
                          _alertRow(Icons.near_me_rounded, 'Distance', '${dist.toStringAsFixed(1)} km away', AppColors.muted),
                        ],
                      ]),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6, runSpacing: 6,
                        children: summary.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.tealSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                          ),
                          child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => _closeIncoming(dismiss: true),
                          icon: const Icon(Icons.close, color: AppColors.red, size: 18),
                          label: const Text('Decline',
                              style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            side: const BorderSide(color: AppColors.red),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: busy ? null : () => _accept(bk),
                          icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                          label: const Text('Accept',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────
  Widget _avatar(String name, String photo, double r) => CircleAvatar(
        radius: r,
        backgroundColor: AppColors.brand,
        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
        child: photo.isEmpty
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: TextStyle(fontSize: r * 0.75, color: Colors.white, fontWeight: FontWeight.w800))
            : null,
      );

  Widget _notice(IconData icon, Color color, String text) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
        ]),
      );

  Widget _tapCard(IconData icon, Color color, String title, String sub, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ]),
        ),
      );

  Widget _statTile(String label, String value, IconData icon, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _infoCard(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.teal, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
            ]),
          ),
        ]),
      );

  Widget _menuTile(String label, IconData icon, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14))),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      );

  Widget _alertRow(IconData icon, String label, String value, Color color) => Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ]),
        ),
      ]);

  Color _statusColor(String s, bool paid) {
    switch (s) {
      case 'price_quoted':
      case 'negotiating':
      case 'negotiation_final':
        return AppColors.yellow;
      case 'confirmed':
        return AppColors.teal;
      case 'active':
        return AppColors.brand;
      case 'completed':
        return paid ? AppColors.green : AppColors.yellow;
      case 'cancelled':
        return AppColors.red;
      default:
        return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'searching': return 'Searching';
      case 'price_quoted': return 'Quote sent';
      case 'negotiating': return 'Customer negotiating';
      case 'negotiation_final': return 'Final offer sent';
      case 'confirmed': return 'Confirmed';
      case 'active': return 'In progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return s;
    }
  }
}
