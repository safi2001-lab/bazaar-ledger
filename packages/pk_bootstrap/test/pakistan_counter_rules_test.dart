import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// FBR as a stand-in that answers what the test tells it to, and keeps what
/// it was sent.
final class _Fbr implements FbrGateway {
  final sent = <String>[];
  FbrOutcome Function(String payload) answer = (_) =>
      const FbrTryLater('No signal.');
  var _next = 1;

  FbrOutcome numbered() => FbrPosted('7000007DI000000000${_next++}');

  @override
  Future<FbrOutcome> post(String payloadJson) async {
    sent.add(payloadJson);
    return answer(payloadJson);
  }
}

/// Pakistan's rules at the counter (M59), against a real database: the
/// buyer's name on a big bill, the province's tax on a service at the rate
/// of the tender, the printed price on Third Schedule goods, and FBR's
/// offline mode.
void main() {
  late AppServices shop;
  late FixedClock clock;
  late String firmId;
  late String pcs;
  late Map<String, String> accounts;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 10, 3, 5));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Lahore Hair Studio',
      ownerName: 'Bilal',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    accounts = {
      for (final a in await shop.queries.paymentAccounts(firmId))
        a.modeLabel: a.id,
    };
  });

  tearDown(() => shop.close());

  Future<String> item(
    String name,
    int rupees, {
    bool? service,
    bool? thirdSchedule,
    int? mrp,
  }) => shop.catalogue.addItem(
    shop.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs,
      saleRate: Rate.rupees(rupees),
      hsCode: '3305.1000',
      tracksStock: service != true,
      openingStock: service == true ? Qty.zero : Qty.units(50),
      openingRate: Rate.rupees(rupees ~/ 2),
      isService: service,
      isThirdSchedule: thirdSchedule,
      mrp: mrp == null ? null : Money.rupees(mrp),
    ),
  );

  /// The item as the counter reads it, onto a line.
  Future<SaleLineDraft> line(String itemId, {int? rupees, int qty = 1}) async {
    final it = (await shop.queries.itemById(firmId, itemId))!;
    return SaleLineDraft(
      itemId: it.id,
      itemName: it.name,
      hsCode: it.hsCode,
      qty: Qty.units(qty),
      baseQty: Qty.units(qty),
      unitId: it.unitId,
      unitCode: it.unitCode,
      rate: rupees == null ? it.saleRate : Rate.rupees(rupees),
      mrp: it.mrp,
      isThirdSchedule: it.isThirdSchedule,
      isService: it.isService,
      tracksStock: it.tracksStock,
    );
  }

  TenderDraft tender(String mode, Money amount) => TenderDraft(
    paymentAccountId: accounts[mode]!,
    mode: mode,
    amount: amount,
  );

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<String> args = const [],
  ]) async {
    final result = await shop.database
        .customSelect(
          sql,
          variables: [for (final a in args) Variable<String>(a)],
        )
        .get();
    return [for (final r in result) r.data];
  }

  Future<int> outOfBalance() async =>
      (await rows(
            'SELECT COALESCE(SUM(debit_paisa) - SUM(credit_paisa), 0) AS n '
            'FROM journal_lines',
          )).single['n']!
          as int;

  group('buyer name over Rs 100,000', () {
    test(
      'a registered shop\'s walk-in bill over the line is refused without a name, and nothing is written',
      () async {
        await shop.updateFirm({'is_sales_tax_registered': 1});
        final sofa = await item('Salon chair', 100000);
        final draft = SaleDraft(
          lines: [await line(sofa)],
          tenders: [tender('cash', const Money.rupees(118000))],
        );
        await expectLater(
          shop.postSale(shop.actorNow(), draft),
          throwsA(isA<BuyerNameRequired>()),
        );
        expect(
          await rows(
            "SELECT id FROM documents WHERE doc_type = 'sale_invoice'",
          ),
          isEmpty,
        );
        expect(await rows('SELECT id FROM payments'), isEmpty);
      },
    );

    test(
      'with the name and CNIC the bill keeps both, and FBR is sent the name',
      () async {
        await shop.updateFirm({
          'is_sales_tax_registered': 1,
          'ntn': '1234567-8',
        });
        final fbr = _Fbr()
          ..answer = (_) => const FbrPosted('7000007DI0000000001');
        shop.fbr.gatewayFor = (_) => fbr;
        await shop.fbr.save(const FbrSettings(enabled: true, token: 'pral'));
        final chair = await item('Salon chair', 100000);
        final posted = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(chair)],
            partyName: 'Imran Ahmed',
            partyNtn: tidyCnic('3520212345671'),
            tenders: [tender('cash', const Money.rupees(118000))],
          ),
        );
        final bill = (await rows(
          'SELECT party_id, party_name_snapshot, party_ntn_snapshot, '
          'total_paisa FROM documents WHERE id = ?',
          [posted.documentId],
        )).single;
        expect(bill['party_id'], isNull);
        expect(bill['party_name_snapshot'], 'Imran Ahmed');
        expect(bill['party_ntn_snapshot'], '35202-1234567-1');
        expect(bill['total_paisa'], 11800000);
        expect(await outOfBalance(), 0);

        final receipt = await shop.queries.receiptFor(
          firmId,
          posted.documentId,
        );
        expect(receipt!.customerName, 'Imran Ahmed');

        await shop.fbr.afterSale(posted.documentId);
        await shop.fbr.sendPending();
        expect(fbr.sent.single, contains('"BuyerName":"Imran Ahmed"'));
        expect(fbr.sent.single, contains('"BuyerNTN":"35202-1234567-1"'));
      },
    );

    test(
      'a shop not registered for sales tax is only asked, and the bill goes without a name',
      () async {
        final chair = await item('Salon chair', 120000);
        final posted = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(chair)],
            tenders: [tender('cash', const Money.rupees(120000))],
          ),
        );
        expect(posted.total, const Money.rupees(120000));
      },
    );

    test(
      'a customer in the khata already names the bill, and the s.21(s) cash flag still stands',
      () async {
        await shop.updateFirm({'is_sales_tax_registered': 1});
        final party = await shop.catalogue.addParty(
          shop.actorNow(),
          const PartyDraft(name: 'Shah Builders'),
        );
        final chair = await item('Salon chair', 200000);
        final posted = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(chair)],
            partyId: party,
            partyName: 'Shah Builders',
            tenders: [tender('cash', const Money.rupees(244000))],
          ),
        );
        final bill = (await rows(
          'SELECT cash_threshold_breached FROM documents WHERE id = ?',
          [posted.documentId],
        )).single;
        expect(bill['cash_threshold_breached'], 1);
      },
    );
  });

  group('provincial tax on services', () {
    setUp(() async {
      await shop.counterTax.setServiceTax(
        ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra),
      );
    });

    test(
      'PRA by card is 8% and in cash 16%, on the bill\'s own tax rows, and the books balance',
      () async {
        final cut = await item('Haircut', 1000, service: true);
        expect(
          (await rows('SELECT item_type FROM items WHERE id = ?', [
            cut,
          ])).single['item_type'],
          'service',
        );

        final byCard = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(cut)],
            tenders: [tender('card', const Money.rupees(1080))],
          ),
        );
        final inCash = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(cut)],
            tenders: [tender('cash', const Money.rupees(1160))],
          ),
        );
        expect(byCard.total, const Money.rupees(1080));
        expect(inCash.total, const Money.rupees(1160));

        Future<List<Map<String, Object?>>> taxesOf(String id) => rows(
          'SELECT tax_kind, tax_code, rate_bp, base_paisa, amount_paisa '
          'FROM document_line_taxes WHERE document_id = ?',
          [id],
        );
        expect(await taxesOf(byCard.documentId), [
          {
            'tax_kind': 'provincial_st',
            'tax_code': 'PRA_CARD',
            'rate_bp': 800,
            'base_paisa': 100000,
            'amount_paisa': 8000,
          },
        ]);
        expect(await taxesOf(inCash.documentId), [
          {
            'tax_kind': 'provincial_st',
            'tax_code': 'PRA_STD',
            'rate_bp': 1600,
            'base_paisa': 100000,
            'amount_paisa': 16000,
          },
        ]);
        expect(await outOfBalance(), 0);
        // Owed over, as the shop's other sales tax is.
        final owed = (await rows(
          'SELECT SUM(jl.credit_paisa - jl.debit_paisa) AS n '
          'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
          "WHERE a.system_key = 'output_tax'",
        )).single['n'];
        expect(owed, 24000);
      },
    );

    test(
      'a split tender, part card and part cash, taxes each part at its rate and the paisa add up',
      () async {
        final cut = await item('Bridal makeup', 1000, service: true);
        final posted = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(cut)],
            roundToRupee: false,
            tenders: [
              tender('card', const Money.rupees(500)),
              tender('cash', const Money.rupees(700)),
            ],
          ),
        );
        final taxes = await rows(
          'SELECT tax_code, base_paisa, amount_paisa FROM document_line_taxes '
          'WHERE document_id = ? ORDER BY tax_code',
          [posted.documentId],
        );
        expect(taxes, [
          {'tax_code': 'PRA_CARD', 'base_paisa': 46296, 'amount_paisa': 3704},
          {'tax_code': 'PRA_STD', 'base_paisa': 53704, 'amount_paisa': 8593},
        ]);
        final bill = (await rows(
          'SELECT taxable_paisa, tax_paisa, total_paisa, paid_paisa, '
          'balance_paisa FROM documents WHERE id = ?',
          [posted.documentId],
        )).single;
        expect(bill['taxable_paisa'], 100000);
        expect(bill['tax_paisa'], 12297);
        expect(bill['total_paisa'], 112297);
        expect(bill['paid_paisa'], 112297);
        expect(bill['balance_paisa'], 0);
        final paid = await rows(
          'SELECT mode, amount_paisa FROM payments ORDER BY mode',
        );
        expect(paid, [
          {'mode': 'card', 'amount_paisa': 50000},
          {'mode': 'cash', 'amount_paisa': 62297},
        ]);
        expect(await outOfBalance(), 0);
      },
    );

    test(
      'the receipt says PRA 8% (card), and the sales tax summary lists it on its own row',
      () async {
        await shop.updateFirm({'is_sales_tax_registered': 1});
        final cut = await item('Haircut', 1000, service: true);
        final gel = await item('Hair gel', 500);
        final posted = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(cut), await line(gel)],
            tenders: [tender('card', const Money.rupees(1670))],
          ),
        );
        final receipt = (await shop.queries.receiptFor(
          firmId,
          posted.documentId,
        ))!;
        expect(receipt.tax, const Money.rupees(170));
        expect(receipt.federalTax, const Money.rupees(90));
        expect(receipt.serviceTaxes.single.label, 'PRA 8% (card)');
        expect(receipt.serviceTaxes.single.amount, const Money.rupees(80));
        final paper = const ReceiptLayout().render(receipt);
        expect(paper.any((l) => l.startsWith('PRA 8% (card)')), isTrue);
        expect(
          paper.any((l) => l.startsWith('Sales Tax') && l.endsWith('90.00')),
          isTrue,
        );

        final today = BusinessDate.now(shop.clock);
        final summary = await shop.reports.run(
          ReportKind.salesTax,
          firmId: firmId,
          period: ReportPeriod.monthOf(today),
          today: today,
        );
        final pra = summary.rows.singleWhere(
          (r) => r.cells.first == 'PRA_CARD',
        );
        expect(pra.cells[1], 800);
        expect(pra.cells[2], const Money.rupees(1000));
        expect(pra.cells[3], const Money.rupees(80));
      },
    );

    test(
      'the owner\'s setting is kept in the shop\'s settings and every change is audited',
      () async {
        expect(
          await shop.counterTax.serviceTax(),
          ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra),
        );
        await shop.counterTax.setServiceTax(
          const ServiceTaxSetting(
            authority: ServiceTaxAuthority.kpra,
            standardBp: 1500,
            digitalBp: 1000,
          ),
        );
        await shop.counterTax.setServiceTax(null);
        expect(await shop.counterTax.serviceTax(), isNull);
        final audit = await rows(
          "SELECT summary FROM audit_log WHERE action_code = 'SERVICE_TAX_SET' "
          'ORDER BY at_utc, rowid',
        );
        expect(audit, hasLength(3));
        expect(audit.last['summary'], 'No provincial sales tax on services');
        expect(
          () => shop.counterTax.setServiceTax(
            const ServiceTaxSetting(
              authority: ServiceTaxAuthority.bra,
              standardBp: 9000,
              digitalBp: 0,
            ),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('third schedule', () {
    test(
      'an item keeps its flag and MRP through an edit that does not show them, and a pack sold below its MRP is taxed on the MRP',
      () async {
        await shop.updateFirm({'is_sales_tax_registered': 1});
        final juice = await item(
          'Juice 1L',
          118,
          thirdSchedule: true,
          mrp: 118,
        );
        // An edit from a form that knows nothing of the tax kind (the
        // importer, the quick-add sheet) leaves it as it was.
        await shop.catalogue.updateItem(
          shop.actorNow(),
          juice,
          ItemDraft(
            name: 'Juice 1 litre',
            baseUnitId: pcs,
            saleRate: Rate.rupees(118),
            mrp: const Money.rupees(118),
            hsCode: '2009.8990',
          ),
        );
        final it = (await shop.queries.itemById(firmId, juice))!;
        expect(it.isThirdSchedule, isTrue);
        expect(it.isService, isFalse);

        final posted = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(juice, rupees: 100)],
            tenders: [tender('cash', const Money.rupees(100))],
          ),
        );
        final tax = (await rows(
          'SELECT tax_code, amount_paisa, base_paisa FROM document_line_taxes '
          'WHERE document_id = ?',
          [posted.documentId],
        )).single;
        expect(tax['tax_code'], 'ST_3RD_18');
        expect(tax['amount_paisa'], 1800);
        expect(tax['base_paisa'], 8200);
        expect(posted.total, const Money.rupees(100));
        expect(await outOfBalance(), 0);
      },
    );
  });

  group('offline mode', () {
    test(
      'a bill made while FBR cannot be reached prints the offline mark, and a bill still unsent a day after the connection came back is overdue',
      () async {
        await shop.updateFirm({
          'is_sales_tax_registered': 1,
          'ntn': '1234567-8',
        });
        final fbr = _Fbr();
        shop.fbr.gatewayFor = (_) => fbr;
        await shop.fbr.save(const FbrSettings(enabled: true, token: 'pral'));
        final oil = await item('Cooking oil 5L', 2500);

        // 10:00 — no signal. The bill is made, and FBR cannot be reached.
        final sale = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(oil, qty: 2)],
            tenders: [tender('cash', const Money.rupees(5900))],
          ),
        );
        await shop.fbr.afterSale(sale.documentId);
        expect(await shop.fbr.sendPending(), (
          posted: 0,
          rejected: 0,
          waiting: 1,
        ));
        final offline = (await shop.queries.receiptFor(
          firmId,
          sale.documentId,
        ))!;
        expect(offline.fbrPending, isTrue);
        final paper = const ReceiptLayout().render(offline);
        for (final mark in offlineInvoiceMark) {
          expect(paper.any((l) => l.trim() == mark), isTrue, reason: mark);
        }
        expect(
          (await shop.fbr.settings()).raw['fbr.offline_since'],
          isNotEmpty,
        );

        // 10:30 — one tin comes back. Its credit note waits for the bill's
        // FBR number, and is offline too.
        clock.advance(const Duration(minutes: 30));
        final soldLine = (await shop.queries.returnableLines(
          firmId,
          sale.documentId,
        )).single;
        final back = await shop.recordReturn(
          shop.actorNow(),
          ReturnDraft(
            originalDocumentId: sale.documentId,
            reason: 'Dabba toota hua',
            refundNow: const Money.rupees(2950),
            paymentAccountId: accounts['cash'],
            lines: [
              ReturnLineDraft(
                documentLineId: soldLine.documentLineId,
                qty: Qty.one,
              ),
            ],
          ),
        );
        await shop.fbr.afterReturn(back.documentId);

        // 11:00 — the signal is back, and FBR answers: it refuses the bill.
        // The credit note has no FBR number to name, so it still waits.
        clock.advance(const Duration(minutes: 30));
        final cameBack = clock.nowUtc();
        fbr.answer = (_) => const FbrRejected('0052', 'Buyer type missing.');
        await shop.fbr.sendPending();
        final watch = (await shop.fbr.settings()).raw;
        expect(watch['fbr.offline_since'], isEmpty);
        expect(watch['fbr.back_at'], '${cameBack.millisecondsSinceEpoch}');

        FbrBill note(List<FbrBill> bills) =>
            bills.singleWhere((b) => b.documentId == back.documentId);
        expect(note(await shop.fbr.bills()).connectionBackAtUtc, cameBack);

        // 23 hours on: still inside the day Rule 150XC allows.
        clock.advance(const Duration(hours: 23));
        var late = await shop.fbr.offlineWatch();
        expect(late.offline, 1);
        expect(late.overdue, isEmpty);

        // 25 hours on: overdue, on the FBR screen and on Home.
        clock.advance(const Duration(hours: 2));
        late = await shop.fbr.offlineWatch();
        expect([for (final b in late.overdue) b.documentId], [back.documentId]);
        expect(
          note(await shop.fbr.bills()).isOfflineOverdue(clock.nowUtc()),
          isTrue,
        );

        // Put right and sent: the bill is numbered, the credit note follows
        // it, nothing is overdue, and the paper carries FBR's number instead
        // of the offline mark.
        fbr.answer = (_) => fbr.numbered();
        await shop.fbr.retry(sale.documentId);
        expect(await shop.fbr.sendPending(), (
          posted: 2,
          rejected: 0,
          waiting: 0,
        ));
        expect((await shop.fbr.offlineWatch()).overdue, isEmpty);
        final numbered = (await shop.queries.receiptFor(
          firmId,
          sale.documentId,
        ))!;
        expect(numbered.fbrPending, isFalse);
        final reprint = const ReceiptLayout().render(numbered);
        expect(reprint.any((l) => l.contains('OFFLINE')), isFalse);
        expect(reprint.any((l) => l.contains('FBR Invoice No')), isTrue);
      },
    );

    test('a shop that does not report has nothing offline, ever', () async {
      expect((await shop.fbr.offlineWatch()).offline, 0);
      expect((await shop.fbr.offlineWatch()).overdue, isEmpty);
    });
  });
}
