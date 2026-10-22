import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/support_contact.dart';
import '../utils/theme.dart';
import '../widgets/accept_job.dart';
import '../widgets/active_job_card.dart';
import '../widgets/new_job_card.dart';
import '../widgets/ui.dart';
import 'active_booking_screen.dart';
import 'earnings_screen.dart';
import 'login_screen.dart';
import 'profile_tab.dart';
import 'ratings_screen.dart';
import 'services_screen.dart';

/// Home shell shown after login: a Material 3 [NavigationBar] with four tabs
/// (Jobs · Earnings · Services · Profile) kept alive in an [IndexedStack].
/// The shell owns job discovery (one poller), the new-job alert and the
/// current-job poll, exactly like the website dashboard.
class DashboardScreen extends StatefulWidget {
  final String providerId;
  final int initialTab;

  // ── Test-only sample data (screenshots). When [debugProfile] is set the
  // shell never touches the network, plugins or timers.
  final Map<String, dynamic>? debugProfile;
  final Map<String, dynamic>? debugActive;
  final List<Map<String, dynamic>>? debugOpenJobs;
  final Map<String, dynamic>? debugIncoming;
  final Map<String, dynamic>? debugBalance;
  final EarningsDemo? debugEarnings;
  final ServicesDemo? debugServices;

  const DashboardScreen({
    super.key,
    required this.providerId,
    this.initialTab = 0,
    this.debugProfile,
    this.debugActive,
    this.debugOpenJobs,
    this.debugIncoming,
    this.debugBalance,
    this.debugEarnings,
    this.debugServices,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

const int _alertSeconds = 30;

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late int _tab = widget.initialTab.clamp(0, 3);
  final Set<int> _visited = {};
  int _earningsTick = 0;
  int _servicesTick = 0;

  bool _loading = true;
  bool _available = false;
  bool _toggling = false;
  bool _foreground = true;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _balance;
  Timer? _profileTimer; // rating / earnings stay current (every 60 s)

  // "My saved price" sources (same as the website)
  Map<String, dynamic> _optionPrices = {};
  Map<String, dynamic> _adminRanges = {};

  // Job discovery (ONE poller, every 4 s like the website)
  Timer? _jobsTimer;
  bool _jobsFetching = false;
  List<Map<String, dynamic>> _openJobs = [];
  String _openError = '';
  final Map<String, DateTime> _shownAt = {}; // re-alert after 45 s (web)
  final Set<String> _acceptingIds = {};

  // New-job alert
  Map<String, dynamic>? _incoming;
  Timer? _countdownTimer;
  int _countdown = _alertSeconds;
  int _incomingSaved = 0;
  final _priceCtrl = TextEditingController();
  AudioPlayer? _audio;

  // Current job (polled every 4 s like the website)
  Timer? _activeTimer;
  Map<String, dynamic>? _active;
  String? _lastStatus;
  String? _lastPay;
  DateTime? _quoteDeadline;
  Timer? _quoteTick;

  bool get _demo => widget.debugProfile != null;
  String get _pid => widget.providerId;
  bool get _approved => str(_profile?['status'], 'pending') == 'approved';

  @override
  void initState() {
    super.initState();
    _visited.add(_tab);
    if (_demo) {
      _profile = widget.debugProfile;
      _available = toBool(_profile?['available']);
      _active = widget.debugActive;
      _openJobs = widget.debugOpenJobs ?? [];
      _balance = widget.debugBalance;
      _loading = false;
      if (_active != null) _setQuoteDeadline(_active!);
      final inc = widget.debugIncoming;
      if (inc != null) {
        _incoming = inc;
        _incomingSaved = _savedPrice(inc);
        _priceCtrl.text = _incomingSaved > 0 ? '$_incomingSaved' : '';
      }
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _audio = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
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
    _startProfilePolling();
    loadSupportConfig();
    _loadPriceSources();
  }

  @override
  void dispose() {
    if (!_demo) WidgetsBinding.instance.removeObserver(this);
    _jobsTimer?.cancel();
    _activeTimer?.cancel();
    _profileTimer?.cancel();
    _countdownTimer?.cancel();
    _quoteTick?.cancel();
    _stopAlert();
    _audio?.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      NotificationService.clearAlerts();
      _refreshAll();
      _startActivePolling();
      _startProfilePolling();
    } else {
      _jobsTimer?.cancel();
      _jobsTimer = null;
      _activeTimer?.cancel();
      _activeTimer = null;
      _profileTimer?.cancel();
      _profileTimer = null;
      _stopAlert();
    }
    _syncJobPoller();
  }

  Future<void> _refreshAll() async {
    if (_demo) return;
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

  void _startProfilePolling() {
    _profileTimer?.cancel();
    _profileTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadProfile();
      _loadBalance();
    });
  }

  Future<void> _loadBalance() async {
    final res = await ProviderApiService.getBalance();
    if (mounted && res.ok) setState(() => _balance = res.map);
  }

  /// Saved option prices + admin defaults → prefill of "Your Price (₹)".
  Future<void> _loadPriceSources() async {
    try {
      final op = await ProviderApiService.getServiceOptionPrices();
      final ad = await ProviderApiService.getServicePrices('');
      if (!mounted) return;
      _optionPrices = op;
      _adminRanges = ad;
    } catch (_) {}
  }

  // ── Current job ─────────────────────────────────────────────
  void _startActivePolling() {
    _activeTimer?.cancel();
    _activeTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadActive());
  }

