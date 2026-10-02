/// What a report can be narrowed by, beyond its dates (M33).
///
/// A shop owner asking "what did Rashid buy this month" or "what did the
/// new boy ring up yesterday" is asking the same report a narrower question.
/// The narrowing travels into the SQL as a `WHERE`, never as a filter over
/// every row read into the phone: a wholesaler's year is tens of thousands
/// of bills, and the one customer's thirty of them are an index away.
library;

import 'package:pk_domain/pk_domain.dart';

/// One way of narrowing a report. Each report declares which it accepts,
/// and the screen offers exactly those.
enum ReportFilter {
  /// One customer or supplier.
  party,

  /// Bills with one item on them, or one item's lines.
  item,

  /// Items of one category, `items.category`.
  itemCategory,

  /// Parties of one group, `parties.party_group`.
  partyGroup,

  /// One kind of document or payment: sale, purchase, payment in...
  transactionType,

  /// Bills paid, at least in part, by one mode: cash, JazzCash, cheque...
  paymentMode,

  /// Whoever entered it.
  user,

  /// Paid in full, partly paid, or not paid at all.
  paymentStatus,

  /// Only parties with something owed one way or the other.
  withBalance,

  // M34: the item and stock reports.

  /// One place goods are kept: the shop floor, a godown, a van.
  location,

  /// Only items with something on the shelf.
  inStockOnly,

  /// The day a report that stands as of today is read for instead: the
  /// stock as it was at the close of that day.
  asOf,

  /// How many days of selling a report looks back over.
  salesDays,

  /// How many days of selling a reorder is meant to last.
  coverDays,

  /// How many bills in the period make an item fast-moving.
  fastAt,

  /// Fewer bills than this in the period make an item slow-moving.
  slowBelow,

  /// A serial or IMEI number, or part of one.
  serial,
}

/// How much of a bill has been paid.
enum PaymentStatus {
  /// Nothing left on it.
  paid,

  /// Something paid, something left.
  partial,

  /// Nothing paid yet.
  unpaid,
}

/// The kinds of transaction the All Transactions report lists, by the code
/// the books write: a document's `doc_type`, or a payment's direction.
abstract final class TransactionType {
  static const sale = 'sale_invoice';
  static const saleReturn = 'sale_return';
  static const purchase = 'purchase_bill';
  static const purchaseReturn = 'purchase_return';
  static const expense = 'expense';
  static const charge = 'other_income';
  static const quotation = 'quotation';
  static const challan = 'delivery_challan';
  static const saleOrder = 'sale_order';
  static const purchaseOrder = 'purchase_order';
  static const proforma = 'proforma';
  static const paymentIn = 'payment_in';
  static const paymentOut = 'payment_out';

  /// In the order a filter offers them.
  static const all = [
    sale,
    saleReturn,
    purchase,
    purchaseReturn,
    expense,
    charge,
    quotation,
    challan,
    saleOrder,
    purchaseOrder,
    proforma,
    paymentIn,
    paymentOut,
  ];

  /// Whether [type] is a payment rather than a document.
  static bool isPayment(String type) => type == paymentIn || type == paymentOut;

  /// The type as the report and its export write it.
  static String label(String type) => switch (type) {
    sale => 'Sale',
    saleReturn => 'Sale return',
    purchase => 'Purchase',
    purchaseReturn => 'Purchase return',
    expense => 'Expense',
    charge => 'Charge',
    quotation => 'Quotation',
    challan => 'Challan',
    saleOrder => 'Sale order',
    purchaseOrder => 'Purchase order',
    proforma => 'Proforma',
    paymentIn => 'Payment in',
    paymentOut => 'Payment out',
    _ => type,
  };
}

/// The payment modes a bill can be paid by, as `payments.mode` stores them.
abstract final class PaymentMode {
  static const all = [
    'cash',
    'bank_transfer',
    'jazzcash',
    'easypaisa',
    'raast',
    'card',
    'cheque',
  ];

  /// The mode as the report and its export write it.
  static String label(String mode) => switch (mode) {
    'cash' => 'Cash',
    'bank_transfer' => 'Bank',
    'jazzcash' => 'JazzCash',
    'easypaisa' => 'EasyPaisa',
    'raast' => 'Raast',
    'card' => 'Card',
    'cheque' => 'Cheque',
    'adjustment' => 'Adjustment',
    _ => mode,
  };
}

/// The narrowing chosen for one run of a report. Empty is everything.
///
/// Each filter carries the name it was chosen by beside its id, so the
/// export can say "Party: Rashid Traders" without a second read, and a PDF
/// forwarded twice still says whose bills these are.
final class ReportFilters {
  const ReportFilters({
    this.partyId,
    this.partyName,
    this.itemId,
    this.itemName,
    this.category,
    this.partyGroup,
    this.transactionType,
    this.paymentMode,
    this.userId,
    this.userName,
    this.paymentStatus,
    this.withBalanceOnly = false,
    // M34: the item and stock reports.
    this.location,
    this.locationName,
    this.inStockOnly = false,
    this.asOf,
    this.salesDays,
    this.coverDays,
    this.fastAt,
    this.slowBelow,
    this.serial,
  });

