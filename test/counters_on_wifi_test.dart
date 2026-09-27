import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Lets real sockets answer: the test clock does not move them.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the master turns sync on and shows a code for a counter', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);

    await openSettings(tester);
    await tapText(tester, 'Wi-fi par counters');
    expect(find.text('IS DUKAAN KE PHONE'), findsOneWidget);
    expect(find.text('Counter 1'), findsOneWidget);

    await tester.tap(find.text('Counters ko is phone se milne dein'));
    await _settleIo(tester);
    expect(app.services.sync.isHosting, isTrue);
    expect(find.text('Counters ke liye pata'), findsOneWidget);

    await tapButton(tester, 'Naya counter jorein');
    final code = app.services.sync.pairingCode;
    expect(code, isNotNull);
    expect(find.text(code!), findsOneWidget);

    // Off again, and the screen closed, so nothing is left listening.
    await tester.tap(find.text('Counters ko is phone se milne dein'));
    await _settleIo(tester);
    expect(app.services.sync.isHosting, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('a new phone joins the master from the welcome screen', (
    tester,
  ) async {
    // The test binding answers every HttpClient with a 400; this test is
    // about a real socket between two phones on one machine.
    HttpOverrides.global = null;
    final master = (await tester.runAsync(() async {
      final m = await openInMemoryServices();
      await m.setUpShop(
        shopName: 'Chishti Kiryana Store',
        ownerName: 'Malik Sahib',
        deviceLabel: 'Master',
      );
      return m;
    }))!;
    addTearDown(() => tester.runAsync(master.close));
    final port = (await tester.runAsync(
      () => master.sync.startHosting(
        port: 0,
        address: InternetAddress.loopbackIPv4,
      ),
    ))!;
    final code = master.sync.openJoining();

    final app = await Harness.start(tester);
    await tapText(tester, 'Dukaan ke master phone se jurein');
    await typeInto(tester, 'Master ka pata', '127.0.0.1:$port');
    await typeInto(tester, 'Master par dikhaya code', code);
    await typeInto(tester, 'Is counter ka naam', 'Counter 2');
    await tester.tap(find.text('Jurein'));
    await _settleIo(tester);

    expect(app.services.isSetUp, isTrue);
    expect(await app.services.sync.isCounter(), isTrue);
    expect(find.text('Chishti Kiryana Store'), findsWidgets);
    final devices = await app.services.sync.devices();
    expect(devices.map((d) => d.label), ['Master', 'Counter 2']);

    // Gone from the tree, so the half-minute sync stops with it.
    await tester.pumpWidget(const SizedBox());
  });
}
