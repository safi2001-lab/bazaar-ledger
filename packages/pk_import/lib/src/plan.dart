import 'package:pk_money/pk_money.dart';

import 'sources.dart';
import 'spreadsheet.dart';

/// What was wrong with a row, or what was left out of one, as a kind the
/// screen can say in the shopkeeper's language.
///
/// Until M52 a problem was an English sentence and the screen printed it as
/// it was, so a shop reading Roman Urdu was told in English why its rows
/// were left out. The English [ImportProblem.message] stays, for the activity
/// log and for anyone reading a test; the screen speaks from the kind.
enum ImportIssue {
  /// Anything said in words only, such as a refusal from the books.
  other,
  noName,
  inSheetTwice,

  /// A "Total" line under a report, which is a sum and not a customer.
  totalLine,
  noSalePrice,
  notAPrice,
  notAQuantity,
  notAnAmount,

  // Rows that come in with something left out.

  /// Stock below nothing, as an app that lets the counter oversell keeps
  /// it. The item comes in with none on the shelf.
  negativeStock,

  /// A barcode Excel turned into `8.96E+12` when it saved the sheet as CSV.
  /// The digits are gone, so no barcode is better than a wrong one.
  barcodeMangled,

  /// A supplier the shop owes. Their balance is not brought in: what the
  /// shop owes is kept as purchase bills, and the khata reads it from them.
  supplierOwed,

  /// A supplier who owes the shop, likewise not brought in.
  supplierOwes,

  // From the import itself, against what the shop already has.
  alreadyItem,
  alreadyParty,

  /// Already in the shop, and brought up to date from the sheet.
  updated,
}

/// One thing the import could not take, or took only in part, and why.
final class ImportProblem {
  const ImportProblem(
    this.line,
    this.message, {
    this.issue = ImportIssue.other,
    this.name = '',
    this.value = '',
  });

  ImportProblem.of(this.line, this.issue, {this.name = '', this.value = ''})
    : message = _english(issue, name, value);

  /// The row as the spreadsheet numbers it, heading row included.
  final int line;
  final String message;
  final ImportIssue issue;

  /// Whose row it is: the item or party name.
  final String name;

  /// What was in the cell, an amount, or the name it clashed with.
  final String value;

  static String _english(ImportIssue issue, String name, String value) =>
      switch (issue) {
        ImportIssue.other => '$name: $value',
        ImportIssue.noName => 'no name',
        ImportIssue.inSheetTwice => '$name is in the sheet twice',
        ImportIssue.totalLine => 'a total line, not a row of its own',
        ImportIssue.noSalePrice => '$name has no sale price',
        ImportIssue.notAPrice => '$name: "$value" is not a price',
        ImportIssue.notAQuantity => '$name: "$value" is not a stock quantity',
        ImportIssue.notAnAmount => '$name: "$value" is not an amount',
        ImportIssue.negativeStock =>
          '$name comes in with no stock; the sheet says $value',
        ImportIssue.barcodeMangled =>
          '$name comes in without its barcode; Excel saved it as $value',
        ImportIssue.supplierOwed =>
          '$name was added without the Rs $value owed; '
              'enter it as a purchase bill',
        ImportIssue.supplierOwes =>
          '$name was added without the Rs $value they owe the shop',
        ImportIssue.alreadyItem => '$name is already an item',
        ImportIssue.alreadyParty => '$name is already in the khata',
        ImportIssue.updated =>
          '$name was already here and is brought up to date',
      };

  @override
  String toString() => 'Row $line: $message';
}

/// Something about the whole sheet the preview says before anything is
/// written.
enum ImportNoteKind {
  /// Indian GST rates were in the sheet and none is carried.
  gstNotCarried,

  /// A tax column was in the sheet and is not read.
  taxNotRead,

  /// India's HSN codes were in the sheet and none is carried.
  hsnNotCarried,

  /// GSTIN numbers were in the sheet and are not kept.
  gstinNotKept,

  /// Amounts carried ₹ and were read as the rupees the shop kept them in.
  rupeeSign,

  /// Columns nothing reads.
  columnsNotKept,

  /// Items Vyapar marked as services, which come in without stock.
  services,
}

final class ImportNote {
  const ImportNote(this.kind, {this.count = 0, this.detail = ''});

  final ImportNoteKind kind;

  /// How many rows it touched.
  final int count;

