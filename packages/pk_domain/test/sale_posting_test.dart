import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The double entry, checked without a database.
///
/// Every assertion here is about which account moves and in which direction.
/// Getting this wrong is the failure mode that stays invisible for six months
/// and then nothing balances and nobody can say when it started.
void main() {
  const calculator = SaleCalculator();
  const builder = SalePostingBuilder();
  const untaxed = TaxContext(
    isSellerRegistered: false,
    buyerIsRegistered: false,
    buyerIsOnAtl: null,
    province: 'punjab',
    pricesIncludeTax: false,
    ruleVersion: 'untaxed-v1',
  );

  final actor = ActorContext(
    firmId: 'F1',
    userId: 'U1',
    deviceId: 'D1',
    startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
  );

  SalePosting post(SaleDraft draft) {
    final calculated = calculator.calculate(draft, untaxed);
    return builder.build(
      actor: actor,
      draft: draft,
      calculated: calculated,
      invoiceNumber: const AllocatedNumber(
        formatted: 'INV-2627-0001',
        series: 'INV',
        sequence: 1,
      ),
      journalNumber: const AllocatedNumber(
        formatted: 'JV-2627-00001',
        series: 'JV',
        sequence: 1,
      ),
      paymentNumbers: [
        for (var i = 0; i < draft.tenders.length; i++)
          AllocatedNumber(
            formatted: 'RCV-2627-000${i + 1}',
            series: 'RCV',
            sequence: i + 1,
          ),
      ],
      ledgerAccountByPaymentAccount: const {
        'PA-CASH': 'ACC-CASH',
        'PA-BANK': 'ACC-BANK',
      },
    );
  }

  SaleLineDraft item({
    String name = 'Item',
    String qty = '1',
    required Rate rate,
    int discountBp = 0,
    Rate cost = Rate.zero,
  }) {
    final q = Qty.parse(qty);
    return SaleLineDraft(
      itemId: 'I-$name',
      itemName: name,
      qty: q,
      baseQty: q,
      unitCode: 'pcs',
      rate: rate,
      discountBp: discountBp,
      unitCost: cost,
    );
  }

  Map<String, ({Money debit, Money credit})> byAccount(SalePosting p) {
    final out = <String, ({Money debit, Money credit})>{};
    for (final l in p.journal.lines) {
      final key = l.isResolvedAccountId ? l.accountId : l.accountSystemKey;
      final prior = out[key] ?? (debit: Money.zero, credit: Money.zero);
      out[key] = (debit: prior.debit + l.debit, credit: prior.credit + l.credit);
    }
    return out;
  }

  group('a cash sale', () {
    test('debits the drawer and credits sales', () {
      final posting = post(
        SaleDraft(
          lines: [item(rate: Rate.rupees(5525))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(6000),
            ),
          ],
        ),
      );

      final accounts = byAccount(posting);
      expect(accounts['ACC-CASH']!.debit, Money.rupees(5525));
      expect(accounts['sales']!.credit, Money.rupees(5525));
      expect(accounts, hasLength(2));
      posting.assertBalanced();
    });

    test('records the change against the cash tender, not as revenue', () {
      // A till that posts the change it gave as revenue ends the day with more
      // money in the books than in the box.
      final posting = post(
        SaleDraft(
          lines: [item(rate: Rate.rupees(5525))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(6000),
              tendered: Money.rupees(6000),
            ),
          ],
        ),
      );
      expect(posting.payments.single.amount, Money.rupees(5525));
      expect(posting.payments.single.tendered, Money.rupees(6000));
      expect(posting.payments.single.change, Money.rupees(475));
    });
  });

  group('a credit sale', () {
    test('debits receivables for what is still owed', () {
      final posting = post(
        SaleDraft(
          partyId: 'P-BILAL',
          partyName: 'Bilal General Store',
          lines: [item(rate: Rate.rupees(5000))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(2000),
            ),
          ],
        ),
      );

      final accounts = byAccount(posting);
      expect(accounts['ACC-CASH']!.debit, Money.rupees(2000));
      expect(accounts['accounts_receivable']!.debit, Money.rupees(3000));
      expect(accounts['sales']!.credit, Money.rupees(5000));
      posting.assertBalanced();
    });

    test('tags the receivable line with the party', () {
      // Without this the party statement is a join through documents rather
      // than an indexed read of the sub-ledger.
      final posting = post(
        SaleDraft(
          partyId: 'P-BILAL',
          lines: [item(rate: Rate.rupees(5000))],
        ),
      );
      final receivable = posting.journal.lines
          .firstWhere((l) => l.accountSystemKey == 'accounts_receivable');
      expect(receivable.partyId, 'P-BILAL');
    });
  });

  group('discount', () {
    test('is a contra entry, so sales stays gross', () {
      // A shopkeeper who gives Rs 40,000 of riayat in a month needs to see
      // that number. Netting it off sales hides it forever.
      final posting = post(
        SaleDraft(
          lines: [item(rate: Rate.rupees(1000), discountBp: 1000)],
          roundToRupee: false,
        ),
      );
      final accounts = byAccount(posting);
      expect(accounts['sales']!.credit, Money.rupees(1000));
      expect(accounts['discount_given']!.debit, Money.rupees(100));
      expect(accounts['accounts_receivable']!.debit, Money.rupees(900));
      posting.assertBalanced();
    });

    test('a bill discount lands in the same contra account', () {
      final posting = post(
        SaleDraft(
          lines: [
            item(name: 'A', rate: Rate.rupees(500)),
            item(name: 'B', rate: Rate.rupees(500)),
          ],
          billDiscount: Money.rupees(50),
          roundToRupee: false,
        ),
      );
      expect(byAccount(posting)['discount_given']!.debit, Money.rupees(50));
      posting.assertBalanced();
    });
  });

  group('round-off', () {
    test('a bill rounded down debits round-off', () {
      final posting = post(
        SaleDraft(lines: [item(rate: Rate.parse('100.24'))]),
      );
      final accounts = byAccount(posting);
      expect(accounts['round_off']!.debit, Money.paisa(24));
      expect(accounts['round_off']!.credit, Money.zero);
      expect(accounts['sales']!.credit, Money.rupees(100, 24));
      posting.assertBalanced();
    });

    test('a bill rounded up credits round-off', () {
      final posting = post(
        SaleDraft(lines: [item(rate: Rate.parse('100.76'))]),
      );
      final accounts = byAccount(posting);
      expect(accounts['round_off']!.credit, Money.paisa(24));
      expect(accounts['round_off']!.debit, Money.zero);
      posting.assertBalanced();
    });
  });

  group('cost of goods', () {
    test('debits COGS and credits inventory', () {
      final posting = post(
        SaleDraft(
          lines: [
            item(qty: '2', rate: Rate.rupees(150), cost: Rate.rupees(110)),
          ],
        ),
      );
      final accounts = byAccount(posting);
      expect(accounts['cogs']!.debit, Money.rupees(220));
      expect(accounts['inventory']!.credit, Money.rupees(220));
      posting.assertBalanced();
    });

    test('posts no cost line when nothing has been purchased yet', () {
      final posting = post(SaleDraft(lines: [item(rate: Rate.rupees(150))]));
      expect(byAccount(posting).containsKey('cogs'), isFalse);
      expect(byAccount(posting).containsKey('inventory'), isFalse);
    });
  });

  group('tenders', () {
    test('a cheque waits in Cheques in Hand, not in the bank', () {
      // A cheque is not money until it clears. Treating it as bank on the day
      // it is taken is how a shop believes it has been paid twice.
      final posting = post(
        SaleDraft(
          lines: [item(rate: Rate.rupees(5000))],
          tenders: [
            TenderDraft(
              paymentAccountId: 'PA-BANK',
              mode: 'cheque',
              amount: Money.rupees(5000),
              chequeNo: '004411',
              chequeBank: 'Meezan',
              chequeDateUtc: DateTime.utc(2026, 9, 15),
            ),
          ],
        ),
      );
      final accounts = byAccount(posting);
      expect(accounts['cheques_in_hand']!.debit, Money.rupees(5000));
      expect(accounts.containsKey('ACC-BANK'), isFalse);
      expect(posting.payments.single.isCheque, isTrue);
      posting.assertBalanced();
    });

    test('a split tender debits each account separately', () {
      final posting = post(
        SaleDraft(
          lines: [item(rate: Rate.rupees(5000))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-BANK',
              mode: 'easypaisa',
              amount: Money.rupees(3000),
              reference: 'TID 88213',
            ),
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(2000),
            ),
          ],
        ),
      );
      final accounts = byAccount(posting);
      expect(accounts['ACC-BANK']!.debit, Money.rupees(3000));
      expect(accounts['ACC-CASH']!.debit, Money.rupees(2000));
      expect(posting.payments, hasLength(2));
      expect(posting.payments.first.reference, 'TID 88213');
      posting.assertBalanced();
    });

    test('refuses a tender against an unknown payment account', () {
      expect(
        () => post(
          SaleDraft(
            lines: [item(rate: Rate.rupees(100))],
            tenders: const [
              TenderDraft(
                paymentAccountId: 'PA-NOWHERE',
                mode: 'cash',
                amount: Money.rupees(100),
              ),
            ],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('stock', () {
    test('moves out of the shop, one movement per stocked line', () {
      final posting = post(
        SaleDraft(
          lines: [
            item(name: 'Oil', qty: '2', rate: Rate.rupees(2500)),
            SaleLineDraft(
              itemId: 'I-SERVICE',
              itemName: 'Home delivery',
              qty: Qty.one,
              baseQty: Qty.one,
              unitCode: 'pcs',
              rate: Rate.rupees(100),
              tracksStock: false,
            ),
          ],
        ),
      );
      expect(posting.stockMovements, hasLength(1));
      expect(posting.stockMovements.single.qtyDelta, Qty.units(-2));
      expect(posting.stockMovements.single.txnType, 'sale');
      expect(posting.stockMovements.single.locationCode, 'MAIN');
    });
  });

  group('the balance guarantee', () {
    test('assertBalanced catches an entry that does not add up', () {
      const broken = SalePosting(
        document: DocumentPosting(
          docType: 'sale_invoice',
          docNo: 'INV-2627-0001',
          docSeries: 'INV',
          docSeq: 1,
          fiscalYear: 2627,
          docDateUtcMillis: 0,
          docDateLocal: '2026-08-23',
          subtotal: Money.zero,
          lineDiscount: Money.zero,
          billDiscount: Money.zero,
          taxable: Money.zero,
          tax: Money.zero,
          furtherTax: Money.zero,
          withholding: Money.zero,
          extraCharges: Money.zero,
          roundOff: Money.zero,
          total: Money.zero,
          paid: Money.zero,
          balance: Money.zero,
          cost: Money.zero,
          roundingMode: 'half_up',
          taxRuleVersion: 'untaxed-v1',
          cashThresholdBreached: false,
        ),
        lines: [],
        payments: [],
        stockMovements: [],
        journal: JournalEntryPosting(
          entryNo: 'JV-2627-00001',
          entryDateUtcMillis: 0,
          entryDateLocal: '2026-08-23',
          fiscalYear: 2627,
          sourceType: 'sale',
          totalDebit: Money.rupees(100),
          totalCredit: Money.rupees(99),
          lines: [
            JournalLinePosting(
              lineNo: 1,
              accountSystemKey: 'cash_in_hand',
              debit: Money.rupees(100),
              credit: Money.zero,
            ),
            JournalLinePosting(
              lineNo: 2,
              accountSystemKey: 'sales',
              debit: Money.zero,
              // One rupee short. Not "within tolerance".
              credit: Money.rupees(99),
            ),
          ],
        ),
        auditSummary: 'x',
      );

      expect(
        broken.assertBalanced,
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('out by'),
          ),
        ),
      );
    });

    test('property: 1000 random sales all balance', () {
      final rng = Random(20260823);
      for (var i = 0; i < 1000; i++) {
        final count = 1 + rng.nextInt(4);
        final lines = [
          for (var j = 0; j < count; j++)
            SaleLineDraft(
              itemId: 'I$j',
              itemName: 'Item $j',
              qty: Qty.raw(1 + rng.nextInt(10000)),
              baseQty: Qty.raw(1 + rng.nextInt(10000)),
              unitCode: 'pcs',
              rate: Rate.raw(rng.nextInt(20000000)),
              discountBp: rng.nextInt(1500),
              unitCost: Rate.raw(rng.nextInt(10000000)),
            ),
        ];
        final roundToRupee = rng.nextBool();
        // Price it once with no tender, so the tender can be drawn against
        // what is actually owed rather than against the pre-discount subtotal
        // — a bank transfer for more than the bill is a mistake the calculator
        // is right to refuse, and it is not what this property is about.
        final owed = calculator
            .calculate(
              SaleDraft(lines: lines, roundToRupee: roundToRupee),
              untaxed,
            )
            .total;
        final paid = owed.isPositive
            ? Money.paisa(rng.nextInt(owed.inPaisa + 1))
            : Money.zero;

        final posting = post(
          SaleDraft(
            partyId: 'P-1',
            lines: lines,
            roundToRupee: roundToRupee,
            tenders: [
              if (paid.isPositive)
                TenderDraft(
                  paymentAccountId: rng.nextBool() ? 'PA-CASH' : 'PA-BANK',
                  mode: rng.nextBool() ? 'cash' : 'bank_transfer',
                  amount: paid,
                ),
            ],
          ),
        );
        // Throws if it does not balance, which is the assertion.
        posting.assertBalanced();
      }
    });
  });
}
