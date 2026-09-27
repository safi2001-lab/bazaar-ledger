import 'package:pk_money/pk_money.dart';

import 'spreadsheet.dart';

/// One thing the import could not take, and why.
final class ImportProblem {
  const ImportProblem(this.line, this.message);

  /// The row as the spreadsheet numbers it, heading row included.
  final int line;
  final String message;

  @override
  String toString() => 'Row $line: $message';
}

/// What a sheet will bring in, before anything is written.
final class ImportPlan<T> {
  const ImportPlan({
    required this.rows,
    required this.problems,
    required this.columns,
  });

  /// Rows ready to import, with the spreadsheet row each came from.
  final List<(int, T)> rows;

  final List<ImportProblem> problems;

  /// Which heading each field was read from, for the preview to show.
  final Map<String, String> columns;
}

/// An item from a sheet.
final class ItemRow {
  const ItemRow({
    required this.name,
    required this.salePrice,
    this.purchasePrice,
    this.openingStock = Qty.zero,
    this.minStock = Qty.zero,
    this.barcode,
    this.code,
    this.unit,
    this.category,
    this.hsCode,
  });

  final String name;
  final Money salePrice;
  final Money? purchasePrice;
  final Qty openingStock;
  final Qty minStock;
  final String? barcode;
  final String? code;
  final String? unit;
  final String? category;
  final String? hsCode;
}

/// A customer or supplier from a sheet.
final class PartyRow {
  const PartyRow({
    required this.name,
    this.phone,
    this.balance = Money.zero,
    this.isSupplier = false,
    this.city,
  });

  final String name;
  final String? phone;

  /// What they owed the shop (a customer) or the shop owed them (a
  /// supplier) when the shop started keeping books here.
  final Money balance;
  final bool isSupplier;
  final String? city;
}

/// Headings each field is recognised by: English, Roman Urdu, and what
/// the common billing apps put on their own exports. Compared with case,
/// spaces and punctuation taken out.
const _itemHeadings = {
  'name': [
    'name',
    'itemname',
    'item',
    'product',
    'productname',
    'naam',
    'cheez',
    'itemdescription',
    'particulars',
  ],
  'salePrice': [
    'saleprice',
    'price',
    'rate',
    'salerate',
    'sellingprice',
    'retailprice',
    'saleamount',
    'qeemat',
    'mrp',
  ],
  'purchasePrice': [
    'purchaseprice',
    'cost',
    'costprice',
    'purchaserate',
    'buyingprice',
    'khareed',
    'purchase',
  ],
  'openingStock': [
    'stock',
    'openingstock',
    'openingquantity',
    'qty',
    'quantity',
    'stockquantity',
    'currentstock',
    'maal',
  ],
  'minStock': ['minimumstock', 'minstock', 'lowstock', 'reorderlevel'],
  'barcode': ['barcode', 'ean', 'gtin', 'upc'],
  'code': ['itemcode', 'code', 'sku', 'productcode'],
  'unit': ['unit', 'uom', 'baseunit', 'primaryunit'],
  'category': ['category', 'group', 'itemcategory', 'qism'],
  'hsCode': ['hscode', 'hsn', 'hs'],
};

const _partyHeadings = {
  'name': [
    'name',
    'partyname',
    'party',
    'customer',
    'customername',
    'supplier',
    'suppliername',
    'naam',
    'khata',
  ],
  'phone': [
    'phone',
    'mobile',
    'phoneno',
    'mobileno',
    'phonenumber',
    'mobilenumber',
    'contact',
    'contactno',
    'number',
  ],
  'balance': [
    'balance',
    'openingbalance',
    'due',
    'udhaar',
    'receivable',
    'payable',
    'amount',
    'baqaya',
    'currentbalance',
  ],
  'type': ['type', 'partytype', 'kind'],
  'city': ['city', 'shehar', 'town'],
};