  /// Nothing narrowed.
  static const none = ReportFilters();

  final String? partyId;
  final String? partyName;
  final String? itemId;
  final String? itemName;

  /// An `items.category`.
  final String? category;

  /// A `parties.party_group`. [ungrouped] picks the parties with none.
  final String? partyGroup;

  /// One of [TransactionType.all].
  final String? transactionType;

  /// One of [PaymentMode.all].
  final String? paymentMode;
  final String? userId;
  final String? userName;
  final PaymentStatus? paymentStatus;
  final bool withBalanceOnly;

  // M34: the item and stock reports.

  /// A `stock_ledger.location_code`: [shopFloor], a godown's name, or a
  /// van's code; [locationName] is what the shop calls it.
  final String? location;
  final String? locationName;
  final bool inStockOnly;

  /// The day a stock report is read as at, when it is not today.
  final BusinessDate? asOf;

  /// Days of selling looked back over; null is the report's own default.
  final int? salesDays;

  /// Days a reorder should last; null is the report's own default.
  final int? coverDays;

  /// Bills in the period from which an item is fast-moving.
  final int? fastAt;

  /// Bills in the period below which an item is slow-moving.
  final int? slowBelow;

  /// A serial or IMEI number, whole or in part, as it was typed.
  final String? serial;

  /// The party group a party without one is counted under.
  static const ungrouped = 'Ungrouped';

  /// The location code of the shop floor, where every movement that names
  /// no other place happened.
  static const shopFloor = 'MAIN';

  bool get isEmpty =>
      partyId == null &&
      itemId == null &&
      category == null &&
      partyGroup == null &&
      transactionType == null &&
      paymentMode == null &&
      userId == null &&
      paymentStatus == null &&
      !withBalanceOnly &&
      location == null &&
      !inStockOnly &&
      asOf == null &&
      salesDays == null &&
      coverDays == null &&
      fastAt == null &&
      slowBelow == null &&
      serial == null;

  /// Whether [filter] is set.
  bool has(ReportFilter filter) => switch (filter) {
    ReportFilter.party => partyId != null,
    ReportFilter.item => itemId != null,
    ReportFilter.itemCategory => category != null,
    ReportFilter.partyGroup => partyGroup != null,
    ReportFilter.transactionType => transactionType != null,
    ReportFilter.paymentMode => paymentMode != null,
    ReportFilter.user => userId != null,
    ReportFilter.paymentStatus => paymentStatus != null,
    ReportFilter.withBalance => withBalanceOnly,
    ReportFilter.location => location != null,
    ReportFilter.inStockOnly => inStockOnly,
    ReportFilter.asOf => asOf != null,
    ReportFilter.salesDays => salesDays != null,
    ReportFilter.coverDays => coverDays != null,
    ReportFilter.fastAt => fastAt != null,
    ReportFilter.slowBelow => slowBelow != null,
    ReportFilter.serial => serial != null,
  };

  /// Only the filters in [accepted]: a report never narrows by something it
  /// did not declare, whatever the screen carried over from the last one.
  ReportFilters only(Set<ReportFilter> accepted) => ReportFilters(
    partyId: accepted.contains(ReportFilter.party) ? partyId : null,
    partyName: accepted.contains(ReportFilter.party) ? partyName : null,
    itemId: accepted.contains(ReportFilter.item) ? itemId : null,
    itemName: accepted.contains(ReportFilter.item) ? itemName : null,
    category: accepted.contains(ReportFilter.itemCategory) ? category : null,
    partyGroup: accepted.contains(ReportFilter.partyGroup) ? partyGroup : null,
    transactionType: accepted.contains(ReportFilter.transactionType)
        ? transactionType
        : null,
    paymentMode: accepted.contains(ReportFilter.paymentMode)
        ? paymentMode
        : null,
    userId: accepted.contains(ReportFilter.user) ? userId : null,
    userName: accepted.contains(ReportFilter.user) ? userName : null,
    paymentStatus: accepted.contains(ReportFilter.paymentStatus)
        ? paymentStatus
        : null,
    withBalanceOnly:
        accepted.contains(ReportFilter.withBalance) && withBalanceOnly,
    location: accepted.contains(ReportFilter.location) ? location : null,
    locationName: accepted.contains(ReportFilter.location)
        ? locationName
        : null,
    inStockOnly: accepted.contains(ReportFilter.inStockOnly) && inStockOnly,
    asOf: accepted.contains(ReportFilter.asOf) ? asOf : null,
    salesDays: accepted.contains(ReportFilter.salesDays) ? salesDays : null,
    coverDays: accepted.contains(ReportFilter.coverDays) ? coverDays : null,
    fastAt: accepted.contains(ReportFilter.fastAt) ? fastAt : null,
    slowBelow: accepted.contains(ReportFilter.slowBelow) ? slowBelow : null,
    serial: accepted.contains(ReportFilter.serial) ? serial : null,
  );

