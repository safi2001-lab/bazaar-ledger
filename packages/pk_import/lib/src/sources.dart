import 'package:pk_money/pk_money.dart';

import 'plan.dart' show excelNumber;
import 'spreadsheet.dart';

/// Where a sheet came from, which decides what its headings mean.
///
/// Two apps strand Pakistani shops at once. Vyapar's licences have not been
/// renewable in Pakistan since about May 2025, and Khatabook asks for an
/// Indian number's OTP before it opens a khata. Vyapar's shops already have
/// their lists in a file — it exports its items and its party report to
/// Excel — and a Khatabook shop has one where its version gives the customer
/// list as a sheet (its phone app's help documents only PDF reports). A shop
/// moving here should bring the lot in one go, not type four hundred
/// customers again.
///
/// None of these presets is a different reader. Each adds the headings that
/// app is known to write to the ones every sheet is read with, says which
/// list it is, and says what in it is India's and not Pakistan's.
enum ImportSource {
  /// The headings this app reads and shows on screen: Name, Sale price,
  /// Purchase price, Stock, Unit and the rest.
  bazaarLedger,

  /// Vyapar's item list: Utilities, Export Items, or its Import Items
  /// template filled in.
  vyaparItems,

  /// Vyapar's parties: the All Parties report saved as Excel, or its Import
  /// Parties template.
  vyaparParties,

  /// Khatabook's customer list as a sheet.
  khatabook,

  /// Anything else. Headings are found by their usual names, and any of them
  /// can be pointed at another column by hand.
  other;

  /// The list this source always is, or null where the shop says which.
  ImportKind? get kind => switch (this) {
    vyaparItems => ImportKind.items,
    vyaparParties || khatabook => ImportKind.parties,
    bazaarLedger || other => null,
  };

  /// A file out of an Indian app. Its tax rates are GST and its codes are
  /// HSN and GSTIN — India's, every one, and none of them Pakistan's.
  bool get isIndian => kind != null;

  /// Who a party is when nothing in the row says, and the shop owes them.
  ///
  /// Vyapar keeps one list of parties with no customer or supplier column,
  /// and a party the shop owes ("To Pay") is nearly always somebody it buys
  /// from. Khatabook's list is customers, so one the shop owes is a customer
  /// who paid ahead. The shop can say otherwise on the preview.
  bool get owedAreSuppliers => this == vyaparParties;
}

/// Which list a sheet is.
enum ImportKind { items, parties }

/// The things a column can hold.
///
/// Some are read and kept; some are read only so that what was in them can
/// be said — an Indian GST rate is recognised precisely so that it is never
/// carried across silently.
enum ImportField {
  // Items and parties.
  name,
  // Items.
  salePrice,
  purchasePrice,
  wholesalePrice,
  mrp,
  openingStock,
  minStock,
  unit,
  secondaryUnit,
  conversion,
  code,
  barcode,
  category,
  description,
  hsCode,
  itemType,

  /// M54: a medicine's salt, from a column headed Generic, Salt or Formula
  /// (M49's generic name), as a chemist's list from Marg or Vyapar has it.
  genericName,

  /// India's HSN/SAC. Read so it can be named and left out: Pakistan's
  /// tariff line is the PCT code, which agrees with HSN only to six digits,
  /// and an FBR invoice carrying an Indian eight-digit code is wrong.
  hsn,

  /// A tax rate. Never carried: an Indian GST slab is not Pakistani sales
  /// tax, and even a rate that happens to read 18% in both countries was set
  /// under the other country's law.
  tax,
  // Parties.
  phone,
  balance,

  /// What they owe the shop, as a column of its own ("Receivable Balance",
  /// "To Receive", "You will get").
  receivable,

  /// What the shop owes them ("Payable Balance", "To Pay", "You will give").
  payable,

  /// Which way a single balance column runs ("To Receive" / "To Pay",
  /// "Dr" / "Cr").
  balanceType,
  type,
  city,
  address,
  creditLimit,

  /// India's GST number. Not an NTN, and not kept as one.
  gstin;

