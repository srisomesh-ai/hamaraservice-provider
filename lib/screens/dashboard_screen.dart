import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/theme.dart';
import 'login_screen.dart';
import 'active_booking_screen.dart';
import 'services_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  final _user = FirebaseAuth.instance.currentUser;
  bool _available = false;
  bool _loading = true;
  Map<String, dynamic>? _providerData;
  Map<String, dynamic>? _incomingBooking;
  String? _incomingBookingKey;
  Timer? _pollTimer;
  Timer? _alertCountdown;
  int _countdownSeconds = 30;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

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
    if (_user == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('providers/${_user!.uid}').get();
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
  }

  Future<void> _toggleAvailability(bool val) async {
    if (_user == null) return;
    setState(() => _available = val);
    if (val) {
      try {
        final permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          await FirebaseDatabase.instance.ref('providers/${_user!.uid}').update({
            'available': true,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          return;
        }
      } catch (e) {}
    }
    await FirebaseDatabase.instance.ref('providers/${_user!.uid}').update({
      'available': val,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkForBookings());
    _checkForBookings();
  }

  Future<void> _checkForBookings() async {
    if (!_available || _incomingBooking != null || _user == null) return;
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
    if (_incomingBooking == null || _incomingBookingKey == null || _user == null) return;
    _alertCountdown?.cancel();
    final snap = await FirebaseDatabase.instance.ref('active_bookings/$_incomingBookingKey').get();
    if (!snap.exists) {
      setState(() { _incomingBooking = null; _incomingBookingKey = null; });
      return;
    }
    final current = Map<String, dynamic>.from(snap.value as Map);
    if (current['acceptedBy'] != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sorry! Another provider accepted this booking.'),
          backgroundColor: AppColors.red));
      setState(() { _incomingBooking = null; _incomingBookingKey = null; });
      return;
    }
    final providerInfo = {
      'id': _user!.uid,
      'name': _user!.displayName ?? '',
      'phone': _user!.phoneNumber ?? '',
      'photo': _user!.photoURL ?? '',
    };
    final bookingKey = _incomingBookingKey!;
    final booking = Map<String, dynamic>.from(_incomingBooking!);
    await FirebaseDatabase.instance.ref('active_bookings/$bookingKey').update({
      'acceptedBy': providerInfo,
      'status': 'accepted',
      'providerId': _user!.uid,
      'acceptedAt': DateTime.now().toIso8601String(),
    });
    setState(() { _incomingBooking = null; _incomingBookingKey = null; });
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ActiveBookingScreen(bookingKey: bookingKey, booking: booking)));
    }
  }

  void _declineBooking() {
    _alertCountdown?.cancel();
    setState(() { _incomingBooking = null; _incomingBookingKey = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Provider Dashboard'),
        backgroundColor: AppColors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : Stack(
              children: [
                _buildMainContent(),
                if (_incomingBooking != null) _buildIncomingAlert(),
              ],
            ),
    );
  }

  Widget _buildMainContent() {
    final status = _providerData?['status'] ?? 'pending';
    final isApproved = status == 'approved';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
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
                radius: 32,
                backgroundColor: AppColors.brand,
                backgroundImage: _user?.photoURL != null ? NetworkImage(_user!.photoURL!) : null,
                child: _user?.photoURL == null
                    ? Text((_user?.displayName ?? 'P')[0].toUpperCase(),
                        style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_user?.displayName ?? 'Provider',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                Text(_user?.email ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isApproved ? AppColors.green.withOpacity(0.2) : AppColors.yellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isApproved ? AppColors.green : AppColors.yellow),
                  ),
                  child: Text(
                    isApproved ? '✅ Approved' : '⏳ Pending Approval',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: isApproved ? AppColors.green : AppColors.yellow),
                  ),
                ),
              ])),
            ]),
          ),

          const SizedBox(height: 16),

          if (!isApproved) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.yellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.yellow.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.yellow),
                SizedBox(width: 12),
                Expanded(child: Text(
                  'Your account is pending approval from admin. You\'ll be notified once approved.',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                )),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // Availability toggle
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Availability', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text(_available ? '🟢 You are Online' : '🔴 You are Offline',
                  style: TextStyle(fontSize: 13, color: _available ? AppColors.green : AppColors.muted)),
              ])),
              Switch(
                value: _available,
                onChanged: isApproved ? _toggleAvailability : null,
                activeColor: AppColors.green,
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Stats
          Row(children: [
            _statCard('Total Jobs', '${_providerData?['totalJobs'] ?? 0}', Icons.work_rounded, AppColors.teal),
            const SizedBox(width: 12),
            _statCard('Rating', '${_providerData?['rating'] ?? '4.8'}★', Icons.star_rounded, AppColors.yellow),
            const SizedBox(width: 12),
            _statCard('Earnings', '₹${_providerData?['totalEarnings'] ?? 0}', Icons.currency_rupee_rounded, AppColors.green),
          ]),

          const SizedBox(height: 16),

          // Services
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Services',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 12),
                if (_providerData?['services'] == null ||
                    (_providerData!['services'] as List?)?.isEmpty == true)
                  const Text('No services added yet. Tap below to add your services.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted))
                else
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: ((_providerData!['services'] as List?) ?? []).map((s) {
                      final name = s is Map ? s['name'] ?? '' : s.toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.tealSoft,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                        ),
                        child: Text(name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ServicesScreen()));
                      if (result == true) _loadProfile();
                    },
                    icon: const Icon(Icons.edit_rounded, color: AppColors.teal),
                    label: const Text('Edit My Services',
                      style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.teal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_available && isApproved) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.green.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.radar_rounded, color: AppColors.green),
                SizedBox(width: 12),
                Expanded(child: Text(
                  'You are online and visible to customers. New booking alerts will appear automatically.',
                  style: TextStyle(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
      ),
    );
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
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D3D47), AppColors.teal],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('🔔 New Booking!',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: _countdownSeconds <= 10 ? AppColors.red : AppColors.brand,
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text('$_countdownSeconds',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Accept within 30 seconds',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _alertRow('🔧', 'Service', bk['service'] ?? ''),
                    const SizedBox(height: 10),
                    _alertRow('💰', 'Price', '₹${bk['price'] ?? bk['priceVal'] ?? 0}'),
                    const SizedBox(height: 10),
                    _alertRow('📅', 'Date & Time', '${bk['date'] ?? ''} at ${bk['time'] ?? ''}'),
                    const SizedBox(height: 10),
                    _alertRow('📍', 'Address', bk['address'] ?? ''),
                    const SizedBox(height: 10),
                    _alertRow('👤', 'Customer', '${bk['customer'] ?? ''} · ${bk['phone'] ?? ''}'),
                    if ((bk['summary'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6, runSpacing: 6,
                        children: (bk['summary'] as List).map((s) {
                          final parts = s.toString().split(' > ');
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.tealSoft,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                            ),
                            child: Text(
                              parts.length > 1 ? parts.sublist(1).join(' › ') : s.toString(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _declineBooking,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            side: const BorderSide(color: AppColors.red),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('✕ Decline',
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('✅ Accept',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _alertRow(String emoji, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ])),
    ]);
  }
}
