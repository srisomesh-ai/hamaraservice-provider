import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/theme.dart';
import 'login_screen.dart';
import 'active_booking_screen.dart';
import 'services_screen.dart';
import 'support_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String providerId;
  const DashboardScreen({super.key, required this.providerId});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  int _currentTab = 0;
  bool _available = false;
  bool _loading = true;
  Map<String, dynamic>? _providerData;
  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic>? _incomingBooking;
  String? _incomingBookingKey;
  Timer? _pollTimer;
  Timer? _alertCountdown;
  int _countdownSeconds = 30;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  String get _pid => widget.providerId;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.05).animate(_pulseCtrl);
    _loadProfile();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _alertCountdown?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      // Save FCM token
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseDatabase.instance.ref('providers/$_pid/fcmToken').set(token);
        }
      } catch (e) {}

      final snap = await FirebaseDatabase.instance.ref('providers/$_pid').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        setState(() {
          _providerData = data;
          _available = data['available'] == true;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      if (!snap.exists) return;
      final all = Map<String, dynamic>.from(snap.value as Map);
      final mine = all.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((b) => b['providerId'] == _pid || 
                       (b['acceptedBy'] is Map && b['acceptedBy']['id'] == _pid))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      if (mounted) setState(() => _bookings = mine);
    } catch (e) {}
  }

  Future<void> _toggleAvailability(bool val) async {
    setState(() => _available = val);
    if (val) {
      try {
        final permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          await FirebaseDatabase.instance.ref('providers/$_pid').update({
            'available': true, 'lat': pos.latitude, 'lng': pos.longitude,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          return;
        }
      } catch (e) {}
    }
    await FirebaseDatabase.instance.ref('providers/$_pid').update({
      'available': val, 'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  void _startPolling() {
  _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkForBookings());
  _checkForBookings();
}

void _watchIncomingBooking(String bookingKey) {
  FirebaseDatabase.instance.ref('active_bookings/$bookingKey/status')
    .onValue.listen((event) {
      if (!mounted) return;
      final status = event.snapshot.value?.toString() ?? '';
      if (status == 'cancelled' || status == 'accepted') {
        // Cancel if it was accepted by someone else
        if (status == 'accepted' && _incomingBookingKey == bookingKey) {
          _alertCountdown?.cancel();
          setState(() { _incomingBooking = null; _incomingBookingKey = null; });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking was accepted by another provider.'),
              backgroundColor: AppColors.red));
        }
        if (status == 'cancelled' && _incomingBookingKey == bookingKey) {
          _alertCountdown?.cancel();
          setState(() { _incomingBooking = null; _incomingBookingKey = null; });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer cancelled this booking.'),
              backgroundColor: AppColors.muted));
        }
      }
    });
}

  Future<void> _checkForBookings() async {
    if (!_available || _incomingBooking != null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('active_bookings').get();
      if (!snap.exists) return;
      final all = Map<String, dynamic>.from(snap.value as Map);
      final providerServices = (_providerData?['services'] as List?)
          ?.map((s) => (s is Map ? s['name'] ?? '' : s.toString()).toLowerCase())
          .toList() ?? [];

      for (final entry in all.entries) {
        final bk = Map<String, dynamic>.from(entry.value as Map);
        if (bk['status'] != 'searching') continue;
        if (bk['acceptedBy'] != null) continue;
        final svcName = (bk['service'] ?? '').toString().toLowerCase();
        if (providerServices.isNotEmpty && !providerServices.any((s) => s == svcName)) continue;
        if (mounted) {
          setState(() {
            _incomingBooking = bk;
            _incomingBookingKey = entry.key;
            _countdownSeconds = 30;
          });
          _startCountdown();
        }
        break;
      }
    } catch (e) {}
  }

  void _startCountdown() {
  // Vibrate
  HapticFeedback.heavyImpact();
  _alertCountdown?.cancel();
    _alertCountdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        t.cancel();
        setState(() { _incomingBooking = null; _incomingBookingKey = null; });
      }
    });
  }

  Future<void> _acceptBooking() async {
  if (_incomingBooking == null || _incomingBookingKey == null) return;
  _alertCountdown?.cancel();
  
  final bookingKey = _incomingBookingKey!;
  final booking = Map<String, dynamic>.from(_incomingBooking!);
  
  // Dismiss alert immediately
  setState(() { _incomingBooking = null; _incomingBookingKey = null; });

  try {
    final snap = await FirebaseDatabase.instance
        .ref('active_bookings/$bookingKey').get();
    if (!snap.exists) return;
    
    final current = Map<String, dynamic>.from(snap.value as Map);
    
    // Check if already accepted by someone else
    final existingAccept = current['acceptedBy'];
    if (existingAccept != null && existingAccept != false) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking already accepted by another provider.'),
          backgroundColor: AppColors.red));
      return;
    }

    final providerInfo = {
      'id': _pid,
      'name': _providerData?['name'] ?? '',
      'phone': _providerData?['phone'] ?? '',
      'photo': _providerData?['photo'] ?? '',
    };

    // Update active_bookings
    await FirebaseDatabase.instance.ref('active_bookings/$bookingKey').update({
      'acceptedBy': providerInfo,
      'status': 'accepted',
      'providerId': _pid,
      'providerName': _providerData?['name'] ?? '',
      'acceptedAt': DateTime.now().toIso8601String(),
    });

    // Update bookings collection too — this is what customer sees
    await FirebaseDatabase.instance.ref('bookings/$bookingKey').update({
      'acceptedBy': providerInfo,
      'status': 'accepted',
      'providerId': _pid,
      'providerName': _providerData?['name'] ?? '',
      'acceptedAt': DateTime.now().toIso8601String(),
    });

    if (mounted) Navigator.push(context, MaterialPageRoute(
      builder: (_) => ActiveBookingScreen(
        bookingKey: bookingKey,
        booking: booking,
        providerId: _pid,
      )));
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
  }
}

  void _declineBooking() {
    _alertCountdown?.cancel();
    setState(() { _incomingBooking = null; _incomingBookingKey = null; });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('provider_id');
    await prefs.remove('provider_email');
    await prefs.setBool('provider_logged_in', false);
    await FirebaseDatabase.instance.ref('providers/$_pid').update({'available': false});
    if (mounted) Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        selectedItemColor: AppColors.teal,
        unselectedItemColor: AppColors.muted,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.build_rounded), label: 'Services'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : Stack(children: [
              IndexedStack(
                index: _currentTab,
                children: [
                  _buildOverview(),
                  _buildBookings(),
                  _buildServices(),
                  _buildProfile(),
                ],
              ),
              if (_incomingBooking != null) _buildIncomingAlert(),
            ]),
    );
  }

  Widget _buildOverview() {
    final status = _providerData?['status'] ?? 'pending';
    final isApproved = status == 'approved';
    final activeBookings = _bookings.where((b) =>
      ['accepted','active'].contains(b['status'])).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        backgroundColor: AppColors.teal,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        color: AppColors.teal,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(children: [

            // Profile card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D3D47), AppColors.teal],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 30, backgroundColor: AppColors.brand,
                  child: Text((_providerData?['name'] ?? 'P')[0].toUpperCase(),
                    style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_providerData?['name'] ?? 'Provider',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text(_providerData?['email'] ?? '',
                    style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  Text('ID: $_pid', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isApproved ? AppColors.green.withOpacity(0.2) : AppColors.yellow.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isApproved ? AppColors.green : AppColors.yellow),
                    ),
                    child: Text(isApproved ? 'Approved' : 'Pending Approval',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: isApproved ? AppColors.green : AppColors.yellow)),
                  ),
                ])),
              ]),
            ),

            const SizedBox(height: 14),

            if (!isApproved) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.yellow.withOpacity(0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.yellow),
                  SizedBox(width: 10),
                  Expanded(child: Text('Your account is pending admin approval.',
                    style: TextStyle(fontSize: 13, color: AppColors.ink2))),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // Availability
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Availability', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  Text(_available ? 'You are Online' : 'You are Offline',
                    style: TextStyle(fontSize: 12, color: _available ? AppColors.green : AppColors.muted)),
                ])),
                Switch(value: _available, onChanged: isApproved ? _toggleAvailability : null,
                  activeColor: AppColors.green),
              ]),
            ),

            const SizedBox(height: 14),

            // Stats
            Row(children: [
              _statCard('Total Jobs', '${_providerData?['totalBookings'] ?? _providerData?['totalJobs'] ?? 0}', Icons.work_rounded, AppColors.teal),
              const SizedBox(width: 10),
              _statCard('Rating', '${_providerData?['rating'] ?? '5.0'}', Icons.star_rounded, AppColors.yellow),
              const SizedBox(width: 10),
              _statCard('Earned', '₹${_providerData?['totalEarned'] ?? _providerData?['totalEarnings'] ?? 0}', Icons.currency_rupee_rounded, AppColors.green),
            ]),

            const SizedBox(height: 14),

            if (activeBookings.isNotEmpty) ...[
              _sectionHeader('Active Bookings', '${activeBookings.length} in progress'),
              ...activeBookings.take(3).map((b) => _bookingCard(b, compact: true)),
              const SizedBox(height: 8),
            ],

            if (_available && isApproved) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.green.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.radar_rounded, color: AppColors.green),
                  SizedBox(width: 10),
                  Expanded(child: Text('You are online. Booking alerts will appear automatically.',
                    style: TextStyle(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen())),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                child: const Row(children: [
                  Icon(Icons.headset_mic_rounded, color: AppColors.teal),
                  SizedBox(width: 12),
                  Expanded(child: Text('Help & Support',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                  Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
              ),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildBookings() {
    final active = _bookings.where((b) => ['accepted','active'].contains(b['status'])).toList();
    final completed = _bookings.where((b) => b['status'] == 'completed').toList();
    final cancelled = _bookings.where((b) => b['status'] == 'cancelled').toList();

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
            tabs: [Tab(text: 'Active'), Tab(text: 'Completed'), Tab(text: 'Cancelled')],
          ),
        ),
        body: TabBarView(children: [
          _bookingList(active, 'No active bookings'),
          _bookingList(completed, 'No completed bookings yet'),
          _bookingList(cancelled, 'No cancelled bookings'),
        ]),
      ),
    );
  }

  Widget _bookingList(List<Map<String, dynamic>> list, String emptyMsg) {
    if (list.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(emptyMsg, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.muted)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _loadBookings,
      color: AppColors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (_, i) => _bookingCard(list[i]),
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b, {bool compact = false}) {
    final status = b['status'] ?? '';
    final statusColor = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(b['service'] ?? 'Service',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(_statusLabel(status),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${b['customer'] ?? ''} · ${b['phone'] ?? ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        Text('${b['date'] ?? ''} at ${b['time'] ?? ''} · ₹${b['price'] ?? 0}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        if (!compact) ...[
          const SizedBox(height: 4),
          Text(b['address'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
        ],
        if (['accepted','active'].contains(status)) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ActiveBookingScreen(
                  bookingKey: b['id'] ?? '', booking: b, providerId: _pid))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 38),
              ),
              child: const Text('View Booking',
                style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildServices() {
    final services = (_providerData?['services'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Services'),
        backgroundColor: AppColors.teal,
        actions: [
          TextButton(
            onPressed: () async {
              final result = await Navigator.push(context,
                MaterialPageRoute(builder: (_) => ServicesScreen(providerId: _pid)));
              if (result == true) _loadProfile();
            },
            child: const Text('Edit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: services.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.build_rounded, size: 48, color: AppColors.muted),
              const SizedBox(height: 12),
              const Text('No services added yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ServicesScreen(providerId: _pid)));
                  if (result == true) _loadProfile();
                },
                child: const Text('Add Services'),
              ),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: services.length,
              itemBuilder: (_, i) {
                final svc = services[i] as Map;
                final subtasks = (svc['subtasks'] as List?) ?? [];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(svc['name'] ?? '',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(20)),
                        child: Text(svc['cat'] ?? svc['subcategory'] ?? '',
                          style: const TextStyle(fontSize: 10, color: AppColors.teal, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    if (subtasks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6,
                        children: subtasks.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.line)),
                          child: Text(s.toString(), style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
                        )).toList()),
                    ],
                  ]),
                );
              },
            ),
    );
  }

  Widget _buildProfile() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: AppColors.teal,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const SizedBox(height: 8),
          CircleAvatar(
            radius: 48, backgroundColor: AppColors.teal,
            child: Text((_providerData?['name'] ?? 'P')[0].toUpperCase(),
              style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Text(_providerData?['name'] ?? 'Provider',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          Text(_providerData?['email'] ?? '',
            style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text('ID: $_pid', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: (_providerData?['status'] == 'approved') ? AppColors.greenSoft : AppColors.yellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (_providerData?['status'] == 'approved') ? AppColors.green : AppColors.yellow),
            ),
            child: Text(
              (_providerData?['status'] == 'approved') ? 'Approved Provider' : 'Pending Approval',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: (_providerData?['status'] == 'approved') ? AppColors.green : AppColors.yellow),
            ),
          ),
          const SizedBox(height: 24),

          Row(children: [
            _statCard('Jobs Done', '${_providerData?['totalBookings'] ?? _providerData?['totalJobs'] ?? 0}', Icons.work_rounded, AppColors.teal),
            const SizedBox(width: 10),
            _statCard('Rating', '${_providerData?['rating'] ?? '5.0'}', Icons.star_rounded, AppColors.yellow),
            const SizedBox(width: 10),
            _statCard('Earned', '₹${_providerData?['totalEarned'] ?? 0}', Icons.currency_rupee_rounded, AppColors.green),
          ]),

          const SizedBox(height: 20),

          _profileInfoRow('Phone', _providerData?['phone'] ?? 'Not set', Icons.phone_rounded),
          const SizedBox(height: 10),
          _profileInfoRow('Experience', _providerData?['experience'] ?? 'Not set', Icons.work_history_rounded),
          const SizedBox(height: 10),
          _profileInfoRow('City', _providerData?['city'] ?? _providerData?['address'] ?? 'Not set', Icons.location_city_rounded),

          const SizedBox(height: 20),

          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen())),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
              child: const Row(children: [
                Icon(Icons.headset_mic_rounded, color: AppColors.teal),
                SizedBox(width: 12),
                Expanded(child: Text('Help & Support',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: AppColors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Sign Out',
                style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _profileInfoRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(children: [
        Icon(icon, color: AppColors.teal, size: 20),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ]),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
        Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted': return AppColors.teal;
      case 'active': return AppColors.brand;
      case 'completed': return AppColors.green;
      case 'cancelled': return AppColors.red;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'accepted': return 'Accepted';
      case 'active': return 'In Progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return s;
    }
  }

  Widget _buildIncomingAlert() {
    final bk = _incomingBooking!;
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
          child: Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0D3D47), AppColors.teal],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('New Booking!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _countdownSeconds <= 10 ? AppColors.red : AppColors.brand,
                      shape: BoxShape.circle),
                    child: Center(child: Text('$_countdownSeconds',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  _alertRow('Service', bk['service'] ?? ''),
                  const SizedBox(height: 8),
                  _alertRow('Price', '₹${bk['price'] ?? bk['priceVal'] ?? 0}'),
                  const SizedBox(height: 8),
                  _alertRow('Date', '${bk['date'] ?? ''} at ${bk['time'] ?? ''}'),
                  const SizedBox(height: 8),
                  _alertRow('Address', bk['address'] ?? ''),
                  const SizedBox(height: 8),
                  _alertRow('Customer', '${bk['customer'] ?? ''} · ${bk['phone'] ?? ''}'),
                  if ((bk['summary'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6,
                      children: (bk['summary'] as List).map((s) {
                        final parts = s.toString().split(' > ');
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.tealSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.teal.withOpacity(0.3))),
                          child: Text(parts.length > 1 ? parts.sublist(1).join(' > ') : s.toString(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal)),
                        );
                      }).toList()),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _declineBooking,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: const BorderSide(color: AppColors.red),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: const Text('Decline',
                          style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _acceptBooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: const Text('Accept',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _alertRow(String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label,
        style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
    ]);
  }
}
