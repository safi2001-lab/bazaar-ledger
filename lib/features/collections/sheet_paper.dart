import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../l10n/app_strings.dart';

/// The recovery man's sheet on paper (M55): the receipt roll, a PDF, and a
/// WhatsApp message — the three ways it leaves the shop.
///
/// Laid out the way the paper sheet a wholesaler hands his man is: numbered,
/// one customer to a block, their phone and route to find them by, each
/// open bill with its number and date (the customer asks "kaun sa bill?"),
/// what is owed in all, and a line left blank for him to write what he was
/// given. Once his return is recorded the blank becomes what happened.

/// What became of a line, in words; null while the sheet is out.
String? resultWords(AppStrings s, SheetResult? result) {
  if (result == null) return null;
  final money = result.amount?.amountOnly;
  return switch (result.outcome) {
    CollectionOutcome.paid => s.sheetPaidLine(money ?? ''),
    CollectionOutcome.partial => s.sheetPartialLine(money ?? ''),
    CollectionOutcome.promise =>
      money == null
          ? s.sheetPromiseLine(shortDate(result.promisedFor ?? ''))
          : s.sheetPromiseAmountLine(
              shortDate(result.promisedFor ?? ''),
              money,
            ),
    CollectionOutcome.shopClosed => s.outcomeShopClosed,
    CollectionOutcome.refused => s.outcomeRefused,
  };
}

/// The sheet as plain lines [width] characters wide: for the receipt
/// printer (32 columns on 58mm, 48 on 80mm) and, at any width, for a
/// message.
///
/// Plain spaces and ASCII marks only: a receipt printer's own font has no
/// middle dot, and a name in Urdu script comes out of it as question marks
/// (the PDF prints it).
List<({String text, bool bold, bool centred})> sheetSlip(
  AppStrings s,
  CollectionSheet sheet, {
  required int width,
  String shopName = '',
}) {
  ({String text, bool bold, bool centred}) line(
    String text, {
    bool bold = false,
    bool centred = false,
  }) => (text: _cut(text, width), bold: bold, centred: centred);
  final rule = line('-' * width);

  return [
    if (shopName.isNotEmpty) line(shopName, bold: true, centred: true),
    line('${s.sheetPaperTitle} ${sheet.sheetNo}', bold: true, centred: true),
    line(shortDate(sheet.dateLocal), centred: true),
    line(s.sheetCollectorLine(sheet.collector), centred: true),
    if (sheet.title case final title?) line(title, centred: true),
    rule,
    for (final l in sheet.lines) ...[
      line(
        _pair('${l.lineNo}. ${l.partyName}', l.due.amountOnly, width),
        bold: true,
      ),
      if ([?l.phone, ?l.group].isNotEmpty)
        line('   ${[?l.phone, ?l.group].join('  ')}'),
      for (final b in l.bills)
        line(
          _pair(
            '   ${b.docNo} ${shortDate(b.dateLocal)}',
            b.outstanding.amountOnly,
            width,
          ),
        ),
      if (l.earlier.isPositive)
        line(_pair('   ${s.partyOpeningBalance}', l.earlier.amountOnly, width)),
      if (l.unpriced > 0) line('   ${s.goodsGivenUnpriced(l.unpriced)}'),
      line(
        '   ${resultWords(s, l.result) ?? '${s.sheetPaperGot} ${'_' * (width - s.sheetPaperGot.length - 5).clamp(4, 24)}'}',
      ),
      rule,
    ],
    line(_pair(s.sheetExpected, sheet.expected.amountOnly, width), bold: true),
    if (sheet.isSettled) ...[
      line(_pair(s.sheetCollected, sheet.collected.amountOnly, width)),
      line(_pair(s.sheetCash, sheet.cashToHandOver.amountOnly, width)),
    ],
    rule,
  ];
}

/// The sheet as a WhatsApp message to the recovery man.
String sheetMessage(AppStrings s, CollectionSheet sheet, {String shop = ''}) =>
    [
      for (final l in sheetSlip(s, sheet, width: 40, shopName: shop))
        if (!l.text.startsWith('---')) l.text.trimRight(),
    ].join('\n');

/// The sheet as a table, for the PDF.
ReportTable sheetTable(AppStrings s, CollectionSheet sheet) => ReportTable(
  id: 'collection_sheet_${sheet.sheetNo}',
  title: '${s.sheetPaperTitle} ${sheet.sheetNo}',
  period: ReportPeriod.day(BusinessDate(sheet.dateLocal)),
  filters: [s.sheetCollectorLine(sheet.collector), ?sheet.title],
  columns: [
    ReportColumn(s.sheetColumnNo, CellKind.count),
    ReportColumn(s.sheetColumnCustomer, CellKind.text),
    ReportColumn(s.sheetColumnBills, CellKind.text),
    ReportColumn(s.sheetExpected, CellKind.money),
    ReportColumn(s.sheetColumnResult, CellKind.text),
    ReportColumn(s.sheetCollected, CellKind.money),
  ],
  rows: [
    for (final l in sheet.lines)
      ReportRow([
        l.lineNo,
        [l.partyName, ?l.phone, ?l.group].join('\n'),
        [
          for (final b in l.bills)
            '${b.docNo} ${shortDate(b.dateLocal)} ${b.outstanding.amountOnly}',
          if (l.earlier.isPositive)
            '${s.partyOpeningBalance} ${l.earlier.amountOnly}',
          if (l.unpriced > 0) s.goodsGivenUnpriced(l.unpriced),
        ].join('\n'),
        l.due,
        resultWords(s, l.result) ?? '',
        l.result?.received,
      ]),
    ReportRow([
      null,
      s.priceGoodsTotal,
      null,
      sheet.expected,
      null,
      sheet.isSettled ? sheet.collected : null,
    ], style: RowStyle.total),
  ],
  notes: [
    if (sheet.isSettled) ...[
      '${s.sheetCash}: ${sheet.cashToHandOver.amountOnly}',
      if (sheet.settledBy case final by?) s.sheetSettledBy(by),
    ],
  ],
);

/// [left] and [right] on one line, the right hard against the edge.
String _pair(String left, String right, int width) {
  final room = width - right.length - 1;
  if (room <= 0) return _cut(right, width);
  final l = left.length > room ? left.substring(0, room) : left;
  return '$l${' ' * (width - l.length - right.length)}$right';
}

String _cut(String text, int width) =>
    text.length > width ? text.substring(0, width) : text;