  Future<void> _loadActive() async {
    final res = await ProviderApiService.getActiveBooking();
    if (!mounted || !res.ok) return;
    final b = res.map;
    final active = (b != null && str(b['id']).isNotEmpty) ? b : null;
    if (active != null) _detectChanges(active);
    setState(() => _active = active);
    if (active != null) _setQuoteDeadline(active);
    if (active == null) _setQuoteDeadline(const {});
    LocationService.instance.onJob = active != null &&
        ['confirmed', 'active'].contains(str(active['status']));
    if (active != null && _incoming != null) _closeIncoming(dismiss: false);
  }

  /// Status-change pop-ups (website pDetect()).
  void _detectChanges(Map<String, dynamic> b) {
    final st = str(b['status']);
    final pay = str(b['payment_status']);
    if (_lastStatus != null && st != _lastStatus) {
      if (st == 'confirmed') {
        final p = toInt(b['confirmed_price']) > 0 ? toInt(b['confirmed_price']) : toInt(b['quoted_price']);
        showSnack(context, '✅ Customer Confirmed! ₹$p — open the job and tap Start trip', tone: Tone.success);
      } else if (st == 'searching' && _lastStatus == 'price_quoted') {
        showSnack(context, '❌ Customer Declined — they chose to search another provider', tone: Tone.error);
      } else if (st == 'cancelled') {
        showSnack(context, '❌ Booking Cancelled — this job was cancelled', tone: Tone.error);
      }
    }
    if (_lastPay != null && pay != _lastPay && pay == 'paid') {
      final amt = toInt(b['amount']) > 0 ? toInt(b['amount']) : toInt(b['confirmed_price']);
      showSnack(context, '💰 Payment Received! ₹$amt marked paid', tone: Tone.success);
    }
    _lastStatus = st;
    _lastPay = pay;
  }

