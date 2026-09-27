import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The first of July.
///
/// Pakistan's financial year runs 1 July to 30 June, and invoice series are
/// numbered by it: `INV-2627-0001`. `numbering_sequences` is scoped to
/// `(firm, doc_type, device, fiscal_year)`, and first run seeds rows for the
/// fiscal year the shop was created in and no other.
///
/// Nothing created next year's row. `SequenceAllocator` threw
/// `SequenceNotConfigured` when it found none, nothing anywhere caught it, and
/// the exception's own message told the shopkeeper to "set up numbering for
/// the new financial year before billing" — through a screen that does not
/// exist and a code path that was never written.
///
/// So every shop running this would have stopped being able to bill on 1 July.
/// Not degraded, not slower: a hard throw on the sale path, at the counter,
/// on a date known years in advance, for every user at once. It would have
/// looked like the app breaking overnight for no reason.
///
/// The fix is to mint the year's row on first use, in the same transaction as
/// the document that needed it. A financial year turning over is not an
/// exceptional condition — it is the calendar.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;

  /// A shop set up in August 2026, which is FY 2026-27.
  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    db = await openTestDatabase();
    ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
  });

  tearDown(() async => db.close());

  /// An actor whose business date is [date], which is what decides the series.
  ///
  /// Built from an instant rather than set directly, because that is how the
  /// app builds one: 09:00 UTC is 14:00 in Lahore, safely inside the same
  /// local day either side of the boundary this is about.
  ActorContext on(String date) {
    final parts = date.split('-').map(int.parse).toList();
    return ActorContext(
      firmId: firm.firmId,
      userId: firm.ownerUserId,
      deviceId: firm.deviceId,
      startedAtUtc: DateTime.utc(parts[0], parts[1], parts[2], 9),
    );
  }

  Future<DocumentNumber> number(ActorContext actor, String docType) =>
      runner.run(
        actor,
        (tx) => const SequenceAllocator().allocate(
          tx,
          docType: docType,
          fiscalYear: actor.businessDate.fiscalYear,
        ),
      );

  test('the year the shop opened in was seeded, and still numbers', () async {
    final first = await number(on('2026-08-23'), 'sale_invoice');
    expect(first.formatted, 'INV-2627-0001');
    expect(first.fiscalYear, 2627);
  });

  test('30 June is the last day of that year', () async {
    expect(BusinessDate('2027-06-30').fiscalYear, 2627);
    final last = await number(on('2027-06-30'), 'sale_invoice');
    expect(last.formatted, startsWith('INV-2627-'));
  });

  test('1 July still bills, on a series nobody had to create by hand', () {
    // The load-bearing one. Before the fix this threw
    // SequenceNotConfigured and the shop could not sell anything.
    expect(BusinessDate('2027-07-01').fiscalYear, 2728);
    return expectLater(
      number(on('2027-07-01'), 'sale_invoice').then((n) => n.formatted),
      completion('INV-2728-0001'),
    );
  });

  test('the new year starts at one, not where the old one stopped', () async {
    for (var i = 0; i < 3; i++) {
      await number(on('2027-06-30'), 'sale_invoice');
    }
    final rollover = await number(on('2027-07-01'), 'sale_invoice');

    expect(
      rollover.sequence,
      1,
      reason:
          'the new financial year carried on from the old one, so the shop '
          'has no INV-2728-0001 and an auditor asks where it went',
    );
  });

  test('the old year is untouched and can still be numbered into', () async {
    // A shopkeeper entering a bill dated 29 June on 2 July, which happens
    // every year in every shop that does its paperwork on Sundays.
    await number(on('2027-07-01'), 'sale_invoice');
    final backdated = await number(on('2027-06-29'), 'sale_invoice');

    expect(backdated.formatted, 'INV-2627-0001');
  });

  test('every series rolls over, not only invoices', () async {
    // A receipt and a journal entry are minted by the same allocator on the
    // same day, and a shop that can bill but cannot take a payment on 1 July
    // is no better off.
    for (final type in ['sale_invoice', 'payment_in', 'journal_entry']) {
      await expectLater(
        number(on('2027-07-01'), type),
        completes,
        reason: '$type could not be numbered in the new financial year',
      );
    }
  });

  test('a document type nobody has defined numbering for still throws', () {
    // The guard has to keep meaning something. "The new year has not been
    // opened yet" is the calendar and is now handled; "some code asked for a
    // kind of document nobody decided the numbering for" is a programming
    // error and has to surface as one rather than inventing a prefix.
    return expectLater(
      number(on('2026-08-23'), 'wedding_invitation'),
      throwsA(isA<SequenceNotConfigured>()),
    );
  });

  test('the minted row keeps this counter reserved block', () async {
    // Two tills on one shop's wi-fi must never mint the same number. The block
    // is per device, and a new year that reset it to the default would put
    // Counter 2 back on the same numbers as Counter 1 the moment the year
    // turned — the one failure the block exists to prevent, arriving annually.
    await runner.run(on('2026-08-23'), (tx) async {
      final row = await tx.selectOne(
        '''
        SELECT id FROM numbering_sequences
        WHERE firm_id = ? AND doc_type = 'sale_invoice' AND fiscal_year = 2627
        ''',
        [firm.firmId],
      );
      await tx.update('numbering_sequences', row!.read<String>('id'), {
        'block_start': 5000,
        'block_end': 9999,
        'next_value': 5000,
      });
    });

    await number(on('2027-07-01'), 'sale_invoice');

    final rows = await db.customSelect('''
          SELECT block_start, block_end, next_value FROM numbering_sequences
          WHERE doc_type = 'sale_invoice' AND fiscal_year = 2728
          ''').get();

    expect(rows, hasLength(1));
    expect(rows.single.read<int>('block_start'), 5000);
    expect(rows.single.read<int>('block_end'), 9999);
    expect(
      rows.single.read<int>('next_value'),
      5001,
      reason: 'the new year did not start inside this counter reserved block',
    );
  });

  test('minting is recorded like any other write', () async {
    // Through TxRunner, so the row gets its envelope, its change_log entry and
    // its audit row. A sequence that appears in the database with no record of
    // who created it or when is exactly the kind of thing an auditor asks
    // about, and the answer has to be in the books.
    await number(on('2027-07-01'), 'sale_invoice');

    final changes = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM change_log '
          "WHERE entity_table = 'numbering_sequences'",
        )
        .getSingle();

    expect(changes.read<int>('n'), greaterThan(0));
  });
}