  static const items = [
    name,
    salePrice,
    purchasePrice,
    wholesalePrice,
    mrp,
    openingStock,
    minStock,
    unit,
    secondaryUnit,
    conversion,
    code,
    barcode,
    category,
    description,
    hsCode,
    itemType,
    genericName, // M54
    hsn,
    tax,
  ];

  static const parties = [
    name,
    phone,
    balance,
    receivable,
    payable,
    balanceType,
    type,
    city,
    address,
    creditLimit,
    gstin,
  ];

  /// Fields recognised only to be named and left out.
  bool get isLeftOut => this == hsn || this == tax || this == gstin;
}

/// Headings each field is recognised by, compared with case, spaces and
/// punctuation taken out: `Item name*` is `itemname`, `Conversion Rate (n)
/// (x = ny)` is `conversionratenxny`. English, Roman Urdu, and what the
/// common billing apps write. The earlier alias in each list wins.
///
/// Vyapar's headings are from its import template and its exports as they
/// are commonly reproduced; its own help pages show the menus but never the
/// columns, and Khatabook's help documents only PDF reports. So no preset
/// leans on an exact match alone: every one of them goes through the same
/// tolerant comparison, and the shop can point any field at another column
/// by hand on the preview.
const Map<ImportField, List<String>> _aliases = {
  ImportField.name: [
    'name',
    'itemname',
    'partyname',
    'customername',
    'suppliername',
    'item',
    'product',
    'productname',
    'party',
    'customer',
    'supplier',
    'accountname',
    'contactname',
    'naam',
    'cheez',
    'khata',
    'itemdescription',
    'particulars',
  ],
  ImportField.salePrice: [
    'saleprice',
    'salesprice',
    'sellingprice',
    'salerate',
    'retailprice',
    'price',
    'rate',
    'unitprice',
    'saleamount',
    'qeemat',
    // A sheet with only an MRP column sells at it. One with both keeps the
    // MRP as the MRP.
    'mrp',
  ],
  ImportField.purchasePrice: [
    'purchaseprice',
    'purchaserate',
    'costprice',
    'cost',
    'buyingprice',
    'khareed',
    'purchase',
  ],
  ImportField.wholesalePrice: [
    'wholesaleprice',
    'wholesalerate',
    'tradeprice',
    'wholesale',
  ],
  ImportField.mrp: ['defaultmrp', 'mrp', 'maximumretailprice', 'printedprice'],
  ImportField.openingStock: [
    'openingstockquantity',
    'openingstock',
    'openingquantity',
    'openingstockqty',
    'stockquantity',
    'currentstock',
    'closingstock',
    'stockinhand',
    'availablestock',
    'stock',
    'qty',
    'quantity',
    'stockqty',
    'maal',
  ],
  ImportField.minStock: [
    'minimumstockquantity',
    'minimumstock',
    'minstock',
    'minstocktomaintain',
    'lowstock',
    'lowstockalert',
    'reorderlevel',
  ],
  ImportField.unit: [
    'baseunitx',
    'baseunit',
    'unit',
    'uom',
    'primaryunit',
    'units',
  ],
  ImportField.secondaryUnit: [
    'secondaryunity',
    'secondaryunit',
    'alternateunit',
    'altunit',
  ],
  ImportField.conversion: [
    'conversionratenxny',
    'conversionrate',
    'conversion',
    'conversionfactor',
  ],
  ImportField.code: ['itemcode', 'code', 'sku', 'productcode'],
  ImportField.barcode: ['barcode', 'barcodeno', 'ean', 'gtin', 'upc'],
  ImportField.category: [
    'category',
    'itemcategory',
    'categoryname',
    'group',
    'qism',
  ],
  ImportField.description: ['description', 'details', 'tafseel'],
  ImportField.hsCode: ['hscode', 'pctcode', 'pct', 'hs'],
  ImportField.itemType: ['itemtype', 'producttype', 'type'],
  // M54: the salt of a medicine.
  ImportField.genericName: [
    'genericname',
    'generic',
    'salt',
    'saltname',
    'formula',
    'formulaname',
    'composition',
  ],
  ImportField.hsn: ['hsn', 'hsnsac', 'hsncode', 'hsnsaccode', 'sac'],
  ImportField.tax: [
    'taxrate',
    'tax',
    'gst',
    'gstrate',
    'gstpercent',
    'gstpercentage',
    'taxpercent',
    'taxslab',
    'salestax',
    'salestaxrate',
  ],
  ImportField.phone: [
    'phone',
    'mobile',
    'phoneno',
    'mobileno',
    'phonenumber',
    'mobilenumber',
    'contact',
    'contactno',
    'contactnumber',
    'whatsapp',
    'whatsappno',
    'cell',
    'cellno',
    'number',
  ],
  ImportField.balance: [
    'balance',
    'openingbalance',
    'currentbalance',
    'closingbalance',
    'netbalance',
    'balanceamount',
    'totalbalance',
    'outstanding',
    'due',
    'udhaar',
    'baqaya',
    'amount',
  ],
  ImportField.receivable: [
    'receivablebalance',
    'receivable',
    'toreceive',
    'torecieve',
    'youwillget',
    'youllget',
    'willget',
    'yougave',
    'lena',
    'lenahai',
  ],
  ImportField.payable: [
    'payablebalance',
    'payable',
    'topay',
    'youwillgive',
    'youllgive',
    'willgive',
    'yougot',
    'dena',
    'denahai',
  ],
  ImportField.balanceType: [
    'balancetype',
    'receivablepayable',
    'receivableorpayable',
    'toreceivetopay',
    'topaytoreceive',
    'drcr',
    'crdr',
    'lenadena',
    'balancestatus',
  ],
  ImportField.type: ['partytype', 'type', 'kind', 'customersupplier'],
  ImportField.city: ['city', 'shehar', 'town'],
  ImportField.address: [
    'address',
    'billingaddress',
    'addressline1',
    'pata',
    'shippingaddress',
  ],
  ImportField.creditLimit: ['creditlimit'],
  ImportField.gstin: ['gstin', 'gstinuin', 'gstno', 'gstnumber', 'gstinno'],
};