  void _setQuoteDeadline(Map<String, dynamic> b) {
    final st = str(b['status']);
    final live = (st == 'price_quoted' || st == 'negotiation_final') && b['quote_expires_in'] != null;
    _quoteDeadline = live ? DateTime.now().add(Duration(seconds: toInt(b['quote_expires_in']))) : null;
    if (_demo) return;
    if (live && _quoteTick == null) {
      _quoteTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _tab == 0) setState(() {});
      });
    } else if (!live) {
      _quoteTick?.cancel();
      _quoteTick = null;
    }
  }

  Future<void> _openBooking(String id, {Map<String, dynamic>? initial}) async {
    if (id.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ActiveBookingScreen(bookingId: id, initial: initial)));
    if (!mounted) return;
    _loadActive();
    _loadBalance();
    _loadProfile();
  }

  // ── Job discovery: single poller ────────────────────────────
  void _syncJobPoller() {
    if (_demo) return;
    final shouldRun = _available && _approved && _foreground;
    if (!shouldRun) {
      _jobsTimer?.cancel();
      _jobsTimer = null;
      if (_incoming != null) _closeIncoming(dismiss: false);
      return;
    }
    if (_jobsTimer != null) return;
    _fetchOpenJobs();
    _jobsTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchOpenJobs());
  }

  Future<void> _fetchOpenJobs() async {
    if (_jobsFetching || _demo) return;
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
    // Alert job disappeared (taken by someone else / cancelled)
    if (_incoming != null && !ids.contains(str(_incoming!['id']))) {
      if (!_acceptingIds.contains(str(_incoming!['id']))) {
        _closeIncoming(dismiss: true);
        showSnack(context, 'That job is no longer available.');
      }
      return;
    }
    // Website: no alerts while a job (incl. completed-but-unpaid) is ours.
    if (_incoming != null || _active != null || !_available) return;
    // Don't ring while another screen (job, ratings…) is on top.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final now = DateTime.now();
    for (final j in jobs) {
      final id = str(j['id']);
      if (id.isEmpty) continue;
      final last = _shownAt[id];
      if (last != null && now.difference(last).inSeconds < 45) continue;
      _shownAt[id] = now;
      _showIncoming(j);
      break;
    }
  }

  int _savedPrice(Map<String, dynamic> job) {
    final svc = str(job['svc_id']);
    return savedPriceFor(svc,
        optionPrices: _optionPrices,
        range: priceRangeFor(_profile, svc),
        adminRanges: _adminRanges);
  }

  void _showIncoming(Map<String, dynamic> job, {bool alert = true}) {
    final saved = _savedPrice(job);
    _priceCtrl.text = saved > 0 ? '$saved' : '';
    setState(() {
      _incoming = job;
      _incomingSaved = saved;
      _countdown = _alertSeconds;
    });
    if (alert) _startAlert();
    if (_demo) return;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 1) {
        t.cancel();
        _closeIncoming(dismiss: true);
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _startAlert() {
    if (_demo) return;
    try {
      Vibration.vibrate(pattern: [0, 600, 200, 600, 200, 600], repeat: 0);
    } catch (_) {}
    _audio?.play(AssetSource('sounds/alert.mp3')).catchError((_) {});
  }

  void _stopAlert() {
    if (_demo) return;
    try { Vibration.cancel(); } catch (_) {}
    try { _audio?.stop(); } catch (_) {}
  }

  void _closeIncoming({required bool dismiss}) {
    _countdownTimer?.cancel();
    _stopAlert();
    final id = str(_incoming?['id']);
    if (dismiss && id.isNotEmpty) _shownAt[id] = DateTime.now();
    if (mounted) setState(() => _incoming = null);
  }

  Future<void> _acceptIncoming() async {
    final job = _incoming;
    if (job == null) return;
    final id = str(job['id']);
    if (id.isEmpty || _acceptingIds.contains(id)) return;
    final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (price < 1) {
      showSnack(context, 'Enter your price for this job', tone: Tone.error);
      return;
    }
    FocusScope.of(context).unfocus();
    _stopAlert();
    setState(() => _acceptingIds.add(id));
    final ok = await sendQuote(context, id, price);
    if (!mounted) return;
    setState(() => _acceptingIds.remove(id));
    _closeIncoming(dismiss: true);
    if (ok) {
      setState(() => _openJobs.removeWhere((j) => str(j['id']) == id));
      await _loadActive();
    } else {
      _fetchOpenJobs();
    }
  }

  // ── Online / offline ────────────────────────────────────────
  Future<void> _toggleAvailability(bool val) async {
    if (_toggling || _demo) return;
    if (val && !_approved) {
      showSnack(context, 'Your account is not approved yet.', tone: Tone.error);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() { _toggling = true; _available = val; });
    if (val) {
      final pos = await LocationService.currentPosition(ask: true);
      if (pos != null) {
        await ProviderApiService.sendLocation(pos.latitude, pos.longitude);
      } else if (mounted) {
        showSnack(context, 'Location unavailable — jobs will be matched by your saved area. '
            'Enable location for better matches.', tone: Tone.warning);
      }
    }
    final res = await ProviderApiService.setAvailable(val);
    if (!mounted) return;
    setState(() => _toggling = false);
    if (!res.ok) {
      setState(() => _available = !val);
      if (!res.unauthorized) {
        showSnack(context, res.error.isNotEmpty ? res.error : 'Could not update', tone: Tone.error);
      }
      return;
    }
    showSnack(context, val ? '✅ You are Online' : 'You are Offline',
        tone: val ? Tone.success : Tone.neutral);
    LocationService.instance.online = val;
    if (!val) {
      _closeIncoming(dismiss: false);
      setState(() => _openJobs = []);
    }
    _syncJobPoller();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will go offline and stop receiving job alerts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44), backgroundColor: AppColors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true || !mounted || _demo) return;
    _jobsTimer?.cancel();
    _activeTimer?.cancel();
    _profileTimer?.cancel();
    _closeIncoming(dismiss: false);
    LocationService.instance.stopAll();
    NotificationService.appReady = false;
    await ProviderApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _openReviews() => Navigator.push(context, MaterialPageRoute(
      builder: (_) => RatingsScreen(providerId: _pid, rating: toDouble(_profile?['rating']))));

  void _selectTab(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    final prev = _tab;
    setState(() {
      _tab = i;
      _visited.add(i);
      if (i == 1) _earningsTick++;
      if (i == 2) _servicesTick++;
    });
    if (prev == 2 && !_demo) {
      // prices may have changed → refresh the "saved price" sources
      _loadPriceSources();
      _loadProfile();
    }
    if (i == 0 && !_demo) _loadActive();
  }

  int _topUpTick = 0;
  void _goTopUp() {
    setState(() => _topUpTick++);
    _selectTab(1);
  }

  // ── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final body = _loading && _profile == null
        ? const Center(child: CircularProgressIndicator())
        : IndexedStack(index: _tab, children: [
            _jobsTab(),
            _visited.contains(1)
                ? EarningsScreen(
                    providerId: _pid,
                    embedded: true,
                    refreshTick: _earningsTick,
                    topUpTick: _topUpTick,
                    profile: _profile,
                    demo: widget.debugEarnings)
                : const SizedBox.shrink(),
            _visited.contains(2)
                ? ServicesScreen(
                    providerId: _pid,
                    embedded: true,
                    refreshTick: _servicesTick,
                    demo: widget.debugServices)
                : const SizedBox.shrink(),
            _visited.contains(3)
                ? ProfileTab(
                    providerId: _pid,
                    profile: _profile ?? const {},
                    demo: _demo,
                    onChanged: (p) {
                      setState(() => _profile = p);
                      if (!_demo) _loadProfile();
                    },
                    onOpenReviews: _openReviews,
                    onLogout: _logout,
                  )
                : const SizedBox.shrink(),
          ]);

    return PopScope(
      canPop: _tab == 0 && _incoming == null,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_incoming != null) {
          _closeIncoming(dismiss: true);
        } else if (_tab != 0) {
          _selectTab(0);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlay,
        child: Stack(children: [
          Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _selectTab,
              destinations: [
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _active != null || (_available && _openJobs.isNotEmpty),
                    smallSize: 8,
                    backgroundColor: AppColors.brand,
                    child: const Icon(Icons.work_outline_rounded),
                  ),
                  selectedIcon: const Icon(Icons.work_rounded),
                  label: 'Jobs',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Earnings',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.home_repair_service_outlined),
                  selectedIcon: Icon(Icons.home_repair_service_rounded),
                  label: 'Services',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
          ),
          if (_incoming != null) _incomingOverlay(),
        ]),
      ),
    );
  }

  Widget _incomingOverlay() {
    final job = _incoming!;
    final busy = _acceptingIds.contains(str(job['id']));
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.55),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
              child: NewJobCard(
                job: job,
                secondsLeft: _countdown,
                totalSeconds: _alertSeconds,
                savedPrice: _incomingSaved,
                priceController: _priceCtrl,
                busy: busy,
                onAccept: _acceptIncoming,
                onSkip: () => _closeIncoming(dismiss: true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── JOBS TAB ───────────────────────────────────────────────
  Widget _jobsTab() {
    final t = Theme.of(context).textTheme;
    final name = str(_profile?['name'], 'Provider');
    final photo = photoUrl(_profile?['photo']);
    final city = str(_profile?['city']);
    final due = toInt(_balance?['commission_due']);
    final rating = toDouble(_profile?['rating']);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          Avatar(name: name, photo: photo, radius: 20, bg: Colors.white24, fg: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              Text([_pid, if (city.isNotEmpty) city].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: Colors.white70)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'WhatsApp support',
            icon: const Icon(Icons.support_agent_rounded),
            onPressed: () => openSupport(context, providerId: _pid, extra: 'Provider ID $_pid.'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshAll();
          await _fetchOpenJobs();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _availabilityCard(),
            if (!_approved) ...[
              const SizedBox(height: 12),
              Notice('Your account is ${str(_profile?['status'], 'pending')}. You can go online once approved.',
                  tone: Tone.warning),
            ],
            if (due > 0) ...[
              const SizedBox(height: 12),
              Notice('Commission due on cash jobs: ₹$due. If dues grow too large you cannot accept new jobs.',
                  tone: Tone.error,
                  icon: Icons.warning_amber_rounded,
                  action: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _goTopUp,
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('Add money to wallet'),
                    ),
                  )),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatTile(
                  value: '${toInt(_profile?['total_bookings'])}',
                  label: 'Jobs done', icon: Icons.task_alt_rounded)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(
                  value: money(_profile?['total_earned']),
                  label: 'Earned', icon: Icons.currency_rupee_rounded, color: AppColors.green)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(
                  value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                  label: 'Rating', icon: Icons.star_rounded, color: const Color(0xFFF5A623),
                  onTap: _openReviews)),
            ]),
            const SectionTitle('Active job'),
            if (_active != null)
              ActiveJobCard(
                booking: _active!,
                quoteDeadline: _quoteDeadline,
                onOpen: () => _openBooking(str(_active!['id']), initial: _active),
                onAddMoney: _goTopUp,
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  child: Row(children: [
                    const IconTile(Icons.work_history_outlined, color: AppColors.muted),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('No active job — stay online for alerts',
                          style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                    ),
                  ]),
                ),
              ),
            if (_active == null && _approved) ..._openJobsSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _openJobsSection() {
    if (!_available) return const [];
    return [
      SectionTitle('New jobs near you (${_openJobs.length})'),
      if (_openError.isNotEmpty) Notice(_openError, tone: Tone.error, margin: const EdgeInsets.only(bottom: 10)),
      if (_openJobs.isEmpty)
        const Card(
          child: EmptyState(
            icon: Icons.notifications_active_outlined,
            title: 'Waiting for new jobs',
            subtitle: 'Keep the app open — you will hear an alert as soon as a customer near you books.',
          ),
        )
      else
        ..._openJobs.map(_openJobTile),
    ];
  }

  Widget _openJobTile(Map<String, dynamic> j) {
    final t = Theme.of(context).textTheme;
    final place = jobPlace(j);
    final slot = slotWhen(j['slot_date'], j['slot_time']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showIncoming(j, alert: false),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(12)),
                child: Text(jobIcon(j), style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(j['svc_name'], 'Service'), style: t.titleSmall),
                  if (slot.isNotEmpty)
                    Text(slot, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  if (place.isNotEmpty)
                    Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _showIncoming(j, alert: false),
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Quote'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _availabilityCard() {
    final on = _available;
    final t = Theme.of(context).textTheme;
    return Card(
      color: on ? AppColors.greenSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: on ? AppColors.green.withOpacity(0.45) : AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _approved && !_toggling ? () => _toggleAvailability(!on) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: on ? AppColors.green : const Color(0xFFE3EAEC),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.power_settings_new_rounded,
                  color: on ? Colors.white : AppColors.muted, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(on ? 'You are Online ✓' : 'You are Offline',
                    style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: on ? const Color(0xFF0F6D33) : AppColors.ink)),
                const SizedBox(height: 2),
                Text(on ? 'Receiving job alerts near you' : 'Go online to receive jobs',
                    style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              ]),
            ),
            _toggling
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                : Switch(
                    value: on,
                    onChanged: _approved ? _toggleAvailability : null,
                  ),
          ]),
        ),
      ),
    );
  }
}