  /// A copy with [filter] cleared.
  ReportFilters without(ReportFilter filter) =>
      only(ReportFilter.values.where((f) => f != filter).toSet());

  /// A copy with the given fields replaced. Clearing goes through
  /// [without], so a null here always means "keep".
  ReportFilters copyWith({
    String? partyId,
    String? partyName,
    String? itemId,
    String? itemName,
    String? category,
    String? partyGroup,
    String? transactionType,
    String? paymentMode,
    String? userId,
    String? userName,
    PaymentStatus? paymentStatus,
    bool? withBalanceOnly,
    String? location,
    String? locationName,
    bool? inStockOnly,
    BusinessDate? asOf,
    int? salesDays,
    int? coverDays,
    int? fastAt,
    int? slowBelow,
    String? serial,
  }) => ReportFilters(
    partyId: partyId ?? this.partyId,
    partyName: partyName ?? this.partyName,
    itemId: itemId ?? this.itemId,
    itemName: itemName ?? this.itemName,
    category: category ?? this.category,
    partyGroup: partyGroup ?? this.partyGroup,
    transactionType: transactionType ?? this.transactionType,
    paymentMode: paymentMode ?? this.paymentMode,
    userId: userId ?? this.userId,
    userName: userName ?? this.userName,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    withBalanceOnly: withBalanceOnly ?? this.withBalanceOnly,
    location: location ?? this.location,
    locationName: locationName ?? this.locationName,
    inStockOnly: inStockOnly ?? this.inStockOnly,
    asOf: asOf ?? this.asOf,
    salesDays: salesDays ?? this.salesDays,
    coverDays: coverDays ?? this.coverDays,
    fastAt: fastAt ?? this.fastAt,
    slowBelow: slowBelow ?? this.slowBelow,
    serial: serial ?? this.serial,
  );

  /// The filters in words, one line each, for the head of an export.
  List<String> describe() => [
    if (partyId != null) 'Party: ${partyName ?? partyId}',
    if (partyGroup != null) 'Party group: $partyGroup',
    if (itemId != null) 'Item: ${itemName ?? itemId}',
    if (category != null) 'Item category: $category',
    if (transactionType != null)
      'Type: ${TransactionType.label(transactionType!)}',
    if (paymentMode != null) 'Paid by: ${PaymentMode.label(paymentMode!)}',
    if (paymentStatus != null) 'Payment: ${_statusLabel(paymentStatus!)}',
    if (userId != null) 'Entered by: ${userName ?? userId}',
    if (withBalanceOnly) 'Only parties with a balance',
    // M34: the item and stock reports.
    if (location != null) 'Place: ${locationName ?? placeLabel(location!)}',
    if (inStockOnly) 'Only items in stock',
    if (asOf != null) 'As at the close of ${asOf!.value}',
    if (salesDays != null) 'Selling over the last $salesDays days',
    if (coverDays != null) 'Reorder to last $coverDays days',
    if (fastAt != null) 'Fast-moving from $fastAt bills',
    if (slowBelow != null) 'Slow-moving under $slowBelow bills',
    if (serial != null) 'Serial: $serial',
  ];

  @override
  bool operator ==(Object other) =>
      other is ReportFilters &&
      other.partyId == partyId &&
      other.itemId == itemId &&
      other.category == category &&
      other.partyGroup == partyGroup &&
      other.transactionType == transactionType &&
      other.paymentMode == paymentMode &&
      other.userId == userId &&
      other.paymentStatus == paymentStatus &&
      other.withBalanceOnly == withBalanceOnly &&
      other.location == location &&
      other.inStockOnly == inStockOnly &&
      other.asOf == asOf &&
      other.salesDays == salesDays &&
      other.coverDays == coverDays &&
      other.fastAt == fastAt &&
      other.slowBelow == slowBelow &&
      other.serial == serial;

  @override
  int get hashCode => Object.hashAll([
    partyId,
    itemId,
    category,
    partyGroup,
    transactionType,
    paymentMode,
    userId,
    paymentStatus,
    withBalanceOnly,
    location,
    inStockOnly,
    asOf,
    salesDays,
    coverDays,
    fastAt,
    slowBelow,
    serial,
  ]);
}

/// A place goods are kept, as a report writes it (M34): the shop floor by
/// name, anything else by the name it was given.
String placeLabel(String locationCode) =>
    locationCode == ReportFilters.shopFloor ? 'Shop floor' : locationCode;

/// A payment status as the report writes it.
String paymentStatusLabel(PaymentStatus status) => _statusLabel(status);

String _statusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.paid => 'Paid',
  PaymentStatus.partial => 'Partly paid',
  PaymentStatus.unpaid => 'Unpaid',
};

/// Something a filter can be set to, as the shop knows it: an item, a
/// category, a group, a member of staff.
final class ReportChoice {
  const ReportChoice({required this.id, required this.label, this.detail});

  /// What the filter carries: an id, or for a category or group the name.
  final String id;
  final String label;

  /// A second line: a party's phone, an item's code.
  final String? detail;
}