/// The extra headings a preset knows, tried before the shared ones.
///
/// Khatabook writes its balance with the direction beside it ("You will
/// get"), so in its file a column called Status says which way the money
/// runs. In anybody else's, Status is more likely "active".
const Map<ImportSource, Map<ImportField, List<String>>> _presetAliases = {
  ImportSource.khatabook: {
    ImportField.balanceType: ['status'],
  },
};

/// The headings this app documents for its own list, as the screen shows
/// them. A sheet whose every heading is one of these is our own.
const bazaarLedgerItemHeadings = [
  'Name',
  'Sale price',
  'Purchase price',
  'Stock',
  'Unit',
  'Code',
  'Barcode',
  'Category',
  'Wholesale price',
  'MRP',
  'Min stock',
  'HS code',
];

const bazaarLedgerPartyHeadings = [
  'Name',
  'Phone',
  'Balance',
  'Type',
  'City',
  'Address',
  'Credit limit',
];

/// Headings that only one app writes. Two or three of them in one row is
/// that app's file, whatever the shop chose.
const _signatures = {
  ImportSource.vyaparItems: {
    'inclusiveoftax',
    'itemlocation',
    'defaultmrp',
    'discounttype',
    'salediscount',
    'openingstockquantity',
    'minimumstockquantity',
    'baseunitx',
    'secondaryunity',
    'conversionratenxny',
    'hsn',
    'hsnsac',
    'minimumwholesalequantity',
  },
  ImportSource.vyaparParties: {
    'gstin',
    'gsttype',
    'partygroup',
    'receivablebalance',
    'payablebalance',
    'toreceive',
    'topay',
    'asofdate',
    'asondate',
    'emailid',
    'billingaddress',
    'shippingaddress',
  },
  ImportSource.khatabook: {
    'youwillget',
    'youwillgive',
    'youllget',
    'youllgive',
    'yougave',
    'yougot',
  },
};