  /// The rates, or the columns, as the sheet wrote them.
  final String detail;

  @override
  String toString() => '${kind.name}($count, $detail)';
}

/// What a sheet will bring in, before anything is written.
final class ImportPlan<T> {
  const ImportPlan({
    required this.rows,
    required this.problems,
    required this.columns,
    this.caveats = const [],
    this.notes = const [],
    this.source = ImportSource.other,
    this.map,
    this.owedUnsaid = 0,
  });

  /// Rows ready to import, with the spreadsheet row each came from.
  final List<(int, T)> rows;

  /// Rows that cannot come in, and why.
  final List<ImportProblem> problems;

  /// Rows that come in with something left out, and what.
  final List<ImportProblem> caveats;

  /// What the preview says about the sheet as a whole.
  final List<ImportNote> notes;

  /// Which heading each field was read from, for the preview to show.
  final Map<String, String> columns;

  final ImportSource source;

  /// Where each field was found, for the preview to change by hand.
  final ColumnMap? map;

  /// Parties the shop owes whose row does not say whether they are a
  /// customer or a supplier. The preview asks.
  final int owedUnsaid;
}

/// An item from a sheet.
final class ItemRow {
  const ItemRow({
    required this.name,
    required this.salePrice,
    this.purchasePrice,
    this.wholesalePrice,
    this.mrp,
    this.openingStock = Qty.zero,
    this.minStock = Qty.zero,
    this.barcode,
    this.code,
    this.unit,
    this.secondaryUnit,
    this.conversion,
    this.category,
    this.description,
    this.hsCode,
    this.tracksStock = true,
    this.genericName, // M54
  });

  final String name;
  final Money salePrice;
  final Money? purchasePrice;
  final Money? wholesalePrice;
  final Money? mrp;
  final Qty openingStock;
  final Qty minStock;
  final String? barcode;
  final String? code;

  /// The unit it is counted in: one of the shop's codes (`pcs`, `kg`) where
  /// the sheet's word is one of theirs, or the word as written.
  final String? unit;

  /// Vyapar's second unit, and how many of it make one [unit] (its
  /// "Conversion Rate (n) (x = ny)").
  final String? secondaryUnit;
  final Qty? conversion;
  final String? category;
  final String? description;

  /// Pakistan's tariff code, from a column that says HS or PCT. India's HSN
  /// never lands here.
  final String? hsCode;

  /// False for a service, which has no stock to count.
  final bool tracksStock;

  /// M54: a medicine's salt (M49), from a Generic, Salt or Formula column.
  final String? genericName;
}

/// A customer or supplier from a sheet.
final class PartyRow {
  const PartyRow({
    required this.name,
    this.phone,
    this.balance = Money.zero,
    this.isSupplier = false,
    this.city,
    this.address,
    this.creditLimit,
  });

  final String name;
  final String? phone;

  /// What they owed the shop (a customer) or the shop owed them (a
  /// supplier) when the shop started keeping books here. Negative the other
  /// way round: a customer's advance, a supplier the shop paid ahead.
  final Money balance;
  final bool isSupplier;
  final String? city;
  final String? address;
  final Money? creditLimit;

  /// What they owe the shop, whichever side they are on: positive they owe
  /// it, negative it owes them.
  Money get owesShop => isSupplier ? -balance : balance;
}

String _cell(List<String> row, int? column) {
  if (column == null || column >= row.length) return '';
  final v = row[column].trim();
  // What an app prints in an empty money or stock cell is not a value.
  return const {'-', '–', '—', 'na', 'n/a', 'nil'}.contains(v.toLowerCase())
      ? ''
      : v;
}

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

