import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart' show ReportPeriod;
import 'package:test/test.dart';

import 'support/test_db.dart';

/// "Baqi chhor do": a balance settled with a discount or written off, with
/// the reason kept (M44) — against a real database.
///
/// What an accountant would check: the bills read settled, the receivable
/// came down by exactly what was let go, the expense shows it, the drawer
/// does not, every entry balances — and a cancellation (M31) puts the
/// udhaar back to the paisa.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late DriftUdhaarQueries udhaar;
  late SettleKhataUseCase settle;
  late CorrectEntriesUseCase correct;
  late ActorContext actor;
  late String aslam;
  late String rice;
  late String pcs;
  late String cash;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 1, 6));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    udhaar = DriftUdhaarQueries(db);
    settle = SettleKhataUseCase(writer: DriftSettlementWriter(runner: runner));
    correct = CorrectEntriesUseCase(
      writer: DriftCorrectionWriter(runner: runner),
    );
    final catalogue = DriftCatalogueWriter(runner);
    aslam = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Aslam Karyana'),
    );
    pcs =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    rice = await catalogue.addItem(
      // On the shelf before the first bill, so the stock ledger reads in order.
      firm.actorAt(DateTime.utc(2026, 1, 1, 4)),
      ItemDraft(
        name: 'Chawal',
        baseUnitId: pcs,
        saleRate: Rate.rupees(100),
        openingStock: Qty.units(500),
      ),
    );
    cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;
  });

  tearDown(() async => db.close());

  Future<PostedSale> bill(String partyId, int rupees, String day) =>
      PostSaleUseCase(writer: DriftSaleWriter(runner: runner))(
        firm.actorAt(DateTime.parse('${day}T04:00:00Z')),
        SaleDraft(
          partyId: partyId,
          lines: [
            SaleLineDraft(
              itemId: rice,
              itemName: 'Chawal',
              qty: Qty.units(rupees ~/ 100),
              baseQty: Qty.units(rupees ~/ 100),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(100),
            ),
          ],
        ),
      );

  ReceiptDraft paid(int rupees) => ReceiptDraft(
    partyId: aslam,
    amount: Money.rupees(rupees),
    mode: 'cash',
    paymentAccountId: cash,
  );

  Future<Money> owed() async =>
      (await queries.partyById(firm.firmId, aslam))!.balance;

  /// The net of one account by system key: debits less credits.
  Future<Money> net(String key) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS n '
          'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
          'WHERE a.system_key = ? AND jl.deleted_at_utc IS NULL',
          variables: [Variable<String>(key)],
        )
        .getSingle();
    return Money.paisa(row.read<int>('n'));
  }

  Future<void> expectBalanced() async {
    final health = await db.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('dr'), totals.read<int>('cr'));
  }

  group('settling with a discount', () {
    test('Rs 9,500 taken on Rs 10,000 settles every bill and posts Rs 500 '
        'to the settlement discount', () async {
      final first = await bill(aslam, 6000, '2026-08-01');
      final second = await bill(aslam, 4000, '2026-08-10');
      final drawer = await queries.cashInDrawer(firm.firmId);

      final done = await settle.settleWithDiscount(
        actor,
        receipt: paid(9500),
        discount: const Money.rupees(500),
        reason: 'Purana gahak',
      );

      expect(done.receipt.amount, const Money.rupees(9500));
      expect(done.discount!.paymentNo, startsWith('SD-'));
      expect(await owed(), Money.zero);
      expect(await queries.openBillsFor(firm.firmId, aslam), isEmpty);
      expect(await net('settlement_discount'), const Money.rupees(500));
      expect(await net('accounts_receivable'), Money.zero);
      // The drawer took Rs 9,500 and not a paisa more.
      expect(
        await queries.cashInDrawer(firm.firmId),
        drawer + const Money.rupees(9500),
      );
      // Oldest first: the receipt cleared the first bill, the discount the
      // last Rs 500 of the second.
      final allocations = await db
          .customSelect(
            'SELECT pa.document_id, pa.amount_paisa, p.payment_no '
            'FROM payment_allocations pa JOIN payments p ON p.id = '
            'pa.payment_id ORDER BY p.payment_no, pa.document_id',
          )
          .get();
      final discount = allocations.where(
        (r) => r.read<String>('payment_no').startsWith('SD-'),
      );
      expect(discount.single.read<String>('document_id'), second.documentId);
      expect(discount.single.read<int>('amount_paisa'), 50000);
      expect(first.documentId, isNot(second.documentId));
      await expectBalanced();
    });

    test('the profit and loss shows the discount as an expense', () async {
      await bill(aslam, 10000, '2026-08-01');
      await settle.settleWithDiscount(
        actor,
        receipt: paid(9500),
        discount: const Money.rupees(500),
      );
      final movements = await DriftReportSource(db).accountMovements(
        firm.firmId,
        ReportPeriod(
          const BusinessDate('2026-07-01'),
          const BusinessDate('2026-09-30'),
        ),
      );
      final line = movements.singleWhere(
        (m) => m.systemKey == 'settlement_discount',
      );
      expect(line.type, 'expense');
      expect(line.debit - line.credit, const Money.rupees(500));
    });

    test('a discount larger than what is left is refused, and nothing is '
        'written', () async {
      await bill(aslam, 10000, '2026-08-01');
      await expectLater(
        settle.settleWithDiscount(
          actor,
          receipt: paid(9500),
          discount: const Money.rupees(600),
        ),
        throwsA(isA<AllowanceRefused>()),
      );
      expect(await owed(), const Money.rupees(10000));
      expect(await db.customSelect('SELECT id FROM payments').get(), isEmpty);
    });
  });

  group('writing off', () {
    test('the whole balance goes to bad debts with its reason, and the '
        'khata shows the line', () async {
      await bill(aslam, 3000, '2026-05-01');
      await bill(aslam, 2000, '2026-06-01');

      final written = await settle.letGo(
        actor,
        AllowanceDraft(
          partyId: aslam,
          kind: AllowanceKind.writeOff,
          amount: await owed(),
          reason: 'Gahak chala gaya',
        ),
      );

      expect(written.paymentNo, startsWith('WO-'));
      expect(await owed(), Money.zero);
      expect(await net('bad_debts'), const Money.rupees(5000));
      final history = await queries.partyLedger(firm.firmId, aslam);
      expect(history.last.reference, written.paymentNo);
      expect(history.last.balanceAfter, Money.zero);
      final list = await udhaar.allowances(
        firm.firmId,
        kind: AllowanceKind.writeOff,
      );
      expect(list.single.reason, 'Gahak chala gaya');
      expect(list.single.partyName, 'Aslam Karyana');
      expect(list.single.byName, 'Malik Sahib');
      expect(list.single.cancelled, isFalse);
      final audit = await db
          .customSelect(
            'SELECT summary FROM audit_log WHERE action_code = '
            "'BAD_DEBT_WRITTEN_OFF'",
          )
          .get();
      expect(audit.single.read<String>('summary'), contains('chala gaya'));
      await expectBalanced();
    });

    test('chosen bills go in full and the rest is still owed', () async {
      final old = await bill(aslam, 3000, '2026-05-01');
      await bill(aslam, 2000, '2026-08-01');
      await settle.letGo(
        actor,
        AllowanceDraft(
          partyId: aslam,
          kind: AllowanceKind.writeOff,
          amount: const Money.rupees(3000),
          reason: 'Dispute settled',
          documentIds: [old.documentId],
        ),
      );
      expect(await owed(), const Money.rupees(2000));
      final open = await queries.openBillsFor(firm.firmId, aslam);
      expect(open.single.outstanding, const Money.rupees(2000));
      await expectBalanced();
    });

    test('an opening balance is written off too', () async {
      final naseem = await DriftCatalogueWriter(runner).addParty(
        actor,
        const PartyDraft(name: 'Naseem', openingBalance: Money.rupees(2500)),
      );
      await settle.letGo(
        actor,
        AllowanceDraft(
          partyId: naseem,
          kind: AllowanceKind.writeOff,
          amount: const Money.rupees(2500),
          reason: 'Wafaat',
        ),
      );
      expect(
        (await queries.partyById(firm.firmId, naseem))!.balance,
        Money.zero,
      );
      await expectBalanced();
    });

    test('a write-off cancelled puts the udhaar back exactly, and is marked '
        'in the list', () async {
      await bill(aslam, 5000, '2026-05-01');
      final written = await settle.letGo(
        actor,
        AllowanceDraft(
          partyId: aslam,
          kind: AllowanceKind.writeOff,
          amount: const Money.rupees(5000),
          reason: 'Gahak chala gaya',
        ),
      );
      await correct.cancelPayment(
        actor,
        paymentId: written.paymentId,
        reason: 'Gahak wapas aa gaya',
      );
      expect(await owed(), const Money.rupees(5000));
      expect(await net('bad_debts'), Money.zero);
      expect(
        (await udhaar.allowances(
          firm.firmId,
          kind: AllowanceKind.writeOff,
        )).single.cancelled,
        isTrue,
      );
      await expectBalanced();
    });

    test('a write-off is not edited into a receipt', () async {
      await bill(aslam, 5000, '2026-05-01');
      final written = await settle.letGo(
        actor,
        AllowanceDraft(
          partyId: aslam,
          kind: AllowanceKind.writeOff,
          amount: const Money.rupees(5000),
          reason: 'Gahak chala gaya',
        ),
      );
      await expectLater(
        correct.editReceipt(
          actor,
          paymentId: written.paymentId,
          draft: paid(5000),
          reason: 'galti',
        ),
        throwsA(isA<VoidRefused>()),
      );
      expect(await owed(), Money.zero);
    });

    test('a write-off says why, or is refused', () async {
      await bill(aslam, 5000, '2026-05-01');
      await expectLater(
        settle.letGo(
          actor,
          const AllowanceDraft(
            partyId: 'x',
            kind: AllowanceKind.writeOff,
            amount: Money.rupees(5000),
            reason: '',
          ),
        ),
        throwsA(isA<AllowanceRefused>()),
      );
    });
  });

  group('an older shop', () {
    test('whose settlement discount account was archived is refused in '
        'words, and nothing is written', () async {
      // A shop that never had the account is given it by `chart_top_up`
      // the first time it is needed (as M6 added Cheques Issued). One the
      // shop archived by hand is not brought back without asking.
      await runner.run(actor, (tx) async {
        final row = await tx.selectOne(
          "SELECT id FROM accounts WHERE system_key = 'settlement_discount'",
        );
        await tx.softDelete('accounts', row!.read<String>('id'));
      });
      // Soft-deleted is "archived by somebody", which is refused in words…
      await bill(aslam, 1000, '2026-08-01');
      await expectLater(
        settle.settleWithDiscount(
          actor,
          receipt: paid(900),
          discount: const Money.rupees(100),
        ),
        throwsA(isA<AllowanceRefused>()),
      );
      // …and nothing was written.
      expect(await owed(), const Money.rupees(1000));
      final hidden = await db
          .customSelect(
            'SELECT is_active, mode_label FROM payment_accounts '
            "WHERE mode_label = 'adjustment'",
          )
          .get();
      expect(hidden, isEmpty);
    });

    test('the allowance accounts are hidden from every tender', () async {
      await bill(aslam, 1000, '2026-08-01');
      await settle.settleWithDiscount(
        actor,
        receipt: paid(900),
        discount: const Money.rupees(100),
      );
      final offered = await queries.paymentAccounts(firm.firmId);
      expect(offered.where((a) => a.modeLabel == 'adjustment'), isEmpty);
      final kept = await db
          .customSelect(
            'SELECT is_active FROM payment_accounts '
            "WHERE mode_label = 'adjustment'",
          )
          .get();
      expect(kept.single.read<int>('is_active'), 0);
    });
  });
}
