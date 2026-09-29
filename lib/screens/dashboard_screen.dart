import 'dart:async';
import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/theme.dart';
import '../utils/parse.dart';
import '../services/hs_catalog.dart';
import 'login_screen.dart';
import 'active_booking_screen.dart';
import 'services_screen.dart';
import 'support_screen.dart';
import 'earnings_screen.dart';
import 'ratings_screen.dart';
import 'open_jobs_screen.dart';
import 'profile_edit_screen.dart';
import 'quote_dialog.dart';
import 'schedule_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String providerId;
  const DashboardScreen({super.key, required this.providerId});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  int _currentTab = 0;
  bool _available = false;
  bool _loading = true;
  Map<String, dynamic>? _providerData;
  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic>? _incomingBooking;
  String? _incomingBookingKey;
  Timer? _pollTimer;
  Timer? _alertCountdown;
  StreamSubscription? _bookingWatcher;
  StreamSubscription? _newBookingListener;
  int _countdownSeconds = 30;
  int _openJobsCount = 0;
  final _audioPlayer = AudioPlayer();
  final Set<String> _dismissedBookingKeys = {};
  final Set<String> _reviewNotifiedIds = {};
  bool _checkingBookings = false;
  bool _loggingOut = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  String get _pid => widget.providerId;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.06).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadProfile();
    _startPolling();
    _setupAudio();
  }

  Future<void> _setupAudio() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _alertCountdown?.cancel();
    _bookingWatcher?.cancel();
    _newBookingListener?.cancel();
    _providerDataListener?.cancel();
    _bookingsListener?.cancel();
    _pulseCtrl.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  StreamSubscription? _providerDataListener;
  StreamSubscription? _bookingsListener;

  Future<void> _loadProfile() async {
    // Load immediately from cache first for instant UI
    final cached = await ProviderApiService.getCachedProvider();
    if (cached != null && mounted) {
      setState(() {
        _providerData = cached;
        _available    = _isAvailable(cached['available']);
        _loading      = false;
      });
    }

    // Then fetch fresh from MySQL
    try {
      final fresh = await ProviderApiService.getProfile(_pid);
      if (fresh != null && mounted) {
        await ProviderApiService.cacheProvider(fresh);
        setState(() {
          _providerData = fresh;
          _available    = _isAvailable(fresh['available']);
          _loading      = false;
        });
        if (_checkAccountStatus(fresh)) return;
      }
    } catch (_) {}
    if (!mounted) return;
    if (_loading) setState(() => _loading = false);

    // FCM token
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ProviderApiService.saveFcmToken(token);
    } catch (_) {}
    if (!mounted) return;

    // Periodic refresh every 30 seconds — cancel any previous subscription
    // first (_loadProfile runs again on pull-to-refresh / after edits).
    _providerDataListener?.cancel();
    _providerDataListener = Stream.periodic(const Duration(seconds: 30))
        .asyncMap((_) => ProviderApiService.getProfile(_pid))
        .listen((data) {
      if (data == null || !mounted) return;
      ProviderApiService.cacheProvider(data);
      setState(() {
        _providerData = data;
        _available    = _isAvailable(data['available']);
      });
      _checkAccountStatus(data);
    }, onError: (_) {});

    _listenBookings();
  }

  bool _isAvailable(dynamic v) => v == 1 || v == true || v == '1';

  /// Logs the provider out if the admin suspended/rejected the account.
  /// Returns true when a logout was triggered.
  bool _checkAccountStatus(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? '';
    if (status == 'suspended' || status == 'rejected') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'suspended'
              ? 'Account suspended. Contact info@hamaraservice.com'
              : 'Application rejected. Contact info@hamaraservice.com'),
          backgroundColor: AppColors.red));
      }
      _logout();
      return true;
    }
    return false;
  }

  void _listenBookings() {
    // Polls the provider's active booking — cancel any previous subscription
    // so repeated calls (refresh, profile edits) don't stack listeners.
    _bookingsListener?.cancel();
    _bookingsListener = Stream.periodic(const Duration(seconds: 5))
        .asyncMap((_) => ProviderApiService.getActiveBooking(_pid))
        .listen((booking) {
      if (!mounted) return;
      if (booking == null) {
        setState(() => _bookings = []);
        return;
      }
      final all = <String,dynamic>{'active': booking};
      final mine = all.entries
          .where((e) {
            final b = e.value as Map;
            return b['provider_id']?.toString() == _pid ||
                b['providerId'] == _pid ||
                (b['acceptedBy'] is Map && b['acceptedBy']['id'] == _pid);
          })
          .map((e) => Map<String, dynamic>.from(
              {'id': e.key, ...e.value as Map}))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));

      // Check for new review/rating
      for (final b in mine) {
        final rid = b['id']?.toString() ?? '';
        if ((b['rating'] != null) && !(b['reviewNotified'] == true) &&
            !_reviewNotifiedIds.contains(rid)) {
          _reviewNotifiedIds.add(rid);
          _notifyNewReview(b);
          // Mark as notified
          // Review notified tracked locally
        }
      }

      if (mounted) setState(() => _bookings = mine);
    }, onError: (_) {});
  }

  void _notifyNewReview(Map<String, dynamic> booking) {
    if (!mounted) return;
    final rating = booking['rating']?.toString() ?? '';
    final review = booking['review']?.toString() ?? '';
    final service = booking['service']?.toString() ?? 'Service';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Text('⭐', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('New $rating★ review for $service',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            if (review.isNotEmpty)
              Text('"$review"',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
      ]),
      backgroundColor: AppColors.green,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating));
  }

  Future<void> _toggleAvailability(bool val) async {
    setState(() => _available = val);
    // Update cache immediately so refresh doesn't revert
    final cached = await ProviderApiService.getCachedProvider();
    if (cached != null) {
      cached['available'] = val ? 1 : 0;
      await ProviderApiService.cacheProvider(cached);
    }
    if (val) {
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Going Online',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text(
              'Update your location so nearby customers can find you?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'keep'),
                child: const Text('Keep Existing',
                    style: TextStyle(color: AppColors.muted))),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, 'update'),
                child: const Text('Update Location')),
          ],
        ),
      );
      if (choice == 'update') {
        try {
          final permission = await Geolocator.requestPermission();
          if (permission != LocationPermission.denied &&
              permission != LocationPermission.deniedForever) {
            final pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high);
            String city = '';
            try {
              final placemarks = await placemarkFromCoordinates(
                  pos.latitude, pos.longitude);
              if (placemarks.isNotEmpty) {
                city = placemarks.first.locality ??
                    placemarks.first.subAdministrativeArea ??
                    '';
              }
            } catch (e) {}
            final updated = await ProviderApiService.updateProfile({
              'available': 1,
              'lat': pos.latitude,
              'lng': pos.longitude,
              if (city.isNotEmpty) 'city': city,
            });
            if (!updated) {
              if (mounted) {
                setState(() => _available = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ProviderApiService.lastError.isNotEmpty
                        ? ProviderApiService.lastError
                        : 'Could not go online — check connection'),
                    backgroundColor: AppColors.red));
              }
              return;
            }
            if (city.isNotEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Location updated: $city'),
                  backgroundColor: AppColors.green));
            }
            _loadProfile();
            return;
          }
        } catch (e) {}
      }
    }
    // Use dedicated availability endpoint
    final ok = await ProviderApiService.setAvailable(val);
    if (!ok && mounted) {
      // Revert on failure
      setState(() => _available = !val);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not update status — check connection'),
        backgroundColor: AppColors.red));
    }
  }

  void _startPolling() {
    // Single open-jobs poller (the old 4s stream + 5s timer duplicated the
    // same request). _checkForBookings does nothing while offline, so no
    // network polling happens when the provider is unavailable.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _checkForBookings());
  }

  Future<void> _checkForBookings() async {
    if (!mounted || !_available || _incomingBooking != null) return;
    if (_checkingBookings) return;
    if ((_providerData?['status'] ?? '') != 'approved') return;
    _checkingBookings = true;
    try {
      final openList = await ProviderApiService.getOpenBookings(_pid);
      if (!mounted || !_available || _incomingBooking != null) return;
      final all = <String,dynamic>{for (final b in openList) b['id']?.toString() ?? '': b};
      int count = 0;
      Map<String, dynamic>? first;
      String? firstKey;
      for (final entry in all.entries) {
        if (entry.key.isEmpty) continue;
        final bk = Map<String, dynamic>.from(entry.value as Map);
        if (bk['status'] != 'searching' || bk['acceptedBy'] != null) {
          continue;
        }
        // Check provider offers this service (by svc_id, or name fallback)
        if (!_offersService(bk)) continue;
        count++;
        // Skip if already declined or standbyed this session
        if (_dismissedBookingKeys.contains(entry.key)) continue;
        if (first == null) { first = bk; firstKey = entry.key; }
      }
      if (mounted && count != _openJobsCount) {
        setState(() => _openJobsCount = count);
      }
      if (first != null && firstKey != null) {
        final bk = first;
        final key = firstKey;
        if (mounted) {
          setState(() {
            _incomingBooking = bk;
            _incomingBookingKey = key;
            _countdownSeconds = 30;
          });
          _startCountdown();
          _watchBookingStatus(key);
        }
      }
    } catch (e) {
      // ignore — next tick retries
    } finally {
      _checkingBookings = false;
    }
  }

  void _watchBookingStatus(String bookingKey) {
    _bookingWatcher?.cancel();
    // Check immediately — handles already-cancelled or already-deleted
    ProviderApiService.getBooking(bookingKey).then((snap) {
      if (!mounted || _incomingBookingKey != bookingKey) return;
      if (snap == null) {
        _alertCountdown?.cancel();
        _stopAlert();
        setState(() { _incomingBooking = null; _incomingBookingKey = null; });
        return;
      }
      final status = snap['status']?.toString() ?? '';
      if (status == 'cancelled') {
        _alertCountdown?.cancel();
        _stopAlert();
        setState(() { _incomingBooking = null; _incomingBookingKey = null; });
      }
    });
    // Watch FULL node — catches both status change AND node deletion
    _bookingWatcher = Stream.periodic(const Duration(seconds: 3))
        .asyncMap((_) => ProviderApiService.getBooking(bookingKey))
        .listen((data) {
      if (!mounted || _incomingBookingKey != bookingKey) return;
      // Node deleted = customer cancelled search
      if (data == null) {
        _alertCountdown?.cancel();
        _bookingWatcher?.cancel();
        _stopAlert();
        setState(() { _incomingBooking = null; _incomingBookingKey = null; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Customer cancelled the search.'),
          backgroundColor: AppColors.muted,
          behavior: SnackBarBehavior.floating));
        return;
      }
      final status = data['status']?.toString() ?? '';
      if (status == 'cancelled') {
        _alertCountdown?.cancel();
        _bookingWatcher?.cancel();
        _stopAlert();
        setState(() { _incomingBooking = null; _incomingBookingKey = null; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Customer cancelled this booking.'),
          backgroundColor: AppColors.muted,
          behavior: SnackBarBehavior.floating));
      } else if (status.isNotEmpty && status != 'searching' &&
          data['provider_id']?.toString() != _pid) {
        // Taken by another provider (price_quoted etc.)
        _alertCountdown?.cancel();
        _bookingWatcher?.cancel();
        _stopAlert();
        setState(() { _incomingBooking = null; _incomingBookingKey = null; });
      }
    });
  }

  void _stopAlert() {
    try {
      Vibration.cancel();
      _audioPlayer.stop();
    } catch (e) {}
  }

  void _startCountdown() {
    try {
      Vibration.vibrate(
          pattern: [0, 600, 200, 600, 200, 600], repeat: 0);
    } catch (e) {}
    try {
      _audioPlayer.play(AssetSource('sounds/alert.mp3'));
    } catch (e) {}
    _alertCountdown?.cancel();
    _alertCountdown =
        Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        t.cancel();
        _bookingWatcher?.cancel();
        _stopAlert();
        setState(() {
          _incomingBooking = null;
          _incomingBookingKey = null;
        });
      }
    });
  }

  Future<void> _acceptBooking() async {
    if (_incomingBooking == null || _incomingBookingKey == null) return;
    final bookingKey = _incomingBookingKey!;
    final booking = Map<String, dynamic>.from(_incomingBooking!);
    // Pause the countdown/alert while the provider types a quote.
    _alertCountdown?.cancel();
    _stopAlert();
    final quoted = await showQuoteDialog(context, _pid, booking);
    if (!mounted) return;

    if (quoted == null || quoted <= 0) {
      // Provider cancelled the quote — dismiss this alert (still listed in Open Jobs)
      _bookingWatcher?.cancel();
      _dismissedBookingKeys.add(bookingKey);
      setState(() {
        _incomingBooking = null;
        _incomingBookingKey = null;
      });
      return;
    }

    _alertCountdown?.cancel();
    _bookingWatcher?.cancel();
    _stopAlert();
    setState(() {
      _incomingBooking = null;
      _incomingBookingKey = null;
    });

    try {
      final ok = await ProviderApiService.acceptBooking(bookingKey, quoted);
      if (!ok) {
        if (mounted) {
          final msg = ProviderApiService.lastError;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg == 'Booking not available'
                ? 'Booking already accepted by another provider.'
                : (msg.isNotEmpty ? msg : 'Could not accept booking. Please try again.')),
            backgroundColor: AppColors.red));
        }
        return;
      }

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => ActiveBookingScreen(
                bookingKey: bookingKey,
                booking: {...booking, 'status': 'price_quoted', 'quoted_price': quoted, 'quotedPrice': quoted},
                providerId: _pid)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _standbyBooking() async {
    if (_incomingBooking == null || _incomingBookingKey == null) return;
    _alertCountdown?.cancel();
    _bookingWatcher?.cancel();
    _stopAlert();
    final bookingKey = _incomingBookingKey!;
    // Add to dismissed so it never pops up again this session
    _dismissedBookingKeys.add(bookingKey);
    setState(() {
      _incomingBooking = null;
      _incomingBookingKey = null;
    });
      // Standby saved locally
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Job saved to standby. You can accept it from Open Jobs later.'),
          backgroundColor: AppColors.teal,
          duration: Duration(seconds: 3)));
    }
  }

  void _declineBooking() {
    _alertCountdown?.cancel();
    _bookingWatcher?.cancel();
    _stopAlert();
    // Add to dismissed so it never pops up again this session
    if (_incomingBookingKey != null) {
      _dismissedBookingKeys.add(_incomingBookingKey!);
    }
    setState(() {
      _incomingBooking = null;
      _incomingBookingKey = null;
    });
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    // Stop all polling before the token is cleared
    _pollTimer?.cancel();
    _alertCountdown?.cancel();
    _bookingWatcher?.cancel();
    _providerDataListener?.cancel();
    _bookingsListener?.cancel();
    _stopAlert();
    // Go offline while the JWT is still valid, then clear JWT + cached data
    try {
      await ProviderApiService.setAvailable(false);
    } catch (e) {}
    try {
      await ProviderApiService.logout();
    } catch (e) {}
    if (mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }


  // Server booking statuses where the provider still has work to do
  static const List<String> _activeStatuses = [
    'price_quoted', 'negotiating', 'negotiation_final', 'confirmed',
    'accepted', 'active', 'otp_sent', 'payment_pending',
  ];

  // Get provider's offered service IDs from either Map or List format
  // (List of ids, List of maps with svc_id/svcId/id, or Map {id: true})
  Set<String> get _myServiceIds => serviceIdsOf(_providerData?['services']);

  // Check if provider offers a service by svcId OR service name
  bool _offersService(Map<String, dynamic> booking) {
    final ids = _myServiceIds;
    if (ids.isEmpty) return true; // no filter = accept all
    final svcId = bookingServiceIdOf(booking);
    if (svcId.isNotEmpty && ids.contains(svcId)) return true;
    // Fallback: match by name
    final name = (booking['svc_name'] ?? booking['service'] ?? '').toString().toLowerCase();
    return ids.any((id) => id.toLowerCase() == name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -2))
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (i) => setState(() => _currentTab = i),
          selectedItemColor: AppColors.teal,
          unselectedItemColor: AppColors.muted,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 11),
          items: [
            const BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_rounded),
                label: 'Bookings'),
            BottomNavigationBarItem(
              icon: Stack(children: [
                const Icon(Icons.work_outline_rounded),
                if (_openJobsCount > 0)
                  Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              color: AppColors.red,
                              shape: BoxShape.circle))),
              ]),
              label: 'Open Jobs',
            ),
            const BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal))
          : Stack(children: [
              IndexedStack(index: _currentTab, children: [
                _buildOverview(),
                _buildBookings(),
                OpenJobsScreen(
                    providerId: _pid,
                    providerData: _providerData),
                _buildProfile(),
              ]),
              if (_incomingBooking != null) _buildIncomingAlert(),
            ]),
    );
  }

  // ── OVERVIEW ──────────────────────────────────────────────────
  Widget _buildOverview() {
    final isApproved =
        (_providerData?['status'] ?? 'pending') == 'approved';
    final activeBookings = _bookings
        .where((b) => _activeStatuses.contains(b['status']))
        .toList();
    // Withdrawable balance: server keeps pending_earned = total earned minus
    // requested/approved payouts (same figure payouts.php checks).
    final availableBalance = asInt(_providerData?['pending_earned']);
    final photo = _providerData?['photo']?.toString();
    final name = (_providerData?['name'] ?? '').toString().isNotEmpty
        ? _providerData!['name'].toString()
        : 'Provider';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppColors.teal,
            actions: [
              IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: _logout)
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF0A2E36), AppColors.teal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 60, 16),
                    child: Row(children: [
                      Stack(children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.brand,
                          backgroundImage:
                              (photo?.isNotEmpty == true)
                                  ? NetworkImage(photo!)
                                  : null,
                          child: (photo == null || photo.isEmpty)
                              ? Text(initialOf(name),
                                  style: const TextStyle(
                                      fontSize: 24,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800))
                              : null,
                        ),
                        Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                    color: _available
                                        ? AppColors.green
                                        : AppColors.muted,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white,
                                        width: 2)))),
                      ]),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            Text(_providerData?['email'] ?? '',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: isApproved
                                          ? Colors.green
                                              .withOpacity(0.3)
                                          : Colors.orange
                                              .withOpacity(0.3),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: isApproved
                                              ? AppColors.green
                                              : AppColors.yellow)),
                                  child: Text(
                                      isApproved
                                          ? 'Approved'
                                          : 'Pending',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: isApproved
                                              ? AppColors.green
                                              : AppColors.yellow))),
                            ]),
                          ])),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: RefreshIndicator(
              onRefresh: _loadProfile,
              color: AppColors.teal,
              child: SingleChildScrollView(
                physics:
                    const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    // Pending warning
                    if (!isApproved) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color:
                                AppColors.yellow.withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.yellow
                                    .withOpacity(0.3))),
                        child: const Row(children: [
                          Icon(Icons.info_outline_rounded,
                              color: AppColors.yellow),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Your account is pending admin approval.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.ink2))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Availability
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                          color: _available
                              ? AppColors.green.withOpacity(0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _available
                                  ? AppColors.green
                                      .withOpacity(0.4)
                                  : AppColors.line),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    Colors.black.withOpacity(0.04),
                                blurRadius: 8)
                          ]),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              color: _available
                                  ? AppColors.green
                                      .withOpacity(0.15)
                                  : AppColors.bg,
                              shape: BoxShape.circle),
                          child: Icon(
                              _available
                                  ? Icons
                                      .wifi_tethering_rounded
                                  : Icons
                                      .wifi_tethering_off_rounded,
                              color: _available
                                  ? AppColors.green
                                  : AppColors.muted,
                              size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              Text(
                                  _available
                                      ? 'You are Online'
                                      : 'You are Offline',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _available
                                          ? AppColors.green
                                          : AppColors.ink)),
                              Text(
                                  _available
                                      ? 'Receiving booking alerts'
                                      : 'Toggle to start receiving bookings',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted)),
                            ])),
                        Switch(
                            value: _available,
                            onChanged: isApproved
                                ? _toggleAvailability
                                : null,
                            activeColor: AppColors.green),
                      ]),
                    ),

                    const SizedBox(height: 12),

                    // MY SERVICES BUTTON
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ServicesScreen(providerId: _pid))),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3))),
                        child: Row(children: [
                          Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.miscellaneous_services_rounded,
                              color: const Color(0xFF8B5CF6), size: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('My Services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            Text('Manage your ${HSCatalog.services.length} available services', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ])),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        ]))),

                    // BIG EARNINGS CARD — FIRST
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EarningsScreen(
                                  providerId: _pid))),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1B5E20),
                                Color(0xFF388E3C)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.green
                                    .withOpacity(0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Row(children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                                color:
                                    Colors.white.withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(14)),
                            child: const Icon(
                                Icons
                                    .account_balance_wallet_rounded,
                                color: Colors.white,
                                size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                const Text('Available Balance',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        fontWeight:
                                            FontWeight.w600)),
                                Text('Rs.$availableBalance',
                                    style: const TextStyle(
                                        fontSize: 34,
                                        fontWeight:
                                            FontWeight.w900,
                                        color: Colors.white)),
                                const Text(
                                    'Tap to view details & withdraw',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white60)),
                              ])),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color:
                                    Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle),
                            child: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 18),
                          ),
                        ]),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Stats — Jobs + Rating only
                    Row(children: [
                      _statTile(
                          'Total Jobs',
                          '${_providerData?['total_bookings'] ?? _providerData?['totalBookings'] ?? 0}',
                          Icons.work_rounded,
                          AppColors.teal),
                      const SizedBox(width: 10),
                      _statTile(
                          'Rating',
                          '${_providerData?['rating'] ?? '5.0'}',
                          Icons.star_rounded,
                          AppColors.yellow),
                      const SizedBox(width: 10),
                      _statTile(
                          'Reviews',
                          '${_providerData?['review_count'] ?? _providerData?['reviews'] ?? 0}',
                          Icons.reviews_rounded,
                          AppColors.brand),
                    ]),

                    // Open jobs banner
                    if (_openJobsCount > 0) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _currentTab = 2),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: AppColors.brand
                                  .withOpacity(0.08),
                              borderRadius:
                                  BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.brand
                                      .withOpacity(0.3))),
                          child: Row(children: [
                            Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: AppColors.brand
                                        .withOpacity(0.15),
                                    shape: BoxShape.circle),
                                child: const Icon(
                                    Icons
                                        .notifications_active_rounded,
                                    color: AppColors.brand,
                                    size: 18)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      '$_openJobsCount New Job${_openJobsCount == 1 ? '' : 's'} Available!',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight.w800,
                                          color: AppColors.brand)),
                                  const Text(
                                      'Tap to view pending bookings',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                ])),
                            const Icon(Icons.chevron_right,
                                color: AppColors.brand),
                          ]),
                        ),
                      ),
                    ],

                    // Active bookings
                    if (activeBookings.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Active Bookings',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink)),
                            Text(
                                '${activeBookings.length} active',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted)),
                          ]),
                      const SizedBox(height: 10),
                      ...activeBookings
                          .take(3)
                          .map((b) =>
                              _bookingCard(b, compact: true)),
                    ],



                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8)
            ]),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── BOOKINGS ──────────────────────────────────────────────────
  Widget _buildBookings() {
    final active = _bookings
        .where((b) =>
            _activeStatuses.contains(b['status']))
        .toList();
    final completed = _bookings
        .where((b) => b['status'] == 'completed')
        .toList();
    final cancelled = _bookings
        .where((b) => b['status'] == 'cancelled')
        .toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('My Bookings'),
            backgroundColor: AppColors.teal,
            bottom: const TabBar(
                indicatorColor: AppColors.brand,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: 'Active'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Cancelled')
                ])),
        body: TabBarView(children: [
          _bookingList(active, 'No active bookings'),
          _bookingList(completed, 'No completed bookings yet'),
          _bookingList(cancelled, 'No cancelled bookings'),
        ]),
      ),
    );
  }

  Widget _bookingList(
      List<Map<String, dynamic>> list, String emptyMsg) {
    if (list.isEmpty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Icon(Icons.receipt_long_rounded,
                size: 56, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(emptyMsg,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted)),
          ]));
    }
    return RefreshIndicator(
      onRefresh: () async => _listenBookings(),
      color: AppColors.teal,
      child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) => _bookingCard(list[i])),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b,
      {bool compact = false}) {
    final status = (b['status'] ?? '').toString();
    final statusColor = _statusColor(status);
    final svcName = (b['svc_name'] ?? b['service'] ?? 'Service').toString();
    final custName = (b['customer_name'] ?? b['customer'] ?? '').toString();
    final custPhone = (b['customer_phone'] ?? b['phone'] ?? '').toString();
    final date = (b['slot_date'] ?? b['date'] ?? '').toString();
    final time = (b['slot_time'] ?? b['time'] ?? '').toString();
    final price = [b['confirmed_price'], b['final_price'], b['quoted_price'], b['price']]
        .map((v) => asInt(v))
        .firstWhere((v) => v > 0, orElse: () => 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8)
          ],
          border:
              Border.all(color: statusColor.withOpacity(0.15))),
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.05),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14))),
            child: Row(children: [
              Expanded(
                  child: Text(svcName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink))),
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor))),
            ])),
        Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                const Icon(Icons.person_rounded,
                    size: 13, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                    status == 'completed' || custPhone.isEmpty
                        ? custName
                        : '$custName - $custPhone',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.ink2,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 13, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                    '$date - $time - Rs.$price',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
              ]),
              if (!compact) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_rounded,
                      size: 13, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text((b['address'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted))),
                ]),
              ],
              if (_activeStatuses.contains(status)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ActiveBookingScreen(
                                bookingKey: (b['id'] ?? '').toString(),
                                booking: b,
                                providerId: _pid))),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        minimumSize:
                            const Size(double.infinity, 40),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                    child: const Text('View and Manage',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
              ],
            ])),
      ]),
    );
  }

  // ── PROFILE ───────────────────────────────────────────────────
  Widget _buildProfile() {
    final photo = _providerData?['photo']?.toString();
    final name = (_providerData?['name'] ?? '').toString().isNotEmpty
        ? _providerData!['name'].toString()
        : 'Provider';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: AppColors.teal,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _logout)
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF0A2E36), AppColors.teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)),
              child: SafeArea(
                child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.brand,
                    backgroundImage:
                        (photo?.isNotEmpty == true)
                            ? NetworkImage(photo!)
                            : null,
                    child:
                        (photo == null || photo.isEmpty)
                            ? Text(initialOf(name),
                                style: const TextStyle(
                                    fontSize: 32,
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w800))
                            : null,
                  ),
                  const SizedBox(height: 8),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(_providerData?['email'] ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                ]),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Status + Edit
              Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                        color: (_providerData?['status'] ==
                                'approved')
                            ? AppColors.greenSoft
                            : AppColors.yellow.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(20),
                        border: Border.all(
                            color: (_providerData?['status'] ==
                                    'approved')
                                ? AppColors.green
                                : AppColors.yellow)),
                    child: Text(
                        (_providerData?['status'] ==
                                'approved')
                            ? 'Approved Provider'
                            : 'Pending Approval',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color:
                                (_providerData?['status'] ==
                                        'approved')
                                    ? AppColors.green
                                    : AppColors.yellow))),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProfileEditScreen(
                                  providerId: _pid,
                                  providerData:
                                      _providerData)));
                      if (result == true) _loadProfile();
                    },
                    icon: const Icon(Icons.edit_rounded,
                        size: 14, color: AppColors.teal),
                    label: const Text('Edit',
                        style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.teal),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(20)))),
              ]),

              const SizedBox(height: 16),

              // Stats
              Row(children: [
                _statTile(
                    'Jobs Done',
                    '${_providerData?['completed_bookings'] ?? _providerData?['totalBookings'] ?? 0}',
                    Icons.work_rounded,
                    AppColors.teal),
                const SizedBox(width: 10),
                _statTile(
                    'Rating',
                    '${_providerData?['rating'] ?? '5.0'}',
                    Icons.star_rounded,
                    AppColors.yellow),
                const SizedBox(width: 10),
                _statTile(
                    'Earned',
                    'Rs.${asInt(_providerData?['total_earned'] ?? _providerData?['totalEarned'])}',
                    Icons.currency_rupee_rounded,
                    AppColors.green),
              ]),

              const SizedBox(height: 16),

              // Info cards
              _infoCard(Icons.phone_rounded, 'Phone',
                  _providerData?['phone'] ?? 'Not set'),
              const SizedBox(height: 10),
              _infoCard(Icons.location_city_rounded, 'City',
                  _providerData?['city'] ?? 'Not set'),
              const SizedBox(height: 10),
              _infoCard(Icons.work_history_rounded, 'Experience',
                  _providerData?['experience'] ?? 'Not set'),
              const SizedBox(height: 10),
              _infoCard(Icons.badge_rounded, 'Provider ID', _pid),

              const SizedBox(height: 16),

              // Menu items
              _menuTile(
                  'Earnings and Withdrawals',
                  Icons.account_balance_wallet_rounded,
                  AppColors.green,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              EarningsScreen(providerId: _pid)))),
              const SizedBox(height: 10),
              _menuTile(
                  'My Ratings and Reviews',
                  Icons.star_rounded,
                  AppColors.yellow,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              RatingsScreen(providerId: _pid)))),
              const SizedBox(height: 10),
              _menuTile('My Services', Icons.build_rounded,
                  AppColors.teal, () async {
                final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ServicesScreen(providerId: _pid)));
                if (result == true) _loadProfile();
              }),
              const SizedBox(height: 10),
              _menuTile(
                  'Availability Schedule',
                  Icons.schedule_rounded,
                  AppColors.brand,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ScheduleScreen(providerId: _pid)))),
              const SizedBox(height: 10),
              _menuTile(
                  'Help and Support',
                  Icons.headset_mic_rounded,
                  AppColors.muted,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const SupportScreen()))),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout,
                      color: AppColors.red, size: 18),
                  label: const Text('Sign Out',
                      style: TextStyle(
                          color: AppColors.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                      minimumSize:
                          const Size(double.infinity, 50),
                      side:
                          const BorderSide(color: AppColors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6)
          ]),
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.teal, size: 18)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink)),
        ]),
      ]),
    );
  }

  Widget _menuTile(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8)
            ]),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      fontSize: 14))),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return AppColors.teal;
      case 'active':
        return AppColors.brand;
      case 'completed':
        return AppColors.green;
      case 'cancelled':
        return AppColors.red;
      default:
        return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'price_quoted': return 'Quote Sent';
      case 'negotiating': return 'Negotiating';
      case 'negotiation_final': return 'Final Offer Sent';
      case 'confirmed': return 'Confirmed';
      case 'accepted': return 'Accepted';
      case 'active': return 'In Progress';
      case 'otp_sent': return 'OTP Sent';
      case 'payment_pending': return '⏳ Awaiting Payment';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return s;
    }
  }


  // ── INCOMING ALERT ────────────────────────────────────────────
  Widget _buildIncomingAlert() {
    final bk = _incomingBooking!;
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnim.value,
              child: child,
            );
          },
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 40)
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A2E36), AppColors.teal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('New Booking Alert!',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            Text(
                                'Accept quickly before it expires',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70)),
                          ],
                        ),
                      ),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _countdownSeconds <= 10
                              ? Colors.red.withOpacity(0.8)
                              : AppColors.brand,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '$_countdownSeconds',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              _alertRow2(
                                  Icons
                                      .home_repair_service_rounded,
                                  'Service',
                                  (bk['svc_name'] ?? bk['service'] ?? '').toString(),
                                  AppColors.teal),
                              const Divider(
                                  height: 16,
                                  color: AppColors.line),
                              _alertRow2(
                                  Icons.currency_rupee_rounded,
                                  'Price',
                                  asInt(bk['price'] ?? bk['priceVal']) > 0
                                      ? 'Rs.${asInt(bk['price'] ?? bk['priceVal'])}'
                                      : 'You quote the price',
                                  AppColors.green),
                              const Divider(
                                  height: 16,
                                  color: AppColors.line),
                              _alertRow2(
                                  Icons.calendar_today_rounded,
                                  'Date',
                                  '${bk['slot_date'] ?? bk['date'] ?? ''} at ${bk['slot_time'] ?? bk['time'] ?? ''}',
                                  AppColors.brand),
                              const Divider(
                                  height: 16,
                                  color: AppColors.line),
                              _alertRow2(
                                  Icons.location_on_rounded,
                                  'Address',
                                  (bk['address'] ?? '').toString(),
                                  AppColors.red),
                              const Divider(
                                  height: 16,
                                  color: AppColors.line),
                              _alertRow2(
                                  Icons.person_rounded,
                                  'Customer',
                                  (bk['customer_name'] ?? bk['customer'] ?? '').toString(),
                                  AppColors.muted),
                            ],
                          ),
                        ),
                        if ((bk['summary'] as List?)
                                ?.isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                (bk['summary'] as List).map((s) {
                              final parts =
                                  s.toString().split(' > ');
                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.tealSoft,
                                  borderRadius:
                                      BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.teal
                                          .withOpacity(0.3)),
                                ),
                                child: Text(
                                  parts.length > 1
                                      ? parts
                                          .sublist(1)
                                          .join(' > ')
                                      : s.toString(),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.teal),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // THREE BUTTONS
                        Row(
                          children: [
                            // Decline
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _declineBooking,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(
                                      double.infinity, 48),
                                  side: const BorderSide(
                                      color: AppColors.red),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(
                                              12)),
                                ),
                                child: const Column(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close,
                                        color: AppColors.red,
                                        size: 18),
                                    Text('Decline',
                                        style: TextStyle(
                                            color: AppColors.red,
                                            fontWeight:
                                                FontWeight.w700,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Standby
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _standbyBooking,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(
                                      double.infinity, 48),
                                  side: const BorderSide(
                                      color: AppColors.yellow),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(
                                              12)),
                                ),
                                child: const Column(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    Icon(Icons.pause_circle_rounded,
                                        color: AppColors.yellow,
                                        size: 18),
                                    Text('Standby',
                                        style: TextStyle(
                                            color:
                                                AppColors.yellow,
                                            fontWeight:
                                                FontWeight.w700,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Accept
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _acceptBooking,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.green,
                                  minimumSize: const Size(
                                      double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(
                                              12)),
                                ),
                                child: const Column(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded,
                                        color: Colors.white,
                                        size: 18),
                                    Text('Accept',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight:
                                                FontWeight.w800,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _alertRow2(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ],
          ),
        ),
      ],
    );
  }
}