String squash(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// [squash] with anything in brackets dropped first: `Sale Price (₹)` is
/// `saleprice`, `Base Unit (x)` is `baseunit`.
String _loose(String s) => squash(s.replaceAll(RegExp(r'\([^)]*\)'), ' '));

/// Where each field is in a sheet: the heading row, its headings as written,
/// and the column each field was found in.
final class ColumnMap {
  const ColumnMap({
    required this.headRow,
    required this.headings,
    required this.fields,
  });

  /// The heading row, counted from zero. Data starts on the next one.
  final int headRow;
  final List<String> headings;
  final Map<ImportField, int> fields;

  /// The same map with [field] pointed at [column], or at nothing.
  ///
  /// A column holds one field, so whatever pointed at [column] before lets
  /// go of it.
  ColumnMap withField(ImportField field, int? column) => ColumnMap(
    headRow: headRow,
    headings: headings,
    fields: {
      for (final e in fields.entries)
        if (e.key != field && e.value != column) e.key: e.value,
      if (column != null && column >= 0 && column < headings.length)
        field: column,
    },
  );

  /// The heading a field was read from, as the sheet writes it.
  String? headingOf(ImportField field) {
    final at = fields[field];
    return at == null ? null : headings[at].trim();
  }

  /// Headings nothing reads, so the preview can say they are not kept.
  List<String> get unread => [
    for (final (i, h) in headings.indexed)
      if (h.trim().isNotEmpty && !fields.containsValue(i)) h.trim(),
  ];
}

List<String> _aliasesFor(ImportField field, ImportSource source) => [
  ...?_presetAliases[source]?[field],
  ...?_aliases[field],
];

/// Finds which column holds each of [wanted] in one row, or an empty map.
Map<ImportField, int> _match(
  List<String> row,
  List<ImportField> wanted,
  ImportSource source,
) {
  final found = <ImportField, int>{};
  // Exact headings first, across every field, then the loose comparison for
  // whatever is still missing — so `Sale Price (₹)` cannot be taken by a
  // weaker alias before the field that names it exactly has looked.
  for (final compare in [squash, _loose]) {
    final cells = [for (final c in row) compare(c)];
    for (final field in wanted) {
      if (found.containsKey(field)) continue;
      for (final alias in _aliasesFor(field, source)) {
        var at = -1;
        for (var i = 0; i < cells.length; i++) {
          if (cells[i] == alias && !found.containsValue(i)) {
            at = i;
            break;
          }
        }
        if (at >= 0) {
          found[field] = at;
          break;
        }
      }
    }
  }
  return found;
}

/// How far down a heading row is looked for. A report saved from an app
/// carries the shop's name, address and the report's title above it.
const _headSearchRows = 25;

/// Finds the heading row — the first with a recognised name column — and
/// the column each field of [kind] is in.
///
/// Never refuses: a sheet with no heading it knows comes back with the first
/// non-empty row as its headings and nothing found, so the shop can point
/// the fields at its columns by hand.
ColumnMap findColumns(
  SheetRows sheet,
  ImportKind kind, {
  ImportSource source = ImportSource.other,
}) {
  final wanted = kind == ImportKind.items
      ? ImportField.items
      : ImportField.parties;
  int? firstFilled;
  for (var r = 0; r < sheet.rows.length && r < _headSearchRows; r++) {
    final row = sheet.rows[r];
    if (row.every((c) => c.trim().isEmpty)) continue;
    firstFilled ??= r;
    final found = _match(row, wanted, source);
    if (found.containsKey(ImportField.name)) {
      return ColumnMap(headRow: r, headings: row, fields: found);
    }
  }
  final at = firstFilled ?? 0;
  return ColumnMap(
    headRow: at,
    headings: at < sheet.rows.length ? sheet.rows[at] : const [],
    fields: const {},
  );
}

/// Which app a sheet most likely came out of, from its headings, or null.
///
/// An app's own file is recognised by the headings only it writes. A list
/// whose every heading is one this app shows on screen — at least two of
/// them — is the shop's own. A plain list with Name and Price is neither,
/// and "other" reads it the same.
ImportSource? recogniseSource(SheetRows sheet) {
  final app = _recogniseApp(sheet);
  if (app != null) return app;
  for (final kind in ImportKind.values) {
    final columns = findColumns(sheet, kind);
    final named = columns.headings.where((h) => h.trim().isNotEmpty).length;
    if (named >= 2 && isBazaarLedgerList(columns, kind)) {
      return ImportSource.bazaarLedger;
    }
  }
  return null;
}

ImportSource? _recogniseApp(SheetRows sheet) {
  ImportSource? best;
  var bestScore = 0;
  for (var r = 0; r < sheet.rows.length && r < _headSearchRows; r++) {
    final cells = {
      for (final c in sheet.rows[r]) ...{squash(c), _loose(c)},
    };
    for (final MapEntry(key: source, value: marks) in _signatures.entries) {
      final score = marks.where(cells.contains).length;
      // Khatabook's "You will get" is unmistakable on its own; the others
      // need two of their own headings, since "HSN" alone could be anybody's.
      final needed = source == ImportSource.khatabook ? 1 : 2;
      if (score >= needed && score > bestScore) {
        best = source;
        bestScore = score;
      }
    }
  }
  return best;
}

/// Whether a sheet with no app's headings is an item list or a khata: an
/// item list has a price column, a khata a balance or a phone.
ImportKind guessKind(SheetRows sheet) {
  final items = findColumns(sheet, ImportKind.items);
  if (items.fields.containsKey(ImportField.salePrice)) return ImportKind.items;
  final parties = findColumns(sheet, ImportKind.parties);
  final f = parties.fields;
  if (f.containsKey(ImportField.balance) ||
      f.containsKey(ImportField.receivable) ||
      f.containsKey(ImportField.payable) ||
      f.containsKey(ImportField.phone)) {
    return ImportKind.parties;
  }
  return ImportKind.items;
}

/// Whether every heading in a sheet is one this app documents — the shop's
/// own list, or one made from the headings on screen.
bool isBazaarLedgerList(ColumnMap columns, ImportKind kind) {
  final ours = {
    for (final h
        in kind == ImportKind.items
            ? bazaarLedgerItemHeadings
            : bazaarLedgerPartyHeadings)
      squash(h),
  };
  final heads = [
    for (final h in columns.headings)
      if (h.trim().isNotEmpty) squash(h),
  ];
  return heads.isNotEmpty &&
      columns.fields.containsKey(ImportField.name) &&
      heads.every(ours.contains);
}

/// Which way money runs: they owe the shop, or the shop owes them.
enum Direction {
  /// "To Receive", "You will get", "Dr", "Lena": they owe the shop.
  theyOwe,

  /// "To Pay", "You will give", "Cr", "Dena": the shop owes them.
  shopOwes,
}

const _theyOweWords = {
  'toreceive',
  'due',
  'torecieve',
  'receivable',
  'receive',
  'youwillget',
  'youllget',
  'willget',
  'get',
  'yougave',
  'dr',
  'debit',
  'lena',
  'lenahai',
  'lene',
  'lenay',
};

const _shopOwesWords = {
  'topay',
  'payable',
  'pay',
  'youwillgive',
  'youllgive',
  'willgive',
  'give',
  'yougot',
  'cr',
  'credit',
  'dena',
  'denahai',
  'dene',
  'denay',
};

/// A direction word on its own — the content of a "To Receive / To Pay"
/// column — or null.
Direction? readDirection(String raw) {
  final w = squash(raw);
  if (w.isEmpty) return null;
  if (_theyOweWords.contains(w)) return Direction.theyOwe;
  if (_shopOwesWords.contains(w)) return Direction.shopOwes;
  return null;
}

/// An amount as a person or an app wrote it.
final class SheetAmount {
  const SheetAmount(this.money, {this.direction, this.rupeeSign = false});

  /// As written: negative when the sheet put a minus or brackets round it.
  final Money money;

  /// Which way it runs, when the cell said ("1,200 Dr", "₹ 500 To Pay").
  final Direction? direction;

  /// Whether it carried India's rupee sign (₹ or INR). Vyapar prints ₹ by
  /// default, so a Pakistani shop's file is full of them; the amounts are
  /// still the rupees the shop kept them in.
  final bool rupeeSign;
}

const _currencyWords = {'rs', 'pkr', 'inr', 'rupees', 'rupee', 'rupay', 'rp'};

final _number = RegExp(r'\d[\d,٬]*(?:\.\d+)?(?:[eE][-+]?\d+)?|\.\d+');

/// Reads `1,250.50`, `Rs 1,250`, `₹ 1,25,000`, `(500)`, `-500`, `500 Cr`,
/// `1,200 To Receive` exactly, to the paisa; null when the cell is not one
/// amount (`lots`, `500/600`).
SheetAmount? readAmount(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final m = _number.firstMatch(s);
  if (m == null) return null;
  final before = s.substring(0, m.start);
  final after = s.substring(m.end);
  // A second figure in the cell is two amounts, or a date, or a phone.
  if (RegExp(r'\d').hasMatch(after) || RegExp(r'\d').hasMatch(before)) {
    return null;
  }
  final negative =
      before.trimRight().endsWith('-') ||
      (before.contains('(') && after.contains(')'));
  final rupeeSign =
      s.contains('₹') || RegExp('inr', caseSensitive: false).hasMatch(s);
  final words = [
    for (final w in '$before $after'.toLowerCase().split(RegExp('[^a-z]+')))
      if (w.isNotEmpty && !_currencyWords.contains(w)) w,
  ].join();
  Direction? direction;
  if (words.isNotEmpty) {
    if (_theyOweWords.contains(words)) {
      direction = Direction.theyOwe;
    } else if (_shopOwesWords.contains(words)) {
      direction = Direction.shopOwes;
    } else {
      return null;
    }
  }
  final digits = m[0]!.replaceAll(RegExp('[,٬]'), '');
  final money = Money.tryParse(excelNumber(digits, 2));
  if (money == null) return null;
  return SheetAmount(
    negative ? -money : money,
    direction: direction,
    rupeeSign: rupeeSign,
  );
}

/// A quantity as written, to the thousandth: `25`, `1,200`, `2.5`, `-3`,
/// and `25 Pcs` the way a stock report prints it. Null when it is not one
/// quantity — `2 Box 5 Pcs` is two.
Qty? readQty(String raw) {
  var s = raw.trim().replaceAll(',', '');
  if (s.isEmpty) return null;
  // A unit printed after the figure is the item's own unit, read elsewhere.
  final unit = RegExp(
    r'^([-+]?[\d.eE+-]*\d)\s*[A-Za-z][A-Za-z. ]*$',
  ).firstMatch(s);
  if (unit != null) s = unit[1]!;
  return Qty.tryParse(excelNumber(s, 3));
}

/// What a sheet's unit most likely is among the units every shop starts
/// with: `PIECES`, `Pcs`, `Nos` and `Numbers` are all `pcs`; Vyapar's
/// `Kilograms (Kg)` is `kg`. Anything else comes back as written, for the
/// shop's own units (a bori, a carton) to be matched by name.
String unitCode(String raw) {
  final candidates = [
    squash(raw),
    for (final m in RegExp(r'\(([^)]*)\)').allMatches(raw)) squash(m[1]!),
    _loose(raw),
  ];
  for (final c in candidates) {
    for (final MapEntry(key: code, value: names) in _unitNames.entries) {
      if (c == code || names.contains(c)) return code;
    }
  }
  return raw.trim();
}

const _unitNames = {
  'pcs': {
    'pc',
    'pcs',
    'piece',
    'pieces',
    'nos',
    'no',
    'number',
    'numbers',
    'unit',
    'units',
    'each',
    'ea',
    'adad',
    'nag',
  },
  'dozen': {'dozens', 'dzn', 'doz', 'dz', 'darzan'},
  'kg': {'kgs', 'kilogram', 'kilograms', 'kilo', 'kilos'},
  'g': {'gm', 'gms', 'gram', 'grams', 'gramme', 'grammes', 'grm'},
  'l': {'ltr', 'ltrs', 'lt', 'litre', 'litres', 'liter', 'liters'},
  'ml': {'mililitre', 'millilitre', 'milliliter', 'millilitres', 'mls'},
  'm': {'mtr', 'mtrs', 'meter', 'meters', 'metre', 'metres'},
  'cm': {'centimeter', 'centimetre', 'centimeters', 'centimetres'},
  'gaz': {'yard', 'yards', 'yd', 'yds'},
  'maund': {'mann', 'maunds', 'mun'},
  'tola': {'tolas'},
  'seer': {'ser'},
};
