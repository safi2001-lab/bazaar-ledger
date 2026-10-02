import 'package:pk_domain/pk_domain.dart';

import 'expense_source.dart';
import 'period.dart';
import 'report_table.dart';

/// The expense reports (M35): every voucher, the totals by head with the
/// direct costs kept apart from the overheads, and what the money went on
/// within each head. All three read the same vouchers, so their totals are
/// one figure.
///
/// Since M58 none of them counts the home's spending (M47). Ghar ka kharcha,
/// in money or in goods taken home, is the owner's drawings: the profit and
/// loss never sees it, and an expense report that added it in would tell the
/// owner the shop spent what his family did. It is shown apart instead, as a
/// tile and a line under the table, so the drawer's money can still be
/// followed.

/// The shop's vouchers out of [vouchers], and the tile and note that show
/// the home's apart.
({List<ExpenseVoucher> shop, List<ReportFigure> tiles, List<String> notes})
_homeApart(List<ExpenseVoucher> vouchers) {
  final home = [
    for (final v in vouchers)
      if (v.forHome) v,
  ];
  if (home.isEmpty) return (shop: vouchers, tiles: const [], notes: const []);
  final taken = Money.sum(home.map((v) => v.amount));
  final goods = Money.sum([
    for (final v in home)
      if (v.goods) v.amount,
  ]);
  final entries = home.length == 1 ? '1 entry' : '${home.length} entries';
  final ofIt = goods.isZero
      ? ''
      : ', Rs ${goods.amountOnly} of it goods taken home at cost';
  final note =
      'Ghar ka kharcha, $entries for Rs ${taken.amountOnly}$ofIt, is the '
      "owner's drawings, not the shop's expense: it is left out of every "
      'figure here, as it is out of the profit and loss.';
  return (
    shop: [
      for (final v in vouchers)
        if (!v.forHome) v,
    ],
    tiles: [ReportFigure(homeTile, taken)],
    notes: [note],
  );
}

/// The tile the home's spending is shown apart under (M58).
const homeTile = "Owner's drawings (ghar)";

