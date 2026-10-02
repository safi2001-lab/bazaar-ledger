import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A bill as the shop hands it over (M51), against a real database: the
/// khata block as it stood on the bill's own day, the shop's design kept
/// with its books, its logo and its own payment QR, and how the goods
/// travel.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String pcs;
  late String rashid;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 9, 15, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    rashid = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(
        name: 'Rashid Traders',
        phone: '0300-4471203',
        addressLine1: 'Shop 5, Shah Alam Market',
        city: 'Lahore',
        ntn: '7654321-0',
        openingBalance: Money.rupees(1000),
      ),
    );
    clock.advance(const Duration(minutes: 1));
  });

  tearDown(() => shop.close());

  /// One line at [rupees], [paid] of it in cash, to [partyId] or a walk-in.
  Future<PostedSale> sell(int rupees, {String? partyId, int? paid}) async {
    final item = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cheez ${clock.nowUtc().microsecondsSinceEpoch}',
        baseUnitId: pcs,
        saleRate: Rate.rupees(rupees),
        tracksStock: false,
      ),
    );
    final taken = paid ?? rupees;
    final party = partyId == null
        ? null
        : await shop.queries.partyById(firmId, partyId);
    final sale = await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        partyId: partyId,
        partyName: party?.name,
        lines: [
          SaleLineDraft(
            itemId: item,
            itemName: 'Cheez',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees),
          ),
        ],
        tenders: [
          if (taken > 0)
            TenderDraft(
              paymentAccountId: cash,
              mode: 'cash',
              amount: Money.rupees(taken),
            ),
        ],
      ),
    );
    clock.advance(const Duration(minutes: 1));
    return sale;
  }

  Future<Money> owedNow() async =>
      (await shop.queries.partyById(firmId, rashid))!.balance;

  Future<int> audits(String action) async =>
      (await shop.database
              .customSelect(
                "SELECT COUNT(*) AS n FROM audit_log WHERE action_code = '$action'",
              )
              .getSingle())
          .read<int>('n');

  /// A 64-pixel grey PNG: a black square on white. Standing in for the QR
  /// a bank issued, and deliberately not one.
  Uint8List picture() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAAAAACPAi4CAAAAL0lEQVR42u3XMREAAAjEsPdvGjRwbJAKyN7UsgBOARkGAAAAAAAAAAAA/gCe6TXQgjb5W+rfoMsAAAAASUVORK5CYII=',
  );

  group('the khata on a bill', () {
    test('a reprint carries the balance as it stood when the bill was made, '
        'never today\'s', () async {
      // Rs 2,000, Rs 500 of it at the counter, on top of the Rs 1,000 the
      // khata was opened with.
      final first = await sell(2000, partyId: rashid, paid: 500);
      final atTheCounter = (await shop.billPaper(first.documentId))!.receipt;
      expect(atTheCounter.khata!.before, const Money.rupees(1000));
      expect(atTheCounter.khata!.thisBill, const Money.rupees(1500));
      expect(atTheCounter.khata!.after, const Money.rupees(2500));
      expect(
        atTheCounter.khata!.after,
        await owedNow(),
        reason: 'kul baqaya on a fresh bill is what the khata says',
      );

      // A payment comes in, then another bill.
      await shop.recordReceipt(
        shop.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(2000),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      clock.advance(const Duration(minutes: 1));
      final second = await sell(300, partyId: rashid, paid: 0);
      final next = (await shop.billPaper(second.documentId))!.receipt;
      expect(next.khata!.before, const Money.rupees(500));
      expect(next.khata!.thisBill, const Money.rupees(300));
      expect(next.khata!.after, await owedNow());

      // The first bill, printed again today: the figures of its own day.
      final duplicate = (await shop.billPaper(
        first.documentId,
        copy: ReceiptCopy.duplicate,
      ))!.receipt;
      expect(duplicate.khata!.before, const Money.rupees(1000));
      expect(
        duplicate.khata!.thisBill,
        const Money.rupees(1500),
        reason: 'the bill has since been paid off; what it left then stands',
      );
      expect(duplicate.khata!.after, const Money.rupees(2500));
      expect(await owedNow(), const Money.rupees(800));

      final paper = shop.receipts.toPreview(duplicate).join('\n');
      expect(paper, contains('** DUPLICATE / DOBARA COPY **'));
      expect(paper, contains('2,500.00'));
      expect(paper, contains('(bill ke din ka hisaab)'));
      expect(paper, isNot(contains('800.00')));
    });

    test(
      'a walk-in, and a shop that turned it off, get no khata block',
      () async {
        final walkIn = await sell(500);
        expect(
          (await shop.billPaper(walkIn.documentId))!.receipt.khata,
          isNull,
        );

        final credit = await sell(700, partyId: rashid, paid: 0);
        expect(
          (await shop.billPaper(credit.documentId))!.receipt.khata,
          isNotNull,
        );
        await shop.saveBillDesign(const BillDesign(showPreviousBalance: false));
        final off = (await shop.billPaper(credit.documentId))!.receipt;
        expect(off.khata, isNull);
        expect(
          shop.receipts.toPreview(off).join('\n'),
          contains('BAQAYA (udhaar)'),
          reason: 'without the block, the bill keeps its own udhaar line',
        );
      },
    );
  });

  group('the shop\'s design', () {
    test('is kept with the books and the next bill is drawn in it', () async {
      expect(await shop.billDesign(), const BillDesign());
      const design = BillDesign(
        theme: BillTheme.modern,
        accent: BillAccent.green,
        pageSize: BillPageSize.a4,
        footerLines: ['Bika hua maal wapas nahi hoga', '  '],
      );
      await shop.saveBillDesign(design);
      final kept = await shop.billDesign();
      expect(kept.theme, BillTheme.modern);
      expect(kept.accent, BillAccent.green);
      expect(kept.pageSize, BillPageSize.a4);
      expect(kept.footerLines, ['Bika hua maal wapas nahi hoga']);
      expect(await audits('BILL_DESIGN_SET'), 1);

      // Saved again, it is the same one row, changed.
      await shop.saveBillDesign(kept.copyWith(accent: BillAccent.blue));
      expect((await shop.billDesign()).accent, BillAccent.blue);
      final rows = await shop.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM settings WHERE setting_key = 'bill.design'",
          )
          .getSingle();
      expect(rows.read<int>('n'), 1);

      final bill = (await shop.billPaper((await sell(250)).documentId))!;
      expect(bill.design.accent, BillAccent.blue);
      expect(
        bill.receipt.footerLines,
        contains('Bika hua maal wapas nahi hoga'),
      );
      expect(
        bill.receipt.footerLines,
        isNot(contains(BillDesign.defaultThanks)),
      );
    });

    test('the logo and the payment QR are kept apart, and the QR on the '
        'bill is the one the shop gave', () async {
      final logo = picture();
      final qr = picture();
      await shop.setShopLogo(logo, fileName: 'logo.png');
      await shop.setPaymentQr(qr, fileName: 'jazzcash-qr.png');

      final kinds = await shop.database
          .customSelect(
            'SELECT kind FROM attachments WHERE deleted_at_utc IS NULL '
            'ORDER BY kind',
          )
          .get();
      expect(
        [for (final r in kinds) r.read<String>('kind')],
        ['bank_qr', 'logo'],
      );
      final storedLogo = (await shop.shopLogo())!;
      final storedQr = (await shop.paymentQr())!;
      expect(storedLogo.width, 64, reason: 'a small picture is not enlarged');
      expect(storedQr.mimeType, 'image/png');

      final sale = await sell(900);
      final bill = (await shop.billPaper(sale.documentId))!.receipt;
      expect(bill.shop.logoImage, storedLogo.bytes);
      expect(bill.paymentQr, storedQr.bytes);
      final pdf = String.fromCharCodes(
        await shop.receipts.toPdf(bill, design: await shop.billDesign()),
      );
      expect(pdf, contains(RegExp(r'/Subtype\s*/Image')));

      // On the till roll only when asked.
      expect(
        (await shop.billPaper(
          sale.documentId,
          thermal: ReceiptPaper.mm80,
        ))!.receipt.bankQr,
        isNull,
      );
      await shop.saveBillDesign(const BillDesign(qrOnThermal: true));
      final roll = (await shop.billPaper(
        sale.documentId,
        thermal: ReceiptPaper.mm80,
      ))!.receipt;
      expect(roll.bankQr!.width, ReceiptPaper.mm80.dots);

      await shop.clearPaymentQr();
      expect(await shop.paymentQr(), isNull);
      expect(await shop.shopLogo(), isNotNull, reason: 'the logo stays');
      final without = (await shop.billPaper(sale.documentId))!.receipt;
      expect(without.paymentQr, isNull);
      expect(
        String.fromCharCodes(
          await shop.receipts.toPdf(
            without.copyWith(shop: without.shop.withLogoImage(null)),
          ),
        ),
        isNot(contains(RegExp(r'/Subtype\s*/Image'))),
        reason: 'with no picture, nothing is drawn in its place',
      );
    });

    test('a file that is not a picture is refused in words', () async {
      expect(
        () => shop.setPaymentQr(
          Uint8List.fromList('%PDF-1.4'.codeUnits),
          fileName: 'statement.pdf',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await shop.paymentQr(), isNull);
    });
  });

  group('how the goods travel', () {
    test('is written onto the bill, audited, and printed on the '
        'transporter\'s copy with no price', () async {
      final sale = await sell(2000, partyId: rashid, paid: 0);
      const transport = ReceiptTransport(
        transporter: 'Daewoo Cargo',
        vehicleNo: 'LES-1234',
        biltyNo: 'BT-88123',
        shipTo: 'Faisalabad adda',
      );
      await shop.setTransportDetails(sale.documentId, transport);
      await shop.setTransportDetails(sale.documentId, transport);
      expect(
        await audits('DOCUMENT_TRANSPORT_SET'),
        1,
        reason: 'saving the same details again changes nothing',
      );

      final bill = (await shop.billPaper(
        sale.documentId,
        copy: ReceiptCopy.transporter,
      ))!;
      expect(bill.sendsGoods, isTrue);
      expect(bill.transport.biltyNo, 'BT-88123');
      final paper = shop.receipts.toPreview(bill.receipt).join('\n');
      for (final word in [
        'TRANSPORTER / DELIVERY COPY',
        'Rashid Traders',
        '0300-4471203',
        'Shah Alam Market',
        'Daewoo Cargo',
        'BT-88123',
      ]) {
        expect(paper, contains(word), reason: word);
      }
      for (final amount in ['2,000.00', '1,000.00', '3,000.00']) {
        expect(paper, isNot(contains(amount)), reason: amount);
      }
      final total = await shop.database
          .customSelect(
            'SELECT total_paisa FROM documents WHERE id = '
            "'${sale.documentId}'",
          )
          .getSingle();
      expect(total.read<int>('total_paisa'), 200000);
    });

    test('a tax invoice names the buyer\'s address and NTN from the khata '
        'when the bill recorded none', () async {
      final sale = await sell(1500, partyId: rashid, paid: 1500);
      final extras = (await shop.queries.billExtras(firmId, sale.documentId))!;
      expect(extras.partyAddress, 'Shop 5, Shah Alam Market, Lahore');
      expect(extras.partyNtn, '7654321-0');
      expect(extras.lineTaxes, hasLength(1));
      expect(extras.lineTaxes.single.valueExclTax, const Money.rupees(1500));
    });
  });
}
