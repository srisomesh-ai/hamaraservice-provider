import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/theme.dart';

class TestConsoleScreen extends StatefulWidget {
  final String providerId;
  const TestConsoleScreen({super.key, required this.providerId});
  @override
  State<TestConsoleScreen> createState() => _TestConsoleScreenState();
}

class _TestConsoleScreenState extends State<TestConsoleScreen> {
  final List<String> _logs = [];
  final _audio = AudioPlayer();

  void _log(String msg) {
    setState(() => _logs.insert(0, '${DateTime.now().toString().substring(11,19)} — $msg'));
  }

  // ── Test 1: Vibration ──
  Future<void> _testVibration() async {
    _log('Testing vibration...');
    try {
      final hasVib = await Vibration.hasVibrator() ?? false;
      _log('Has vibrator: $hasVib');
      if (hasVib) {
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
        _log('✅ Vibration triggered!');
      } else {
        _log('❌ No vibrator found');
      }
    } catch (e) { _log('❌ Error: $e'); }
  }

  // ── Test 2: Alert Sound ──
  Future<void> _testSound() async {
    _log('Testing alert sound...');
    try {
      await _audio.play(AssetSource('sounds/alert.mp3'));
      _log('✅ Sound played!');
    } catch (e) {
      _log('❌ Sound error: $e (check assets/sounds/alert.mp3 exists)');
      // Fallback
      SystemSound.play(SystemSoundType.alert);
      _log('  → Fallback system sound played');
    }
  }

  // ── Test 3: Fake new job popup ──
  Future<void> _testNewJobAlert() async {
    _log('Testing new job alert...');
    try {
      final hasVib = await Vibration.hasVibrator() ?? false;
      if (hasVib) Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500, 200, 500]);
      await _audio.play(AssetSource('sounds/alert.mp3'));
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
    if (mounted) {
      showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.teal,
        title: const Text('🔔 New Job! (TEST)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Service: House Cleaning', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          Text('Customer: Ravi Kumar', style: TextStyle(color: Colors.white70)),
          Text('Amount: Rs.499', style: TextStyle(color: Colors.white70)),
          Text('Distance: 2.3 km', style: TextStyle(color: Colors.white70)),
        ]),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _log('→ Declined'); },
            child: const Text('Decline', style: TextStyle(color: Colors.white70))),
          ElevatedButton(onPressed: () { Navigator.pop(context); _log('✅ Accepted!'); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            child: Text('Accept', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800))),
        ],
      ));
      _log('✅ New job popup shown with sound + vibration');
    }
  }

  // ── Test 4: FCM Token ──
  Future<void> _testFCM() async {
    _log('Getting FCM token...');
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _log('✅ FCM: ${token.substring(0, 20)}...');
        await FirebaseDatabase.instance
            .ref('providers/${widget.providerId}/fcmToken').set(token);
        _log('✅ Token saved to Firebase');
      } else {
        _log('❌ No FCM token — check google-services.json');
      }
    } catch (e) { _log('❌ FCM error: $e'); }
  }

  // ── Test 5: Push to self ──
  Future<void> _testPush() async {
    _log('Sending push to self...');
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) { _log('❌ No FCM token'); return; }
      final res = await http.post(
        Uri.parse('https://hamaraservice.com/api/notify_booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event': 'new_booking',
          'fcmToken': token,
          'data': {
            'service': 'Test House Cleaning',
            'price': '499',
            'bookingId': 'TEST-001',
          },
        }),
      );
      final result = jsonDecode(res.body);
      _log(result['sent'] == true
          ? '✅ Push sent! Lock screen and check notification'
          : '❌ Push failed: ${res.body.substring(0, 80)}');
    } catch (e) { _log('❌ Push error: $e'); }
  }

  // ── Test 6: Payment received notification ──
  Future<void> _testPaymentReceived() async {
    _log('Testing payment received...');
    try {
      final hasVib = await Vibration.hasVibrator() ?? false;
      if (hasVib) Vibration.vibrate(pattern: [0, 300, 100, 300]);
    } catch (_) {}
    HapticFeedback.heavyImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🎉 Payment received! Rs.499 for House Cleaning. (TEST)'),
        backgroundColor: AppColors.green,
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating));
      _log('✅ Payment received snackbar shown');
    }
  }

  // ── Test 7: Firebase write/read ──
  Future<void> _testFirebase() async {
    _log('Testing Firebase...');
    try {
      await FirebaseDatabase.instance
          .ref('test_ping/${widget.providerId}').set({
        'ts': DateTime.now().toIso8601String(), 'app': 'provider'
      });
      final snap = await FirebaseDatabase.instance
          .ref('test_ping/${widget.providerId}').get();
      if (snap.exists) {
        _log('✅ Firebase OK');
        await FirebaseDatabase.instance
            .ref('test_ping/${widget.providerId}').remove();
      }
    } catch (e) { _log('❌ Firebase error: $e'); }
  }

  @override
  void dispose() { _audio.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('🛠️ Test Console'),
        backgroundColor: AppColors.teal,
        actions: [TextButton(
          onPressed: () => setState(() => _logs.clear()),
          child: const Text('Clear', style: TextStyle(color: Colors.white)))],
      ),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(12), color: Colors.black87,
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Text('DEV ONLY — Remove before production',
              style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
        Expanded(flex: 1,
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(12),
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: [
              _btn('📳 Vibration', AppColors.teal, _testVibration),
              _btn('🔊 Alert Sound', AppColors.teal, _testSound),
              _btn('🔔 New Job Alert', AppColors.brand, _testNewJobAlert),
              _btn('🔑 FCM Token', AppColors.brand, _testFCM),
              _btn('📲 Push Notify', Colors.deepPurple, _testPush),
              _btn('💰 Payment Done', AppColors.green, _testPaymentReceived),
              _btn('🔥 Firebase', Colors.orange, _testFirebase),
            ],
          )),
        const Divider(height: 1),
        Expanded(flex: 1,
          child: Container(color: Colors.black87,
            child: _logs.isEmpty
                ? const Center(child: Text('Tap a button to test...',
                    style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Text(_logs[i],
                      style: TextStyle(
                        color: _logs[i].contains('✅') ? Colors.greenAccent
                            : _logs[i].contains('❌') ? Colors.redAccent
                            : Colors.white70,
                        fontSize: 12, fontFamily: 'monospace'))))),
      ]),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: Text(label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)));
  }
}