/// How a name is compared within a sheet: case, punctuation and spacing
/// aside, the way the khata's own search key is built.
String _key(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _isTotal(String name) => const {
  'total',
  'totals',
  'grandtotal',
  'subtotal',
  'nettotal',
}.contains(squash(name));

/// A tax cell that says something: not empty, not nought.
bool _saysTax(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  if (digits.isEmpty) return raw.trim().isNotEmpty;
  return RegExp('[1-9]').hasMatch(digits);
}

/// What the preview says about a sheet's columns, whichever list it is.
List<ImportNote> _sheetNotes(
  ColumnMap map,
  ImportSource source, {
  required int taxed,
  required Set<String> rates,
  required int hsn,
  required int gstin,
  required bool rupee,
}) => [
  if (taxed > 0)
    ImportNote(
      // An Indian app's rates are GST whatever the column says; so is any
      // column that calls itself GST.
      source.isIndian ||
              squash(map.headingOf(ImportField.tax) ?? '').contains('gst')
          ? ImportNoteKind.gstNotCarried
          : ImportNoteKind.taxNotRead,
      count: taxed,
      detail: (rates.toList()..sort()).join(', '),
    ),
  if (hsn > 0) ImportNote(ImportNoteKind.hsnNotCarried, count: hsn),
  if (gstin > 0) ImportNote(ImportNoteKind.gstinNotKept, count: gstin),
  if (rupee) const ImportNote(ImportNoteKind.rupeeSign),
  if (map.unread.isNotEmpty)
    ImportNote(
      ImportNoteKind.columnsNotKept,
      count: map.unread.length,
      detail: map.unread.join(', '),
    ),
];

Map<String, String> _columnsOf(ColumnMap map) => {
  for (final e in map.fields.entries)
    if (!e.key.isLeftOut) e.key.name: map.headings[e.value].trim(),
};

/// Items from a sheet: a name and a sale price at least, one row each.
///
/// [columns] is where each field is, when the shop has pointed one by hand;
/// otherwise the headings are found as [source] writes them.
ImportPlan<ItemRow> planItems(
  SheetRows sheet, {
  ImportSource source = ImportSource.other,
  ColumnMap? columns,
}) {
  final map = columns ?? findColumns(sheet, ImportKind.items, source: source);
  final col = map.fields;
  if (!col.containsKey(ImportField.name) ||
      !col.containsKey(ImportField.salePrice)) {
    throw const ImportRefused(
      'Could not find the columns. The first row needs headings, with at '
      'least "Name" and "Sale price".',
    );
  }
  final rows = <(int, ItemRow)>[];
  final problems = <ImportProblem>[];
  final caveats = <ImportProblem>[];
  final seen = <String>{};
  var taxed = 0;
  final rates = <String>{};
  var hsn = 0;
  var services = 0;
  var rupee = false;

  // An optional price: null when empty, and the row refused when it cannot
  // be read. A price is never guessed.
  (Money?, bool) price(List<String> row, ImportField field) {
    final text = _cell(row, col[field]);
    if (text.isEmpty) return (null, true);
    final amount = readAmount(text);
    if (amount == null || amount.money.isNegative) return (null, false);
    if (amount.rupeeSign) rupee = true;
    return (amount.money, true);
  }

  for (var r = map.headRow + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final line = r + 1;
    if (row.every((c) => c.trim().isEmpty)) continue;
    final name = _cell(row, col[ImportField.name]);
    if (name.isEmpty) {
      problems.add(ImportProblem.of(line, ImportIssue.noName));
      continue;
    }
    if (_isTotal(name)) {
      problems.add(ImportProblem.of(line, ImportIssue.totalLine, name: name));
      continue;
    }
    if (!seen.add(_key(name))) {
      problems.add(
        ImportProblem.of(line, ImportIssue.inSheetTwice, name: name),
      );
      continue;
    }
    final saleText = _cell(row, col[ImportField.salePrice]);
    final (sale, saleRead) = price(row, ImportField.salePrice);
    if (sale == null) {
      problems.add(
        saleText.isEmpty || saleRead
            ? ImportProblem.of(line, ImportIssue.noSalePrice, name: name)
            : ImportProblem.of(
                line,
                ImportIssue.notAPrice,
                name: name,
                value: saleText,
              ),
      );
      continue;
    }
    ImportProblem? unread;
    final optional = <ImportField, Money?>{};
    for (final field in const [
      ImportField.purchasePrice,
      ImportField.wholesalePrice,
      ImportField.mrp,
    ]) {
      final (money, read) = price(row, field);
      if (!read) {
        unread = ImportProblem.of(
          line,
          ImportIssue.notAPrice,
          name: name,
          value: _cell(row, col[field]),
        );
        break;
      }
      optional[field] = money;
    }
    if (unread != null) {
      problems.add(unread);
      continue;
    }

    final type = squash(_cell(row, col[ImportField.itemType]));
    final service = type == 'service' || type == 'services';
    final stockText = service ? '' : _cell(row, col[ImportField.openingStock]);
    var stock = stockText.isEmpty ? Qty.zero : readQty(stockText);
    if (stock == null) {
      problems.add(
        ImportProblem.of(
          line,
          ImportIssue.notAQuantity,
          name: name,
          value: stockText,
        ),
      );
      continue;
    }
    if (stock.isNegative) {
      caveats.add(
        ImportProblem.of(
          line,
          ImportIssue.negativeStock,
          name: name,
          value: stockText,
        ),
      );
      stock = Qty.zero;
    }
    if (service) services++;

    var barcode = _optional(row, col[ImportField.barcode]);
    if (barcode != null &&
        RegExp(r'^\d+(\.\d+)?[eE]\+?\d+$').hasMatch(barcode)) {
      caveats.add(
        ImportProblem.of(
          line,
          ImportIssue.barcodeMangled,
          name: name,
          value: barcode,
        ),
      );
      barcode = null;
    }

    final taxText = _cell(row, col[ImportField.tax]);
    if (_saysTax(taxText)) {
      taxed++;
      rates.add(taxText);
    }
    if (_cell(row, col[ImportField.hsn]).isNotEmpty) hsn++;

    final unitText = _optional(row, col[ImportField.unit]);
    final secondText = _optional(row, col[ImportField.secondaryUnit]);
    final minText = _cell(row, col[ImportField.minStock]);
    final min = minText.isEmpty ? null : readQty(minText);
    rows.add((
      line,
      ItemRow(
        name: name,
        salePrice: sale,
        purchasePrice: optional[ImportField.purchasePrice],
        wholesalePrice: optional[ImportField.wholesalePrice],
        mrp: optional[ImportField.mrp],
        openingStock: stock,
        minStock: min == null || min.isNegative ? Qty.zero : min,
        barcode: barcode,
        code: _optional(row, col[ImportField.code]),
        unit: unitText == null ? null : unitCode(unitText),
        secondaryUnit: secondText == null ? null : unitCode(secondText),
        conversion: secondText == null
            ? null
            : readQty(_cell(row, col[ImportField.conversion])),
        category: _optional(row, col[ImportField.category]),
        description: _optional(row, col[ImportField.description]),
        hsCode: _optional(row, col[ImportField.hsCode]),
        tracksStock: !service,
        genericName: _optional(row, col[ImportField.genericName]), // M54
      ),
    ));
  }
  return ImportPlan(
    rows: rows,
    problems: problems,
    caveats: caveats,
    columns: _columnsOf(map),
    source: source,
    map: map,
    notes: [
      ..._sheetNotes(
        map,
        source,
        taxed: taxed,
        rates: rates,
        hsn: hsn,
        gstin: 0,
        rupee: rupee,
      ),
      if (services > 0) ImportNote(ImportNoteKind.services, count: services),
    ],
  );
}

const _supplierWords = {
  'supplier',
  'suppliers',
  'vendor',
  'vendors',
  'seller',
  'creditor',
  'creditors',
  'distributor',
};

const _customerWords = {
  'customer',
  'customers',
  'buyer',
  'debtor',
  'debtors',
  'client',
  'grahak',
};

/// Customers and suppliers from a sheet: a name at least.
///
/// What each owes is read whichever way the sheet writes it: one signed
/// balance (negative, the shop owes them); a balance with "To Receive" or
/// "To Pay", "Dr" or "Cr" beside it or in a column of its own; or separate
/// columns for what they owe and what the shop owes ("Receivable Balance"
/// and "Payable Balance", "You will get" and "You will give").
///
/// A supplier is a row whose type says so. A row that does not say, and
/// that the shop owes, is a supplier when [owedAreSuppliers] (by default,
/// what [source] usually means) and otherwise a customer who paid ahead. A
/// plain balance on a row marked supplier is what the shop owes them, as
/// M14 read it.
ImportPlan<PartyRow> planParties(
  SheetRows sheet, {
  ImportSource source = ImportSource.other,
  ColumnMap? columns,
  bool? owedAreSuppliers,
}) {
  final map = columns ?? findColumns(sheet, ImportKind.parties, source: source);
  final col = map.fields;
  if (!col.containsKey(ImportField.name)) {
    throw const ImportRefused(
      'Could not find the columns. The first row needs headings, with at '
      'least "Name".',
    );
  }
  final suppliersByDefault = owedAreSuppliers ?? source.owedAreSuppliers;
  final rows = <(int, PartyRow)>[];
  final problems = <ImportProblem>[];
  final caveats = <ImportProblem>[];
  final seen = <String>{};
  var gstin = 0;
  var owedUnsaid = 0;
  var rupee = false;

  for (var r = map.headRow + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final line = r + 1;
    if (row.every((c) => c.trim().isEmpty)) continue;
    final name = _cell(row, col[ImportField.name]);
    if (name.isEmpty) {
      problems.add(ImportProblem.of(line, ImportIssue.noName));
      continue;
    }
    if (_isTotal(name)) {
      problems.add(ImportProblem.of(line, ImportIssue.totalLine, name: name));
      continue;
    }
    if (!seen.add(_key(name))) {
      problems.add(
        ImportProblem.of(line, ImportIssue.inSheetTwice, name: name),
      );
      continue;
    }

    final typeWord = squash(_cell(row, col[ImportField.type]));
    final saidSupplier = _supplierWords.contains(typeWord);
    final saidCustomer = _customerWords.contains(typeWord);

    // What they owe the shop, positive; what the shop owes them, negative.
    Money? owed;
    String? unreadable;
    SheetAmount? amountIn(ImportField field) {
      final text = _cell(row, col[field]);
      if (text.isEmpty) return null;
      final a = readAmount(text);
      if (a == null) {
        unreadable ??= text;
      } else if (a.rupeeSign) {
        rupee = true;
      }
      return a;
    }

    final get = amountIn(ImportField.receivable);
    final give = amountIn(ImportField.payable);
    final plain = amountIn(ImportField.balance);
    if (get != null || give != null) {
      Money signed(SheetAmount a, Direction otherwise) =>
          (a.direction ?? otherwise) == Direction.theyOwe
          ? a.money.abs
          : -a.money.abs;
      owed =
          (get == null ? Money.zero : signed(get, Direction.theyOwe)) +
          (give == null ? Money.zero : signed(give, Direction.shopOwes));
    } else if (plain != null) {
      final said =
          plain.direction ??
          readDirection(_cell(row, col[ImportField.balanceType]));
      owed = switch (said) {
        Direction.theyOwe => plain.money.abs,
        Direction.shopOwes => -plain.money.abs,
        // A plain figure on a supplier's row is what the shop owes them.
        null => saidSupplier ? -plain.money : plain.money,
      };
    }
    if (unreadable != null) {
      problems.add(
        ImportProblem.of(
          line,
          ImportIssue.notAnAmount,
          name: name,
          value: unreadable!,
        ),
      );
      continue;
    }
    final limitText = _cell(row, col[ImportField.creditLimit]);
    final limit = limitText.isEmpty ? null : readAmount(limitText);
    if (limitText.isNotEmpty && (limit == null || limit.money.isNegative)) {
      problems.add(
        ImportProblem.of(
          line,
          ImportIssue.notAnAmount,
          name: name,
          value: limitText,
        ),
      );
      continue;
    }

    owed ??= Money.zero;
    var supplier = saidSupplier;
    if (!saidSupplier && !saidCustomer && owed.isNegative) {
      owedUnsaid++;
      supplier = suppliersByDefault;
    }
    if (supplier && !owed.isZero) {
      caveats.add(
        ImportProblem.of(
          line,
          owed.isNegative ? ImportIssue.supplierOwed : ImportIssue.supplierOwes,
          name: name,
          value: owed.abs.amountOnly,
        ),
      );
    }
    if (_cell(row, col[ImportField.gstin]).isNotEmpty) gstin++;

    rows.add((
      line,
      PartyRow(
        name: name,
        phone: _optional(row, col[ImportField.phone]),
        balance: supplier ? -owed : owed,
        isSupplier: supplier,
        city: _optional(row, col[ImportField.city]),
        address: _optional(row, col[ImportField.address]),
        creditLimit: limit?.money,
      ),
    ));
  }
  return ImportPlan(
    rows: rows,
    problems: problems,
    caveats: caveats,
    columns: _columnsOf(map),
    source: source,
    map: map,
    owedUnsaid: owedUnsaid,
    notes: _sheetNotes(
      map,
      source,
      taxed: 0,
      rates: const {},
      hsn: 0,
      gstin: gstin,
      rupee: rupee,
    ),
  );
}
