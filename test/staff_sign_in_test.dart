import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Staff, from the screen: the owner hands out PINs, the app locks, and
/// whoever signs in sees only what their role allows.
void main() {
  testWidgets('the owner sets a PIN and adds a cashier from settings', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);

    await openSettings(tester);
    await tapText(tester, 'Staff aur PIN');
    await tapButton(tester, 'Mera PIN rakhein');
    await typeInto(tester, 'PIN (4 se 6 hindsay)', '1947');
    await typeInto(tester, 'PIN dobara', '1947');
    await tapButton(tester, 'Save karein');
    expect(find.text('PIN rakh diya'), findsOneWidget);

    await tapButton(tester, 'Staff shamil karein');
    await typeInto(tester, 'Naam', 'Bilal');
    await typeInto(tester, 'PIN (4 se 6 hindsay)', '2468');
    await typeInto(tester, 'PIN dobara', '2468');
    await tester.tap(
      find
          .ancestor(
            of: find.text('Staff shamil karein'),
            matching: find.byType(BlButton),
          )
          .last,
    );
    await tester.pumpAndSettle();

    final staff = await app.rowsOf(
      "SELECT name, role, pin_hash FROM users WHERE role = 'cashier'",
    );
    expect(staff.single['name'], 'Bilal');
    expect(staff.single['pin_hash'], isNot('2468'));
    expect(find.text('Bilal'), findsOneWidget);
  });

  testWidgets('two PINs that differ are refused in words', (tester) async {
    await Harness.startWithShop(tester);

    await openSettings(tester);
    await tapText(tester, 'Staff aur PIN');
    await tapButton(tester, 'Mera PIN rakhein');
    await typeInto(tester, 'PIN (4 se 6 hindsay)', '1947');
    await typeInto(tester, 'PIN dobara', '1948');
    await tapButton(tester, 'Save karein');

    expect(find.text('Dono PIN ek jaisay nahi'), findsOneWidget);
  });

  testWidgets('a locked app opens only for the right PIN', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _hireBilal(app);
    await _refresh(tester);

    await tester.tap(find.byTooltip('Taala lagayein'));
    await tester.pumpAndSettle();
    expect(find.text('Kaun hai?'), findsOneWidget);

    await tapText(tester, 'Bilal · Cashier');
    await typeInto(tester, 'PIN', '1111');
    await tapButton(tester, 'Kholein');
    expect(find.text('Ghalat PIN'), findsOneWidget);

    await typeInto(tester, 'PIN', '2468');
    await tapButton(tester, 'Kholein');
    expect(find.text('Kaun hai?'), findsNothing);
    expect(find.text('Naya Bill'), findsWidgets);
  });

  testWidgets("a cashier sees the counter and not the owner's screens", (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _hireBilal(app);
    await _refresh(tester);
    await tester.tap(find.byTooltip('Taala lagayein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Bilal · Cashier');
    await typeInto(tester, 'PIN', '2468');
    await tapButton(tester, 'Kholein');

    expect(find.text('Naya Bill'), findsWidgets);
    expect(find.text('Report'), findsNothing);
    expect(find.text('Kharcha'), findsNothing);
    expect(find.text('Cheque'), findsNothing);

    await openSettings(tester);
    expect(find.text('Staff aur PIN'), findsNothing);
  });
}

/// The owner's PIN, and Bilal at the counter with his own.
Future<String> _hireBilal(Harness app) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  final id = await services.addStaff(
    name: 'Bilal',
    role: Role.cashier,
    pin: '2468',
  );
  return id;
}

/// The home screen as it is after something changed underneath it.
Future<void> _refresh(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}
