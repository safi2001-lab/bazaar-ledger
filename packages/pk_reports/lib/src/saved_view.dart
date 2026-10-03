/// A report kept the way the shop likes it (M61).
///
/// Every Monday the owner of a wholesale shop opens Udhaar by age, narrows
/// it to the customers in the Mandi group with something owed, sorts it by
/// the oldest money, and reads it down the phone to his munshi. Six taps,
/// every Monday, the same six. Zoho calls the answer a saved view; the shop
/// calls it "my Monday udhaar list". A view is a name and everything the
/// report screen lets the shop choose: which report, which period, which
/// filters, which column it is sorted by and which way, and whether it is
/// read as a table or drawn as a chart. Opened from the hub it comes back
/// exactly so, in one tap.
///
/// The period is kept as the shop chose it — "this week", not the dates of
/// the week it was saved in — so Monday's list is always this Monday's.
/// Dates picked by hand stay those dates.
///
/// Kept on the phone, beside the report shelf's favourites (M33), never in
/// the books: how one person likes to read a report is theirs, not the
/// shop's, and must not travel to the other counters with a sync or come
/// back with somebody else's backup. This file is the view and how it is
/// written down; the app keeps the file.
library;

import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_engine.dart';
import 'table_arrangement.dart'; // M67

/// One saved view of one report.
final class SavedReportView {
  const SavedReportView({
    required this.id,
    required this.name,
    required this.kind,
    required this.preset,
    this.custom,
    this.filters = ReportFilters.none,
    this.sortColumn,
    this.sortAscending = false,
    this.asChart = false,
    this.arrangement = TableArrangement.none, // M67
  });

  /// Unique on this phone; never shown.
  final String id;

  /// What the shop called it: "Monday udhaar list".
  final String name;
  final ReportKind kind;

  /// The period as chosen: a preset, worked out afresh on the day it is
  /// opened, or [DatePreset.custom] with [custom]'s dates.
  final DatePreset preset;
  final ReportPeriod? custom;
  final ReportFilters filters;

  /// The column the table was sorted by, by its title — a title survives a
  /// report gaining a column, where a position would sort by the wrong one
  /// — or null for the report's own order.
  final String? sortColumn;
  final bool sortAscending;

  /// Drawn as a chart rather than listed (M46).
  final bool asChart;

  /// The table as the shop arranged it (M67): its columns shown, hidden
  /// and moved, and the filters on them.
  final TableArrangement arrangement;

  /// The days the view covers when the business date is [today].
  ReportPeriod periodOn(BusinessDate today) =>
      (preset == DatePreset.custom ? custom : null) ??
      preset.resolve(today) ??
      ReportPeriod.day(today);

  /// The same view under another name.
  SavedReportView renamed(String name) => SavedReportView(
    id: id,
    name: name,
    kind: kind,
    preset: preset,
    custom: custom,
    filters: filters,
    sortColumn: sortColumn,
    sortAscending: sortAscending,
    asChart: asChart,
    arrangement: arrangement,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'preset': preset.name,
    if (preset == DatePreset.custom && custom != null) ...{
      'from': custom!.from.value,
      'to': custom!.to.value,
    },
    'filters': reportFiltersToJson(filters),
    if (sortColumn != null) 'sort': sortColumn,
    if (sortAscending) 'ascending': true,
    if (asChart) 'chart': true,
    if (!arrangement.isEmpty) 'table': arrangement.toJson(), // M67
  };

  /// Reads what [toJson] wrote, or null for anything that is not a view
  /// this build can open: a report it no longer has, a period it cannot
  /// read, a view with no name. One bad view is dropped, never the rest.
  static SavedReportView? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final kind = ReportKind.values
        .where((k) => k.name == raw['kind'])
        .firstOrNull;
    final preset = DatePreset.values
        .where((p) => p.name == raw['preset'])
        .firstOrNull;
    if (kind == null || preset == null) return null;
    ReportPeriod? custom;
    if (preset == DatePreset.custom) {
      final from = BusinessDate.tryParse('${raw['from']}');
      final to = BusinessDate.tryParse('${raw['to']}');
      if (from == null || to == null || to.value.compareTo(from.value) < 0) {
        return null;
      }
      custom = ReportPeriod(from, to);
    }
    final sort = raw['sort'];
    return SavedReportView(
      id: id,
      name: name.trim(),
      kind: kind,
      preset: preset,
      custom: custom,
      filters: reportFiltersFromJson(raw['filters']),
      sortColumn: sort is String && sort.isNotEmpty ? sort : null,
      sortAscending: raw['ascending'] == true,
      asChart: raw['chart'] == true,
      arrangement: TableArrangement.fromJson(raw['table']), // M67
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedReportView &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.preset == preset &&
      other.custom == custom &&
      other.filters == filters &&
      other.sortColumn == sortColumn &&
      other.sortAscending == sortAscending &&
      other.asChart == asChart &&
      other.arrangement == arrangement;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    preset,
    custom,
    filters,
    sortColumn,
    sortAscending,
    asChart,
    arrangement,
  );

