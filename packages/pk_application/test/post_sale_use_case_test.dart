import 'package:pk_application/pk_application.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The use case, exercised with no database at all.
///
/// This is what the port boundary buys: the orchestration, the ordering, the
/// cost lookup and the balance assertion are all provable in milliseconds
/// against a fake, and the drift integration test above is then free to be
/// about persistence rather than about arithmetic.
void main() {
  late _FakeWriter writer;
  late PostSaleUseCase postSale;
  late ActorContext actor;

  setUp(() {
    writer = _FakeWriter();
    postSale = PostSaleUseCase(writer: writer);
    actor = ActorContext(
      firmId: 'F1',
      userId: 'U1',
      deviceId: 'D1',
      startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
    );
  });

  SaleDraft draft({
    List<TenderDraft> tenders = const [],
    String? partyId,
    Rate? explicitCost,
  }) =>
      SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: 'I-OIL',
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
            unitCost: explicitCost ?? Rate.zero,
          ),
          SaleLineDraft(
            itemId: 'I-MUTTON',
            itemName: 'Mutton',
            qty: Qty.parse('3.5'),
            baseQty: Qty.parse('3.5'),
            unitCode: 'kg',
            rate: Rate.rupees(150),
          ),
        ],
        tenders: tenders,
      );

  test('posts a balanced entry and returns what was written', () async {
    final result = await postSale(
      actor,
      draft(
        tenders: const [
          TenderDraft(
            paymentAccountId: 'PA-CASH',
            mode: 'cash',
            amount: Money.rupees(6000),
          ),
        ],
      ),
    );

    expect(result.docNo, 'INV-2627-0001');
    expect(result.total, Money.rupees(5525));
    expect(result.change, Money.rupees(475));
    expect(result.balance, Money.zero);

    final posting = writer.applied.single;
    posting.assertBalanced();
    expect(posting.document.total, Money.rupees(5525));
    expect(posting.lines, hasLength(2));
    expect(posting.payments, hasLength(1));
    expect(posting.stockMovements, hasLength(2));
  });

  test('everything happens inside one transaction', () async {
    await postSale(actor, draft());
    expect(writer.transactions, 1);
    // The write is the last thing that happens, after every number has been
    // allocated and the entry has been proved to balance.
    expect(writer.applyHappenedAfterNumbering, isTrue);
  });

  test('pulls cost from the ledger when the line does not carry one',
      () async {
    writer.costs['I-OIL'] = Rate.rupees(2000);
    writer.costs['I-MUTTON'] = Rate.rupees(110);

    await postSale(actor, draft());

    final posting = writer.applied.single;
    // Rs 2,000 x 2 plus Rs 110 x 3.5.
    expect(posting.document.cost, Money.rupees(4385));
    expect(posting.stockMovements[0].valueDelta, Money.rupees(-4000));
    expect(posting.stockMovements[1].valueDelta, Money.rupees(-385));
  });

  test('a cost typed on the line beats the ledger average', () async {
    writer.costs['I-OIL'] = Rate.rupees(2000);
    await postSale(actor, draft(explicitCost: Rate.rupees(2200)));
    expect(writer.applied.single.lines.first.cost, Money.rupees(4400));
  });

  test('allocates one number per tender, plus invoice and journal', () async {
    await postSale(
      actor,
      draft(
        tenders: const [
          TenderDraft(
            paymentAccountId: 'PA-BANK',
            mode: 'easypaisa',
            amount: Money.rupees(3000),
          ),
          TenderDraft(
            paymentAccountId: 'PA-CASH',
            mode: 'cash',
            amount: Money.rupees(2525),
          ),
        ],
      ),
    );
    expect(
      writer.requestedNumbers,
      ['sale_invoice', 'journal_entry', 'payment_in', 'payment_in'],
    );
  });

  test('refuses to post when a tender names an unknown payment account',
      () async {
    writer.knownAccounts.remove('PA-CASH');
    await expectLater(
      postSale(
        actor,
        draft(
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(6000),
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(writer.applied, isEmpty);
  });

  test('a writer failure is not swallowed', () async {
    // A use case that caught this and returned normally would be the previous
    // build's SnackBar all over again: a success message over a write that
    // never happened.
    writer.failOnApply = true;
    await expectLater(
      postSale(
        actor,
        draft(
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(6000),
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

/// A [SaleWriter] that remembers what it was asked to do.
class _FakeWriter implements SaleWriter {
  final List<SalePosting> applied = [];
  final List<String> requestedNumbers = [];
  final Map<String, Rate> costs = {};
  final Set<String> knownAccounts = {'PA-CASH', 'PA-BANK'};
  bool failOnApply = false;

  int transactions = 0;
  bool applyHappenedAfterNumbering = false;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) async {
    transactions++;
    return body(_FakeContext(this, actor));
  }
}

class _FakeContext implements SaleWriteContext {
  _FakeContext(this._writer, this.actor);

  final _FakeWriter _writer;

  @override
  final ActorContext actor;

  var _sequence = 0;

  @override
  Future<TaxContext> taxContextFor(String? partyId) async => const TaxContext(
        isSellerRegistered: false,
        buyerIsRegistered: false,
        buyerIsOnAtl: null,
        province: 'punjab',
        pricesIncludeTax: false,
        ruleVersion: 'untaxed-v1',
      );

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    _writer.requestedNumbers.add(docType);
    final series = switch (docType) {
      'sale_invoice' => 'INV',
      'journal_entry' => 'JV',
      _ => 'RCV',
    };
    final n = ++_sequence;
    return AllocatedNumber(
      formatted: '$series-2627-${n.toString().padLeft(4, '0')}',
      series: series,
      sequence: n,
    );
  }

  @override
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) async => {
        for (final id in itemIds)
          if (_writer.costs[id] != null) id: _writer.costs[id]!,
      };

  @override
  Future<Map<String, String>> ledgerAccountsFor(Iterable<String> ids) async => {
        for (final id in ids)
          if (_writer.knownAccounts.contains(id)) id: 'ACC-$id',
      };

  @override
  Future<PostedSale> apply(SalePosting posting) async {
    if (_writer.failOnApply) {
      throw StateError('the disk is full');
    }
    _writer.applyHappenedAfterNumbering = _writer.requestedNumbers.isNotEmpty;
    _writer.applied.add(posting);
    return PostedSale(
      documentId: 'DOC-1',
      docNo: posting.document.docNo,
      total: posting.document.total,
      paid: posting.document.paid,
      balance: posting.document.balance,
      change: Money.sum([for (final p in posting.payments) p.change]),
      journalEntryId: 'JE-1',
      paymentIds: [for (final _ in posting.payments) 'PAY'],
    );
  }
}
