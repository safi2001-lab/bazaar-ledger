import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'party_source.dart';
import 'period.dart';
import 'report_table.dart';

/// The party reports (M33): a party's statement, profit by party, every
/// party's balance, what a party bought and sold by item, and trade by party
/// and by party group. Pure builders, like every other report: each total
/// is on the table before the screen or an export sees it.

/// One side of a party's account over [period], as statement rows: the
/// balance brought forward, every entry in the period with the balance after
/// it, and the balance at the end (M24, shared with the party reports in
/// M33).
///
/// [entries] is the whole ledger, oldest first, as the khata reads it; the
/// opening is the balance after the last entry before the period. Amounts
/// that add to the balance go in the first money column when
/// [increasesFirst], or the second: a supplier's delivery is a credit to
/// their account, and on a statement holding both sides it sits under Credit.
({List<ReportRow> rows, Money opening, Money closing}) statementSection({
  required ReportPeriod period,
  required List<LedgerEntry> entries,
  required bool owedToUs,
  bool increasesFirst = true,
  RowStyle closingStyle = RowStyle.total,
}) {
  final before = entries
      .where((e) => e.dateLocal.compareTo(period.from.value) < 0)
      .toList();
  final opening = before.isEmpty ? Money.zero : before.last.balanceAfter;
  final within = entries
      .where((e) => period.contains(BusinessDate(e.dateLocal)))
      .toList();
  final closing = within.isEmpty ? opening : within.last.balanceAfter;
  final up = Money.sum([
    for (final e in within)
      if (!e.amount.isNegative) e.amount,
  ]);
  final down = -Money.sum([
    for (final e in within)
      if (e.amount.isNegative) e.amount,
  ]);

  List<Object?> money(Money? increase, Money? decrease) =>
      increasesFirst ? [increase, decrease] : [decrease, increase];

  return (
    opening: opening,
    closing: closing,
    rows: [
      ReportRow([
        period.from.value,
        'Opening balance',
        '',
        null,
        null,
        opening,
      ], style: RowStyle.subtotal),
      for (final e in within)
        ReportRow([
          e.dateLocal,
          _entryLabel(e.kind, owedToUs: owedToUs),
          e.reference,
          ...money(
            e.amount.isNegative ? null : e.amount,
            e.amount.isNegative ? -e.amount : null,
          ),
          e.balanceAfter,
        ], link: _entryLink(e, owedToUs: owedToUs)),
      ReportRow([
        period.to.value,
        owedToUs ? 'Balance owed to us' : 'Balance we owe',
        '',
        ...money(up, down),
        closing,
      ], style: closingStyle),
    ],
  );
}

String _entryLabel(String kind, {required bool owedToUs}) => switch (kind) {
  'sale' => 'Bill',
  'charge' => 'Charge',
  'payment' => 'Payment',
  'bounce' => 'Cheque bounced',
  'purchase' => 'Delivery',
  'expense' => 'Expense',
  'opening' => 'Opening balance',
  'return' => owedToUs ? 'Goods returned' : 'Goods sent back',
  _ => kind,
};

ReportLink? _entryLink(LedgerEntry e, {required bool owedToUs}) {
  final docType = switch (e.kind) {
    'sale' => 'sale_invoice',
    'charge' => 'other_income',
    'purchase' => 'purchase_bill',
    'expense' => 'expense',
    'return' => owedToUs ? 'sale_return' : 'purchase_return',
    _ => null,
  };
  if (docType == null) return null;
  return ReportLink.document(e.id, label: e.reference, docType: docType);
}

/// A party's statement for the report pack (M33): their account over
/// [period] from the same ledger the khata reads, with every bill, payment,
/// charge, bounced cheque and return and the balance after each.
///
/// A party the shop both sells to and buys from has two accounts, and they
/// are shown as two sections, never netted: the two debts are settled
/// separately, each against its own bills, and "owes the shop Rs 15,000" is
/// a figure neither side agreed to.
ReportTable partyStatementReport({
  required ReportPeriod period,
  required PartyLedgers? ledgers,
}) {
  const columns = [
    ReportColumn('Date', CellKind.text),
    ReportColumn('Details', CellKind.text),
    ReportColumn('Reference', CellKind.text),
    ReportColumn('Debit', CellKind.money),
    ReportColumn('Credit', CellKind.money),
    ReportColumn('Balance', CellKind.money),
  ];
  if (ledgers == null) {
    return ReportTable(
      id: 'party_statement',
      title: 'Party statement',
      period: period,
      columns: columns,
      rows: const [],
      notes: const [_chooseAParty],
    );
  }

  final customer =
      ledgers.receivable.isNotEmpty || ledgers.partyType != 'supplier';
  final supplier =
      ledgers.payable.isNotEmpty || ledgers.partyType == 'supplier';
  final both = customer && supplier;

  final theyOwe = customer
      ? statementSection(
          period: period,
          entries: ledgers.receivable,
          owedToUs: true,
        )
      : null;
  final weOwe = supplier
      ? statementSection(
          period: period,
          entries: ledgers.payable,
          owedToUs: false,
          increasesFirst: false,
        )
      : null;

  return ReportTable(
    id: 'party_statement',
    title: 'Party statement: ${ledgers.name}',
    period: period,
    columns: columns,
    rows: [
      if (theyOwe != null) ...[
        if (both) ReportRow.heading('What they owe the shop', columns.length),
        ...theyOwe.rows,
      ],
      if (weOwe != null) ...[
        if (both) ReportRow.heading('What the shop owes them', columns.length),
        ...weOwe.rows,
      ],
    ],
    summary: [
      if (theyOwe != null) ...[
        ReportFigure('Opening balance', theyOwe.opening),
        ReportFigure('Owed to us', theyOwe.closing),
      ],
      if (weOwe != null) ...[
        if (theyOwe == null) ReportFigure('Opening balance', weOwe.opening),
        ReportFigure('We owe', weOwe.closing),
      ],
    ],
    notes: [
      if (theyOwe != null && theyOwe.closing.isNegative)
        'A minus balance owed to us is an advance: we owe it back.',
      if (weOwe != null && weOwe.closing.isNegative)
        'A minus balance we owe is an advance we have paid them.',
      if (both) _twoAccounts,
    ],
  );
}

