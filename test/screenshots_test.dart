// Renders the main provider screens to PNGs with real fonts (no device needed).
//
//   flutter test --update-goldens test/screenshots_test.dart
//
// writes test/goldens/*.png (1080x2400, devicePixelRatio 3 = a 360dp phone).
// All data is sample data passed through the screens' test-only parameters,
// so nothing touches the network or platform plugins.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamaraservice_provider/screens/active_booking_screen.dart';
import 'package:hamaraservice_provider/screens/dashboard_screen.dart';
import 'package:hamaraservice_provider/screens/earnings_screen.dart';
import 'package:hamaraservice_provider/screens/email_otp_screen.dart';
import 'package:hamaraservice_provider/screens/login_screen.dart';
import 'package:hamaraservice_provider/screens/profile_edit_screen.dart';
import 'package:hamaraservice_provider/screens/services_screen.dart';
import 'package:hamaraservice_provider/services/provider_api_service.dart';
import 'package:hamaraservice_provider/utils/theme.dart';

const _emojiFont = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf';

String _materialFontsDir() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty)
    return '$root/bin/cache/artifacts/material_fonts';
  final exe = Platform.resolvedExecutable;
  final i = exe.indexOf('/bin/cache/');
  return '${exe.substring(0, i)}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File(f);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final dir = _materialFontsDir();
  await _loadFont('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Black', 'Light'])
      '$dir/Roboto-$w.ttf',
  ]);
  await _loadFont('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
  await _loadFont('NotoColorEmoji', [_emojiFont]);
  // ✓ ✕ ₹ etc. (Android has these in its system fonts)
  await _loadFont(
      'DejaVuSans', ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']);
}

final _theme = AppTheme.build(
    fontFamily: 'Roboto', fontFamilyFallback: ['NotoColorEmoji', 'DejaVuSans']);

const _pid = 'HSP-RAVI42';

final Map<String, dynamic> _profile = {
  'id': _pid,
  'name': 'Ravi Kumar',
  'email': 'ravi.kumar@example.com',
  'phone': '9876543210',
  'city': 'Visakhapatnam',
  'status': 'approved',
  'available': 1,
  'rating': '4.8',
  'review_count': 37,
  'total_bookings': 126,
  'total_earned': 48250,
  'upi_id': 'ravikumar@ybl',
  'areas': '["Gajuwaka","Sheelanagar","MVP Colony","Madhurawada"]',
  'radius_km': 8,
  'base_lat': '17.6868',
  'base_lng': '83.2185',
  'address': 'Sector 4, MVP Colony, Visakhapatnam',
  'services': [
    {'svc_id': 'SVC001', 'min_price': 299, 'max_price': 799},
  ],
};

final List<Map<String, dynamic>> _openJobs = [
  {
    'id': 'HS-BK-20931',
    'svc_id': 'SVC001',
    'svc_name': 'Home Deep Cleaning',
    'svc_icon': '🧹',
    'address': 'Gajuwaka, Visakhapatnam',
    'distance_km': 2.4,
    'slot_date': '2099-01-01',
    'slot_time': 'Morning (8 AM – 12 PM)',
    'summary': '["2 BHK","Kitchen deep clean","Bathroom x2"]',
    'notes': 'Please bring your own ladder',
  },
  {
    'id': 'HS-BK-20935',
    'svc_id': 'SVC010',
    'svc_name': 'AC Service & Repair',
    'svc_icon': '❄️',
    'address': 'Sheelanagar, Visakhapatnam',
    'distance_km': 5.1,
    'slot_time': 'Evening (4 PM – 8 PM)',
  },
];

Map<String, dynamic> _booking(String status,
        {Map<String, dynamic> extra = const {}}) =>
    {
      'id': 'HS-BK-20931',
      'svc_id': 'SVC001',
      'svc_name': 'Home Deep Cleaning',
      'svc_icon': '🧹',
      'status': status,
      'payment_status': 'pending',
      'quoted_price': 650,
      'confirmed_price': 650,
      'contact_name': 'Anita Sharma',
      'contact_phone': '9123456780',
      'address': 'Flat 302, Sai Residency, Gajuwaka',
      'city': 'Visakhapatnam',
      'distance_km': 2.4,
      'slot_time': 'Morning (8 AM – 12 PM)',
      'summary': '["2 BHK","Kitchen deep clean","Bathroom x2"]',
      'notes': 'Please bring your own ladder',
      'cash_allowed': 1,
      'platform_fee': 65,
      ...extra,
    };

final _earnings = EarningsDemo(
  balance: {
    'available': 3240,
    'total_earned': 48250,
    'in_process': 1500,
    'withdrawn': 43510,
    'commission_due': 0,
    'completed_bookings': 126,
  },
  payouts: [
    {
      'amount': 1500,
      'account_type': 'upi',
      'upi_id': 'ravikumar@ybl',
      'requested_at': '2026-10-18 10:42:00',
      'status': 'pending'
    },
    {
      'amount': 5000,
      'account_type': 'bank',
      'bank_name': 'SBI',
      'account_last4': '4421',
      'requested_at': '2026-10-02 18:05:00',
      'status': 'approved'
    },
  ],
  jobs: [
    {
      'svc_name': 'Home Deep Cleaning',
      'other_party': 'Anita S.',
      'completed_at': '2026-10-19 12:10:00',
      'amount': 650,
      'commission_pct': 10,
      'commission_amt': 65,
      'provider_earns': 585,
      'payment_status': 'paid',
      'payment_method': 'online'
    },
  ],
);

const _services = ServicesDemo(
  enabled: {'SVC001': true, 'SVC002': true, 'SVC010': true},
  ranges: {
    'SVC001': [299, 799],
    'SVC010': [450, 1200]
  },
);

Future<void> _shot(WidgetTester tester, Widget screen, String name,
    {Future<void> Function()? before}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // flutter_test paints shadows as solid outlines by default; show real ones
  // (restored before the test ends, as the framework requires).
  debugDisableShadows = false;
  try {
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false, theme: _theme, home: screen));
    await tester.pump(const Duration(milliseconds: 100));
    if (before != null) await before();
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

DashboardScreen _shell(
        {int tab = 0,
        Map<String, dynamic>? active,
        Map<String, dynamic>? incoming,
        bool online = true}) =>
    DashboardScreen(
      providerId: _pid,
      initialTab: tab,
      debugProfile: {..._profile, 'available': online ? 1 : 0},
      debugActive: active,
      debugOpenJobs: online ? _openJobs : const [],
      debugIncoming: incoming,
      debugBalance: const {'commission_due': 0},
      debugEarnings: _earnings,
      debugServices: _services,
    );

void main() {
  final skip = !Platform.isLinux; // goldens are rendered on Linux
  setUpAll(_loadFonts);

  testWidgets('jobs tab — online with new jobs',
      (t) => _shot(t, _shell(), 'jobs_online'),
      skip: skip);
  testWidgets('jobs tab — offline',
      (t) => _shot(t, _shell(online: false), 'jobs_offline'),
      skip: skip);
  testWidgets('new job alert',
      (t) => _shot(t, _shell(incoming: _openJobs.first), 'new_job_alert'),
      skip: skip);
  testWidgets('jobs tab — active job', (t) async {
    await _shot(
        t,
        _shell(active: _booking('confirmed', extra: {'cash_allowed': 0})),
        'jobs_active');
  }, skip: skip);
  testWidgets('earnings tab', (t) => _shot(t, _shell(tab: 1), 'earnings'),
      skip: skip);
  testWidgets('services tab', (t) => _shot(t, _shell(tab: 2), 'services'),
      skip: skip);
  testWidgets('profile tab', (t) => _shot(t, _shell(tab: 3), 'profile'),
      skip: skip);

  testWidgets('edit profile — social links', (t) async {
    await _shot(
        t,
        const ProfileEditScreen(providerId: 'HS-PRO-RAVI6780', providerData: {
          'name': 'Ravi Kumar',
          'phone': '9123456780',
          'city': 'Hyderabad',
          'bio': 'Wedding and corporate event anchor, 6 years.',
          'instagram_url': 'https://instagram.com/ravi.anchor',
          'youtube_url': 'https://youtube.com/@RaviAnchor',
          'followers': '25K',
        }),
        'profile_edit_social');
    expect(find.text('https://instagram.com/ravi.anchor'), findsOneWidget);
    expect(find.text('25K'), findsOneWidget);
  }, skip: skip);

  testWidgets('active job — start trip', (t) async {
    await _shot(
        t,
        ActiveBookingScreen(
            bookingId: 'HS-BK-20931', initial: _booking('confirmed'), demo: true),
        'active_job_start_trip');
  }, skip: skip);
  testWidgets('active job — on the way', (t) async {
    await _shot(
        t,
        ActiveBookingScreen(
            bookingId: 'HS-BK-20931',
            initial: {..._booking('confirmed'), 'travel_started_at': '2026-10-22 10:05:00'},
            demo: true),
        'active_job_on_the_way');
  }, skip: skip);
  testWidgets('active job — start OTP', (t) async {
    await _shot(
        t,
        ActiveBookingScreen(
            bookingId: 'HS-BK-20931',
            initial: {..._booking('confirmed'), 'travel_started_at': '2026-10-22 10:05:00',
                'arrived_at': '2026-10-22 10:21:00', 'start_otp_requested': 1},
            demo: true),
        'active_job_confirmed', before: () async {
      await t.enterText(find.byType(TextField).first, '48');
    });
  }, skip: skip);
  testWidgets('active job — negotiating', (t) async {
    await _shot(
        t,
        ActiveBookingScreen(
            bookingId: 'HS-BK-20931',
            initial: _booking('negotiating',
                extra: {'counter_price': 550, 'contact_phone': null}),
            demo: true),
        'active_job_negotiating');
  }, skip: skip);
  testWidgets('active job — in progress', (t) async {
    await _shot(
        t,
        ActiveBookingScreen(
            bookingId: 'HS-BK-20931',
            initial: _booking('active', extra: {'completion_otp_requested': 1}),
            demo: true),
        'active_job_in_progress');
  }, skip: skip);
  testWidgets('active job — payment pending', (t) async {
    await _shot(
        t,
        ActiveBookingScreen(
            bookingId: 'HS-BK-20931',
            initial: _booking('completed', extra: {
              'amount': 650,
              'commission_pct': 10,
              'commission_amt': 65,
              'provider_earns': 585,
            }),
            demo: true),
        'active_job_payment_pending');
  }, skip: skip);
  testWidgets('login', (t) => _shot(t, const LoginScreen(), 'login'), skip: skip);

  // ── Registration: email verification code ──
  EmailOtpScreen otp({Future<String> Function(String)? verify, Future<int> Function()? resend}) =>
      EmailOtpScreen(
        email: 'ravi.plumber@example.com',
        verify: verify ?? (c) async => 'tok-$c',
        resend: resend ?? () async => 60,
      );

  testWidgets('register — email otp', (t) async {
    await _shot(t, otp(), 'register_email_otp', before: () async {
      await t.enterText(find.byKey(const ValueKey('otp-field')), '482');
    });
    expect(find.text('Verify & Submit Application'), findsOneWidget);
    expect(find.textContaining('Resend in'), findsOneWidget);
  }, skip: skip);

  testWidgets('register — email otp wrong code', (t) async {
    await _shot(
        t,
        otp(verify: (c) async => throw ApiException('Incorrect code. 4 attempts left.', 400)),
        'register_email_otp_error', before: () async {
      await t.enterText(find.byKey(const ValueKey('otp-field')), '123456'); // auto-submits
    });
    expect(find.text('Incorrect code. 4 attempts left.'), findsOneWidget);
  }, skip: skip);

  testWidgets('email otp: countdown, resend, verify pops token', (t) async {
    String? popped;
    var sends = 0;
    await t.pumpWidget(MaterialApp(
      theme: _theme,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await Navigator.push<String>(ctx,
                  MaterialPageRoute(builder: (_) => otp(resend: () async { sends++; return 60; })));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Resend in 1:00'), findsOneWidget);
    await t.pump(const Duration(seconds: 61));
    await t.tap(find.text('Resend code'));
    await t.pump();
    expect(sends, 1);
    await t.enterText(find.byKey(const ValueKey('otp-field')), '654321');
    await t.pumpAndSettle();
    expect(popped, 'tok-654321');
  });
}
