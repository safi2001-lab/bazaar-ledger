import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

void main() {
  testWidgets('an error the app hit is shown in Data Health, and cleared', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('crashes');
    addTearDown(() => dir.deleteSync(recursive: true));
    final journal = CrashJournal(File('${dir.path}/crashes.jsonl'))
      ..record(StateError('the printer vanished mid-bill'), null);

    await Harness.startWithShop(
      tester,
      overrides: [crashJournalProvider.overrideWithValue(journal)],
    );
    await openSettings(tester);
    await tapText(tester, 'App is phone par 1 dafa kisi ghalti par ruki');
    expect(find.textContaining('the printer vanished'), findsOneWidget);

    await tapText(tester, 'Saaf karein');
    expect(journal.entries(), isEmpty);
    expect(find.textContaining('the printer vanished'), findsNothing);
  });

  testWidgets('Data Health says whether the books are encrypted', (
    tester,
  ) async {
    await Harness.startWithShop(tester);
    await openSettings(tester);
    // In memory, as in every test: nothing on disk to encrypt.
    await tapText(
      tester,
      'Is phone par hisaab encrypted nahin: phone ka keystore key nahin rakh saka',
    );
  });
}