String _squash(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Finds the heading row — the first row with a recognised name column —
/// and which column holds each field.
(int, Map<String, int>)? _headings(
  SheetRows sheet,
  Map<String, List<String>> headings,
) {
  for (var r = 0; r < sheet.rows.length && r < 10; r++) {
    final found = <String, int>{};
    final row = sheet.rows[r];
    for (final field in headings.keys) {
      for (final alias in headings[field]!) {
        final at = row.indexWhere((cell) => _squash(cell) == alias);
        if (at >= 0 && !found.containsValue(at)) {
          found[field] = at;
          break;
        }
      }
    }
    if (found.containsKey('name')) return (r, found);
  }
  return null;
}

String _cell(List<String> row, int? column) =>
    column == null || column >= row.length ? '' : row[column].trim();

String? _optional(List<String> row, int? column) {
  final v = _cell(row, column);
  return v.isEmpty ? null : v;
}

/// A number as Excel stores it, as text with at most [decimals] places:
/// `159.99999999999997` is `160.00`, `1.5E3` is `1500`. Anything that is
/// not a plain number — `Rs 1,250` — is left for the money parser.
String excelNumber(String raw, int decimals) {
  final m = RegExp(r'^(-?)(\d*)(?:\.(\d*))?[eE]?([-+]?\d+)?$').firstMatch(raw);
  if (m == null || '${m[2]}${m[3] ?? ''}'.isEmpty) return raw;
  final negative = m[1] == '-';
  var digits = '${m[2]}${m[3] ?? ''}';
  var point = m[2]!.length + (int.tryParse(m[4] ?? '') ?? 0);
  if (point < 0) {
    digits = '${'0' * -point}$digits';
    point = 0;
  }
  if (point > digits.length) digits = digits.padRight(point, '0');
  // Round half up at [decimals] places, on the digits themselves.
  final keep = point + decimals;
  var kept = BigInt.parse(
    digits.length > keep
        ? digits.substring(0, keep)
        : digits.padRight(keep, '0'),
  );
  if (digits.length > keep && digits.codeUnitAt(keep) >= 0x35) {
    kept += BigInt.one;
  }
  final text = kept.toString().padLeft(decimals + 1, '0');
  final whole = text.substring(0, text.length - decimals);
  final frac = text.substring(text.length - decimals);
  final sign = negative && kept != BigInt.zero ? '-' : '';
  return decimals == 0 ? '$sign$whole' : '$sign$whole.$frac';
}

Money? _money(String raw) =>
    raw.isEmpty ? null : Money.tryParse(excelNumber(raw, 2));

Qty? _qty(String raw) => raw.isEmpty ? null : Qty.tryParse(excelNumber(raw, 3));

/// Items from a sheet: a name and a sale price at least, one row each.
ImportPlan<ItemRow> planItems(SheetRows sheet) {
  final heads = _headings(sheet, _itemHeadings);
  if (heads == null || !heads.$2.containsKey('salePrice')) {
    throw const ImportRefused(
      'Could not find the columns. The first row needs headings, with at '
      'least "Name" and "Sale price".',
    );
  }
  final (headRow, col) = heads;
  final rows = <(int, ItemRow)>[];
  final problems = <ImportProblem>[];
  final seen = <String>{};
  for (var r = headRow + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final line = r + 1;
    if (row.every((c) => c.trim().isEmpty)) continue;
    final name = _cell(row, col['name']);
    if (name.isEmpty) {
      problems.add(ImportProblem(line, 'no name'));
      continue;
    }
    if (!seen.add(name.toLowerCase())) {
      problems.add(ImportProblem(line, '$name is in the sheet twice'));
      continue;
    }
    final price = _money(_cell(row, col['salePrice']));
    if (price == null || price.isNegative) {
      problems.add(ImportProblem(line, '$name has no sale price'));
      continue;
    }
    final costText = _cell(row, col['purchasePrice']);
    final cost = _money(costText);
    if (costText.isNotEmpty && cost == null) {
      problems.add(ImportProblem(line, '$name: "$costText" is not a price'));
      continue;
    }
    final stockText = _cell(row, col['openingStock']);
    final stock = _qty(stockText);
    if (stockText.isNotEmpty && (stock == null || stock.isNegative)) {
      problems.add(
        ImportProblem(line, '$name: "$stockText" is not a stock quantity'),
      );
      continue;
    }
    rows.add((
      line,
      ItemRow(
        name: name,
        salePrice: price,
        purchasePrice: cost,
        openingStock: stock ?? Qty.zero,
        minStock: _qty(_cell(row, col['minStock'])) ?? Qty.zero,
        barcode: _optional(row, col['barcode']),
        code: _optional(row, col['code']),
        unit: _optional(row, col['unit']),
        category: _optional(row, col['category']),
        hsCode: _optional(row, col['hsCode']),
      ),
    ));
  }
  return ImportPlan(
    rows: rows,
    problems: problems,
    columns: {
      for (final e in col.entries) e.key: sheet.rows[headRow][e.value].trim(),
    },
  );
}

/// Customers and suppliers from a sheet: a name at least.
///
/// A supplier is a row whose type says so; a sheet with no type column is
/// all customers. A negative balance on a customer is an advance they paid.
ImportPlan<PartyRow> planParties(SheetRows sheet) {
  final heads = _headings(sheet, _partyHeadings);
  if (heads == null) {
    throw const ImportRefused(
      'Could not find the columns. The first row needs headings, with at '
      'least "Name".',
    );
  }
  final (headRow, col) = heads;
  final rows = <(int, PartyRow)>[];
  final problems = <ImportProblem>[];
  final seen = <String>{};
  for (var r = headRow + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final line = r + 1;
    if (row.every((c) => c.trim().isEmpty)) continue;
    final name = _cell(row, col['name']);
    if (name.isEmpty) {
      problems.add(ImportProblem(line, 'no name'));
      continue;
    }
    if (!seen.add(name.toLowerCase())) {
      problems.add(ImportProblem(line, '$name is in the sheet twice'));
      continue;
    }
    final balanceText = _cell(row, col['balance']);
    final balance = _money(balanceText);
    if (balanceText.isNotEmpty && balance == null) {
      problems.add(
        ImportProblem(line, '$name: "$balanceText" is not an amount'),
      );
      continue;
    }
    final type = _squash(_cell(row, col['type']));
    rows.add((
      line,
      PartyRow(
        name: name,
        phone: _optional(row, col['phone']),
        balance: balance ?? Money.zero,
        isSupplier: const {
          'supplier',
          'vendor',
          'seller',
          'creditor',
        }.contains(type),
        city: _optional(row, col['city']),
      ),
    ));
  }
  return ImportPlan(
    rows: rows,
    problems: problems,
    columns: {
      for (final e in col.entries) e.key: sheet.rows[headRow][e.value].trim(),
    },
  );
}
