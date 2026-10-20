import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamaraservice_provider/screens/dashboard_screen.dart';
import 'package:hamaraservice_provider/screens/earnings_screen.dart';
import 'package:hamaraservice_provider/screens/services_screen.dart';
import 'package:hamaraservice_provider/utils/theme.dart';

Widget _app() => MaterialApp(
      theme: AppTheme.theme,
      home: const DashboardScreen(
        providerId: 'HSP-1',
        debugProfile: {'id': 'HSP-1', 'name': 'Test', 'status': 'approved', 'available': 0},
        debugEarnings: EarningsDemo(balance: {'available': 500}),
        debugServices: ServicesDemo(enabled: {}),
      ),
    );

void main() {
  testWidgets('bottom navigation switches tabs and back returns to Jobs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('You are Offline'), findsOneWidget);

    await tester.tap(find.text('Earnings').last);
    await tester.pumpAndSettle();
    expect(find.text('Add money to wallet'), findsOneWidget);

    await tester.tap(find.text('Services').last);
    await tester.pumpAndSettle();
    expect(find.text('My Services'), findsOneWidget);

    // Android back on a non-Jobs tab → Jobs tab (the app stays open).
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 0);
  });
}