const _chooseAParty = 'Choose a party to see their statement.';

const _twoAccounts =
    'They buy from the shop and sell to it, and the two accounts are kept '
    'apart: each is settled against its own bills.';

/// Profit by party over [period] (M33): what each customer's bills came to
/// before tax, less returns, against what the goods cost when they left the
/// shelf. Walk-in customers are one row between them. Most profitable
/// first.
ReportTable partyProfitAndLoss(ReportPeriod period, List<PartyTrade> trades) {
  final rows =
      trades
          .where((t) => !t.netSalesTaxable.isZero || !t.netCost.isZero)
          .toList()
        ..sort((a, b) {
          final byProfit = b.profit.compareTo(a.profit);
          return byProfit != 0 ? byProfit : a.name.compareTo(b.name);
        });
  final sales = Money.sum(rows.map((t) => t.netSalesTaxable));
  final cost = Money.sum(rows.map((t) => t.netCost));
  final profit = sales - cost;
  return ReportTable(
    id: 'party_profit_and_loss',
    title: 'Party-wise profit and loss',
    period: period,
    columns: const [
      ReportColumn('Party', CellKind.text),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Cost', CellKind.money, isCost: true),
      ReportColumn('Profit', CellKind.money, isCost: true),
      ReportColumn('Margin', CellKind.percent, isCost: true),
    ],
    rows: [
      for (final t in rows)
        ReportRow([
          t.name,
          t.netSalesTaxable,
          t.netCost,
          t.profit,
          shareBp(t.profit, t.netSalesTaxable),
        ], link: _partyLink(t.partyId, t.name)),
      ReportRow([
        'Total',
        sales,
        cost,
        profit,
        shareBp(profit, sales),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Cost', cost),
      ReportFigure('Profit', profit),
    ],
    notes: const [_salesBeforeTax],
  );
}

const _salesBeforeTax =
    'Sales are before tax and after every discount, less returns. Cost is '
    'what the goods cost when they left the shelf, less what came back.';

ReportLink? _partyLink(String? partyId, String name) =>
    partyId == null ? null : ReportLink.party(partyId, label: name);

/// Every party on the books with what the khata says each way, as of
/// [asOf] (M33). [withBalanceOnly] leaves out the settled.
ReportTable allParties(
  BusinessDate asOf,
  List<PartyBalanceRow> parties, {
  bool withBalanceOnly = false,
}) {
  final rows = parties.where((p) => !withBalanceOnly || p.hasBalance).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final receivable = Money.sum(rows.map((p) => p.receivable));
  final payable = Money.sum(rows.map((p) => p.payable));
  return ReportTable(
    id: 'all_parties',
    title: 'All parties',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Party', CellKind.text),
      ReportColumn('Type', CellKind.text),
      ReportColumn('Group', CellKind.text),
      ReportColumn('Phone', CellKind.text),
      ReportColumn('To receive', CellKind.money),
      ReportColumn('To pay', CellKind.money),
      ReportColumn('Credit limit', CellKind.money),
    ],
    rows: [
      for (final p in rows)
        ReportRow([
          p.name,
          _partyType(p.partyType),
          p.group ?? '',
          p.phone ?? '',
          p.receivable,
          p.payable,
          p.creditLimit,
        ], link: ReportLink.party(p.partyId, label: p.name)),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 party' : '${rows.length} parties',
        null,
        null,
        receivable,
        payable,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('To receive', receivable),
      ReportFigure('To pay', payable),
    ],
    notes: const [_khataFigures],
  );
}

const _khataFigures =
    'To receive is the figure on each khata: opening balance, bills and '
    'charges still open, less any advance. To pay is deliveries and expenses '
    'left on account. The two are never netted.';

String _partyType(String type) => switch (type) {
  'customer' => 'Customer',
  'supplier' => 'Supplier',
  'both' => 'Both',
  _ => type,
};

/// What one party bought from the shop and sold to it over [period], item
/// by item, net of returns (M33); every party's together when [partyName]
/// is null.
ReportTable partyItemsReport(
  ReportPeriod period,
  List<PartyItemTrade> items, {
  String? partyName,
}) {
  final rows =
      items
          .where(
            (i) =>
                !i.qtySold.isZero ||
                !i.saleAmount.isZero ||
                !i.qtyPurchased.isZero ||
                !i.purchaseAmount.isZero,
          )
          .toList()
        ..sort((a, b) {
          final bySales = b.saleAmount.compareTo(a.saleAmount);
          return bySales != 0 ? bySales : a.itemName.compareTo(b.itemName);
        });
  final sold = Money.sum(rows.map((i) => i.saleAmount));
  final bought = Money.sum(rows.map((i) => i.purchaseAmount));
  return ReportTable(
    id: 'party_items',
    title: partyName == null
        ? 'Party report by items'
        : 'Party report by items: $partyName',
    period: period,
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Sold qty', CellKind.qty),
      ReportColumn('Sale amount', CellKind.money),
      ReportColumn('Bought qty', CellKind.qty),
      ReportColumn('Purchase amount', CellKind.money),
    ],
    rows: [
      for (final i in rows)
        ReportRow([
          i.itemName,
          i.unitCode,
          i.qtySold,
          i.saleAmount,
          i.qtyPurchased,
          i.purchaseAmount,
        ]),
      ReportRow([
        'Total',
        null,
        null,
        sold,
        null,
        bought,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sale amount', sold),
      ReportFigure('Purchase amount', bought),
    ],
    notes: const [_amountsBeforeTax],
  );
}

const _amountsBeforeTax =
    'Amounts are before tax and after every discount, less returns. '
    'Quantities are in each item\'s base unit.';

/// What the shop sold to and bought from each party over [period], tax
/// included and net of returns (M33). Largest trade first.
ReportTable salePurchaseByParty(ReportPeriod period, List<PartyTrade> trades) {
  final rows =
      trades.where((t) => !t.netSales.isZero || !t.netPurchases.isZero).toList()
        ..sort((a, b) {
          final bySales = b.netSales.compareTo(a.netSales);
          if (bySales != 0) return bySales;
          final byPurchases = b.netPurchases.compareTo(a.netPurchases);
          return byPurchases != 0 ? byPurchases : a.name.compareTo(b.name);
        });
  final sales = Money.sum(rows.map((t) => t.netSales));
  final purchases = Money.sum(rows.map((t) => t.netPurchases));
  return ReportTable(
    id: 'sale_purchase_by_party',
    title: 'Sale and purchase by party',
    period: period,
    columns: const [
      ReportColumn('Party', CellKind.text),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Purchases', CellKind.money),
    ],
    rows: [
      for (final t in rows)
        ReportRow([
          t.name,
          t.netSales,
          t.netPurchases,
        ], link: _partyLink(t.partyId, t.name)),
      ReportRow(['Total', sales, purchases], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Purchases', purchases),
    ],
    notes: const [_withTaxLessReturns],
  );
}

const _withTaxLessReturns =
    'Bills as handed over, tax included, less what came back either way.';

/// The same trade summed by party group (M33). A party with no group is
/// counted under Ungrouped, and the walk-in customers under their own row.
ReportTable salePurchaseByPartyGroup(
  ReportPeriod period,
  List<PartyTrade> trades,
) {
  final groups = <String, ({int parties, Money sales, Money purchases})>{};
  for (final t in trades) {
    if (t.netSales.isZero && t.netPurchases.isZero) continue;
    final name = t.partyId == null
        ? _walkIns
        : (t.group == null || t.group!.trim().isEmpty)
        ? _ungrouped
        : t.group!.trim();
    final was = groups[name];
    groups[name] = (
      parties: (was?.parties ?? 0) + (t.partyId == null ? 0 : 1),
      sales: (was?.sales ?? Money.zero) + t.netSales,
      purchases: (was?.purchases ?? Money.zero) + t.netPurchases,
    );
  }
  final names = groups.keys.toList()
    ..sort((a, b) {
      final bySales = groups[b]!.sales.compareTo(groups[a]!.sales);
      return bySales != 0 ? bySales : a.compareTo(b);
    });
  final sales = Money.sum(groups.values.map((g) => g.sales));
  final purchases = Money.sum(groups.values.map((g) => g.purchases));
  return ReportTable(
    id: 'sale_purchase_by_party_group',
    title: 'Sale and purchase by party group',
    period: period,
    columns: const [
      ReportColumn('Group', CellKind.text),
      ReportColumn('Parties', CellKind.count),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Purchases', CellKind.money),
    ],
    rows: [
      for (final n in names)
        ReportRow([
          n,
          groups[n]!.parties,
          groups[n]!.sales,
          groups[n]!.purchases,
        ]),
      ReportRow([
        'Total',
        groups.values.fold<int>(0, (n, g) => n + g.parties),
        sales,
        purchases,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Purchases', purchases),
    ],
    notes: const [_withTaxLessReturns],
  );
}

const _ungrouped = ReportFilters.ungrouped;
const _walkIns = 'Walk-in customers';