/// Every expense voucher in [period], in date order.
ReportTable expenseTransactions(ReportPeriod period, List<ExpenseVoucher> all) {
  final apart = _homeApart(all);
  final vouchers = apart.shop;
  final total = Money.sum(vouchers.map((v) => v.amount));
  final owed = Money.sum(vouchers.map((v) => v.balance));
  return ReportTable(
    id: 'expense_transactions',
    title: 'Expense transactions',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('Paid to', CellKind.text),
      ReportColumn('Head', CellKind.text),
      ReportColumn('Paid from', CellKind.text),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Still owed', CellKind.money),
      ReportColumn('Note', CellKind.text),
      ReportColumn('Entered by', CellKind.text),
    ],
    rows: [
      for (final v in vouchers)
        ReportRow(
          [
            v.date.value,
            v.docNo,
            v.party ?? '',
            v.head,
            v.paidFrom,
            v.amount,
            v.balance,
            v.note,
            v.enteredBy ?? '',
          ],
          link: ReportLink.document(
            v.documentId,
            label: v.docNo,
            docType: 'expense',
          ),
        ),
      ReportRow([
        'Total',
        vouchers.length == 1 ? '1 voucher' : '${vouchers.length} vouchers',
        null,
        null,
        null,
        total,
        owed,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Expenses', total),
      ReportFigure.count('Vouchers', vouchers.length),
      ReportFigure('Still owed', owed),
      ...apart.tiles,
    ],
    notes: [_vouchersNote, ...apart.notes],
  );
}

const _vouchersNote =
    'Expense vouchers that stand: an edited one is here as it now reads, '
    'and a cancelled one is not here at all.';

/// What was spent under each head over [period], the direct costs apart
/// from the overheads, largest first within each.
ReportTable expenseCategories(ReportPeriod period, List<ExpenseVoucher> all) {
  final apart = _homeApart(all);
  final vouchers = apart.shop;
  final heads = <String, _Head>{};
  for (final v in vouchers) {
    heads.putIfAbsent(v.headId, () => _Head(v.head, isDirect: v.isDirect))
      ..count += 1
      ..amount += v.amount;
  }
  final total = Money.sum(vouchers.map((v) => v.amount));
  List<_Head> part({required bool direct}) =>
      heads.values.where((h) => h.isDirect == direct).toList()..sort((a, b) {
        final byAmount = b.amount.compareTo(a.amount);
        return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
      });
  final direct = part(direct: true);
  final indirect = part(direct: false);
  final directTotal = Money.sum(direct.map((h) => h.amount));
  final indirectTotal = Money.sum(indirect.map((h) => h.amount));

  List<ReportRow> section(String title, List<_Head> hs, Money subtotal) => [
    ReportRow.heading(title, 4),
    for (final h in hs)
      ReportRow([h.name, h.count, h.amount, shareBp(h.amount, total)]),
    ReportRow([
      'Total ${title.toLowerCase()}',
      hs.fold<int>(0, (n, h) => n + h.count),
      subtotal,
      shareBp(subtotal, total),
    ], style: RowStyle.subtotal),
  ];

  return ReportTable(
    id: 'expense_categories',
    title: 'Expense categories',
    period: period,
    columns: const [
      ReportColumn('Head', CellKind.text),
      ReportColumn('Vouchers', CellKind.count),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Share', CellKind.percent),
    ],
    rows: [
      if (direct.isNotEmpty) ...section('Direct expenses', direct, directTotal),
      if (indirect.isNotEmpty)
        ...section('Indirect expenses', indirect, indirectTotal),
      ReportRow([
        'Total',
        vouchers.length,
        total,
        total.isZero ? 0 : 10000,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Direct', directTotal),
      ReportFigure('Indirect', indirectTotal),
      ReportFigure('Total', total),
      ...apart.tiles,
    ],
    notes: [_categoriesNote, ...apart.notes],
  );
}

const _categoriesNote =
    'Direct expenses are part of what the goods cost (freight in, '
    'production); the rest are the shop\'s overheads. These are the '
    'vouchers; Expenses by head reads the books, and so also counts stock '
    'written off and cash short at a day close.';

final class _Head {
  _Head(this.name, {required this.isDirect});

  final String name;
  final bool isDirect;
  int count = 0;
  Money amount = Money.zero;
}

/// What the money went on within each head over [period] (M35).
///
/// The books keep no expense items: a voucher is a head and a line in the
/// shopkeeper's words, which the voucher form insists on. So the item here
/// is that line, read without regard to capitals, spacing or a full stop at
/// the end, within its head: "Bijli bill", "bijli  bill." and "BIJLI BILL"
/// are one item under Utilities, and the wording of the latest is the one
/// shown.
ReportTable expenseItems(ReportPeriod period, List<ExpenseVoucher> all) {
  final apart = _homeApart(all);
  final vouchers = apart.shop;
  final items = <(String, String), _Item>{};
  for (final v in vouchers) {
    final key = (v.headId, expenseItemKey(v.note));
    final item = items.putIfAbsent(key, () => _Item(v.head, v.note));
    item
      ..count += 1
      ..amount += v.amount;
    if (v.date.value.compareTo(item.last.value) >= 0) {
      item
        ..last = v.date
        ..wording = v.note.trim();
    }
  }
  final headTotals = <String, Money>{};
  for (final i in items.values) {
    headTotals[i.head] = (headTotals[i.head] ?? Money.zero) + i.amount;
  }
  final rows = items.values.toList()
    ..sort((a, b) {
      final byHead = headTotals[b.head]!.compareTo(headTotals[a.head]!);
      if (byHead != 0) return byHead;
      final byName = a.head.compareTo(b.head);
      if (byName != 0) return byName;
      final byAmount = b.amount.compareTo(a.amount);
      return byAmount != 0 ? byAmount : a.wording.compareTo(b.wording);
    });
  final total = Money.sum(rows.map((i) => i.amount));
  return ReportTable(
    id: 'expense_items',
    title: 'Expense items',
    period: period,
    columns: const [
      ReportColumn('Head', CellKind.text),
      ReportColumn('Spent on', CellKind.text),
      ReportColumn('Times', CellKind.count),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Share of head', CellKind.percent),
      ReportColumn('Last on', CellKind.text),
    ],
    rows: [
      for (final i in rows)
        ReportRow([
          i.head,
          i.wording,
          i.count,
          i.amount,
          shareBp(i.amount, headTotals[i.head]!),
          i.last.value,
        ]),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 item' : '${rows.length} items',
        vouchers.length,
        total,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Expenses', total),
      ReportFigure.count('Items', rows.length),
      ...apart.tiles,
    ],
    notes: [_itemsNote, ...apart.notes],
  );
}

const _itemsNote =
    'An item is what the voucher says it was for, within its head, with '
    'capitals, spacing and a closing full stop ignored. The books keep no '
    'expense items of their own.';

/// [note] as the item it names: lower case, spaces closed up, a trailing
/// full stop dropped.
String expenseItemKey(String note) => note
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[.\s]+$'), '');

final class _Item {
  _Item(this.head, String note) : wording = note.trim();

  final String head;
  String wording;
  int count = 0;
  Money amount = Money.zero;
  BusinessDate last = const BusinessDate('0000-01-01');
}