  @override
  String toString() => 'SavedReportView($name: ${kind.name})';
}

/// The views as one file's text, in the order they are listed.
String encodeSavedViews(List<SavedReportView> views) => jsonEncode({
  'views': [for (final v in views) v.toJson()],
});

/// The views [encodeSavedViews] wrote. Anything unreadable is no views at
/// all, and a view this build cannot open is left out: a views file must
/// never stop the reports opening. Two views with one id keep the first.
List<SavedReportView> decodeSavedViews(String text) {
  try {
    final raw = jsonDecode(text);
    final list = raw is Map ? raw['views'] : null;
    if (list is! List) return const [];
    final seen = <String>{};
    return [
      for (final v in list)
        if (SavedReportView.fromJson(v) case final view? when seen.add(view.id))
          view,
    ];
  } on FormatException {
    return const [];
  }
}

/// [filters] as a map of what is set, with each name it was chosen by, so
/// the view reopens saying "Party: Rashid Traders" without a read.
Map<String, Object?> reportFiltersToJson(ReportFilters filters) {
  final f = filters;
  return {
    'partyId': ?f.partyId,
    'partyName': ?f.partyName,
    'itemId': ?f.itemId,
    'itemName': ?f.itemName,
    'category': ?f.category,
    'partyGroup': ?f.partyGroup,
    'transactionType': ?f.transactionType,
    'paymentMode': ?f.paymentMode,
    'userId': ?f.userId,
    'userName': ?f.userName,
    'paymentStatus': ?f.paymentStatus?.name,
    if (f.withBalanceOnly) 'withBalanceOnly': true,
    'location': ?f.location,
    'locationName': ?f.locationName,
    if (f.inStockOnly) 'inStockOnly': true,
    'asOf': ?f.asOf?.value,
    'salesDays': ?f.salesDays,
    'coverDays': ?f.coverDays,
    'fastAt': ?f.fastAt,
    'slowBelow': ?f.slowBelow,
    'serial': ?f.serial,
    'accountId': ?f.accountId,
    'accountName': ?f.accountName,
    'expenseHeadId': ?f.expenseHeadId,
    'expenseHeadName': ?f.expenseHeadName,
    'loanId': ?f.loanId,
    'loanName': ?f.loanName,
    'minAmountPaisa': ?f.minAmount?.inPaisa,
    // M67
    'valuation': ?f.valuation?.name,
    'abcBasis': ?f.abcBasis?.name,
    'abcA': ?f.abcA,
    'abcB': ?f.abcB,
    'lateDays': ?f.lateDays,
  };
}

/// What [reportFiltersToJson] wrote. A field of the wrong shape is read as
/// not set, never as a guess.
ReportFilters reportFiltersFromJson(Object? raw) {
  if (raw is! Map) return ReportFilters.none;
  String? text(String key) {
    final v = raw[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  int? whole(String key) {
    final v = raw[key];
    return v is int ? v : null;
  }

  final asOf = text('asOf');
  final minPaisa = whole('minAmountPaisa');
  return ReportFilters(
    partyId: text('partyId'),
    partyName: text('partyName'),
    itemId: text('itemId'),
    itemName: text('itemName'),
    category: text('category'),
    partyGroup: text('partyGroup'),
    transactionType: text('transactionType'),
    paymentMode: text('paymentMode'),
    userId: text('userId'),
    userName: text('userName'),
    paymentStatus: PaymentStatus.values
        .where((s) => s.name == raw['paymentStatus'])
        .firstOrNull,
    withBalanceOnly: raw['withBalanceOnly'] == true,
    location: text('location'),
    locationName: text('locationName'),
    inStockOnly: raw['inStockOnly'] == true,
    asOf: asOf == null ? null : BusinessDate.tryParse(asOf),
    salesDays: whole('salesDays'),
    coverDays: whole('coverDays'),
    fastAt: whole('fastAt'),
    slowBelow: whole('slowBelow'),
    serial: text('serial'),
    accountId: text('accountId'),
    accountName: text('accountName'),
    expenseHeadId: text('expenseHeadId'),
    expenseHeadName: text('expenseHeadName'),
    loanId: text('loanId'),
    loanName: text('loanName'),
    minAmount: minPaisa == null ? null : Money.paisa(minPaisa),
    // M67
    valuation: StockValuation.values
        .where((v) => v.name == raw['valuation'])
        .firstOrNull,
    abcBasis: AbcBasis.values
        .where((b) => b.name == raw['abcBasis'])
        .firstOrNull,
    abcA: whole('abcA'),
    abcB: whole('abcB'),
    lateDays: whole('lateDays'),
  );
}
