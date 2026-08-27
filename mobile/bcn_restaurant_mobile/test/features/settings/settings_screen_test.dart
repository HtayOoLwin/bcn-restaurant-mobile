import 'package:bcn_restaurant_mobile/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows account, server, printer, version and logout actions', (
    tester,
  ) async {
    var printerOpened = false;
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          fullName: 'Kitchen User',
          user: 'kitchen@example.com',
          serverUrl: 'https://restaurant.example.com',
          appVersion: 'v1.2.3 (45)',
          onPrinterSetup: () => printerOpened = true,
          onLogout: () => loggedOut = true,
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Kitchen User'), findsOneWidget);
    expect(find.text('kitchen@example.com'), findsOneWidget);
    expect(find.text('https://restaurant.example.com'), findsOneWidget);
    expect(find.text('v1.2.3 (45)'), findsOneWidget);

    await tester.tap(find.text('Printer Setup'));
    expect(printerOpened, isTrue);

    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    expect(loggedOut, isTrue);
  });
}
