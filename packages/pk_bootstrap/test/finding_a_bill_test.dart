import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Finding an old bill again, in SQL (M30).
///
/// The sales list was newest first and nothing else, so "Rashid Sahib's bill
/// from last week" was a scroll. These prove the narrowing happens in the
/// query, under the paging cursor, so page two of a search is page two of
/// that search and not page two of everything with the search applied after.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String pcs;
  late String rashid;
  late String bilal;

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
      const PartyDraft(name: 'Rashid Traders', phone: '0300-4471203'),
    );
    bilal = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: 'Bilal General Store', phone: '0321 7654321'),
    );
  });

  tearDown(() => shop.close());

  /// One line at [rupees], [paid] of it in cash, to [partyId] or a walk-in.
  Future<PostedSale> sell(
    int rupees, {
    String? partyId,
    String? partyName,
    int? paid,
  }) async {
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
    final sale = await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        partyId: partyId,
        partyName: partyName,
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
    // A minute apart, so every bill has its own place in the list.
    clock.advance(const Duration(minutes: 1));
    return sale;
  }

  Future<List<SaleListRow>> find(SaleFilter filter, {String? afterId}) =>
      shop.queries.recentSales(firmId, filter: filter, afterId: afterId);

  List<String> numbers(List<SaleListRow> rows) => [
    for (final r in rows) r.docNo,
  ];

  group('finding a bill', () {
    test('by its number, its customer, their phone, or its amount', () async {
      final big = await sell(
        5525,
        partyId: rashid,
        partyName: 'Rashid Traders',
        paid: 1000,
      );
      final small = await sell(
        800,
        partyId: rashid,
        partyName: 'Rashid Traders',
      );
      final other = await sell(
        1200,
        partyId: bilal,
        partyName: 'Bilal General Store',
      );
      final walkIn = await sell(300);

      // The tail of the number is what a customer reads off the paper.
      final tail = big.docNo.substring(big.docNo.length - 4);
      expect(numbers(await find(SaleFilter(query: tail))), [big.docNo]);

      expect(
        numbers(await find(const SaleFilter(query: 'rashid'))),
        [small.docNo, big.docNo],
        reason: 'a name is matched however it is capitalised',
      );

      // The khata says 0300-4471203; the shopkeeper types it however they
      // like, or only the end of it.
      for (final typed in ['4471203', '0300 4471203', '+92 300 4471203']) {
        expect(
          numbers(await find(SaleFilter(query: typed))),
          [small.docNo, big.docNo],
          reason: typed,
        );
      }
      expect(numbers(await find(const SaleFilter(query: '0321-7654321'))), [
        other.docNo,
      ]);

      for (final typed in ['5525', '5,525', 'Rs 5525', '5525.00']) {
        expect(
          numbers(await find(SaleFilter(query: typed))),
          [big.docNo],
          reason: typed,
        );
      }

      // Nothing typed is everything, the walk-in's bill included.
      expect(
        numbers(await find(SaleFilter.none)),
        [walkIn.docNo, other.docNo, small.docNo, big.docNo],
      );
      expect(await find(const SaleFilter(query: 'Kashif')), isEmpty);
    });

    test('a period and a standing narrow it, and cancelled bills are found '
        'apart', () async {
      final september = await sell(
        1200,
        partyId: bilal,
        partyName: 'Bilal General Store',
      );
      clock.set(DateTime.utc(2026, 10, 1, 6));
      final owed = await sell(
        5525,
        partyId: rashid,
        partyName: 'Rashid Traders',
        paid: 1000,
      );
      clock.set(DateTime.utc(2026, 10, 2, 6));
      final today = await sell(300);
      final cancelled = await sell(
        800,
        partyId: rashid,
        partyName: 'Rashid Traders',
      );
      await shop.voidDocument(
        shop.actorNow(),
        documentId: cancelled.documentId,
        reason: 'Dobara ring ho gaya',
      );

      final october = SaleFilter.none.between(
        const BusinessDate('2026-10-01'),
        const BusinessDate('2026-10-31'),
      );
      expect(numbers(await find(october)), [
        cancelled.docNo,
        today.docNo,
        owed.docNo,
      ]);
      expect(
        numbers(await find(october.copyWith(standing: SaleStanding.udhaar))),
        [owed.docNo],
      );
      expect(
        numbers(await find(october.copyWith(standing: SaleStanding.paid))),
        [today.docNo],
        reason: 'a cancelled bill has nothing owed on it and is still not paid',
      );
      expect(
        numbers(
          await find(october.copyWith(standing: SaleStanding.cancelled)),
        ),
        [cancelled.docNo],
      );

      final oneDay = SaleFilter.none.between(
        const BusinessDate('2026-09-15'),
        const BusinessDate('2026-09-15'),
      );
      expect(numbers(await find(oneDay)), [september.docNo]);

      // Everything at once: Rashid's, in October, still owed.
      expect(
        numbers(
          await find(
            october.copyWith(query: 'Rashid', standing: SaleStanding.udhaar),
          ),
        ),
        [owed.docNo],
      );
    });

    test('a narrowed list still pages past its first forty', () async {
      // Forty-five of Rashid's among a shop's other bills. A filter applied
      // to a page already fetched would find the few on page one and call
      // the rest missing.
      final his = <String>[];
      for (var i = 0; i < 45; i++) {
        his.add(
          (await sell(
            100 + i,
            partyId: rashid,
            partyName: 'Rashid Traders',
          )).docNo,
        );
        if (i.isEven) await sell(50, partyId: bilal, partyName: 'Bilal');
      }

      const filter = SaleFilter(query: 'Rashid');
      final first = await find(filter);
      expect(first, hasLength(40));
      final second = await find(filter, afterId: first.last.id);
      expect(second, hasLength(5));

      expect(
        numbers([...first, ...second]),
        his.reversed.toList(),
        reason: 'every one of his bills, once each, and nobody else\'s',
      );
    });

    test('a bill knows who it goes to, and where to reach them', () async {
      final his = await sell(
        5525,
        partyId: rashid,
        partyName: 'Rashid Traders',
        paid: 1000,
      );
      final walkIn = await sell(300);

      final to = await shop.queries.recipientOf(firmId, his.documentId);
      expect(to?.name, 'Rashid Traders');
      expect(to?.phone, '0300-4471203');
      expect(whatsappNumber(to?.phone), '923004471203');

      expect(
        await shop.queries.recipientOf(firmId, walkIn.documentId),
        isNull,
        reason: 'a walk-in has nobody to send it to',
      );

      // The row in the list carries the same, so a bill can be sent from it
      // without being opened.
      final row = (await find(SaleFilter(query: his.docNo))).single;
      expect(row.partyPhone, '0300-4471203');
      expect(row.partyId, rashid);
    });
  });
}
