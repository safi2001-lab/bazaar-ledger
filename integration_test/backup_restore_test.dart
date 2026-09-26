import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A backup made on the handset, and the books brought back on it after
/// they are gone.
///
/// The host suite proves the archive and the swap against files on a Linux
/// disk. It cannot prove the things that differ on a phone: that the
/// no-backup books directory is where the swap happens, that Android's own
/// SQLite writes a `VACUUM INTO` copy the restore can open, that the seal
/// runs in a background isolate on an ARM or x86 Android runtime, and how
/// long it takes there. This does all of it through the same calls the
/// screens make.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a backup made on the phone brings the books back after a wipe', (
    tester,
  ) async {
    const passphrase = 'chishti-1987';
    final books = await _freshBooks();

    // ---- A shop with something in it -------------------------------------
    var services = await AppServices.open(databasePath: books);
    await services.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      city: 'Lahore',
    );
    await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(
        name: 'Rashid Traders',
        openingBalance: Money.rupees(4500),
      ),
    );

    // ---- The backup, timed -----------------------------------------------
    final clock = Stopwatch()..start();
    final made = await services.backups.create(
      services.actorNow(),
      passphrase: passphrase,
      into: Directory('${(await getTemporaryDirectory()).path}/backups'),
    );
    clock.stop();
    // Printed rather than asserted tight: an emulator is not an Android Go
    // handset, and a number from one is evidence, not a promise about the
    // other. The bound only catches a seal that has gone badly wrong.
    // ignore: avoid_print
    print('backup: ${made.bytes} bytes in ${clock.elapsedMilliseconds} ms');
    expect(clock.elapsed, lessThan(const Duration(seconds: 60)));

    final sealed = await made.file.readAsBytes();
    expect(latin1.decode(sealed), isNot(contains('Chishti')));
    await services.close();

    // ---- The phone loses its books ---------------------------------------
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File('$books$suffix');
      if (f.existsSync()) f.deleteSync();
    }

    // ---- And gets them back ----------------------------------------------
    final candidate = await Restore.inspect(
      sealed,
      passphrase: passphrase,
      scratch: Directory('${(await getTemporaryDirectory()).path}/restore'),
    );
    expect(candidate.shopName, 'Chishti Kiryana Store');
    await Restore.stage(candidate, databasePath: books);

    services = await AppServices.open(databasePath: books);
    addTearDown(services.close);

    expect(services.isSetUp, isTrue);
    final firm = (await services.queries.currentFirm())!;
    expect(firm.name, 'Chishti Kiryana Store');
    final rashid = await services.queries.searchParties(
      firm.id,
      query: 'rashid',
    );
    expect(rashid.single.balance, const Money.rupees(4500));
  });
}

/// The real books path on this device, emptied.
Future<String> _freshBooks() async {
  final dir = await AppServices.booksDirectory();
  final path = '${dir.path}${Platform.pathSeparator}bazaar_ledger.sqlite';
  for (final suffix in const [
    '',
    '-wal',
    '-shm',
    '-journal',
    '.restore',
    '.before-restore',
  ]) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  return path;
}
