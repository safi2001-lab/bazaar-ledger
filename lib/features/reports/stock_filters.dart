import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../l10n/app_strings.dart';

/// The filters the item and stock reports add (M34), as the filters bar
/// offers them: the day a stock list is read for, how many days of selling
/// a list looks back over and orders for, where fast-moving starts and
/// slow-moving ends, and a serial number typed in.
///
/// Kept apart from the filters bar so the bar carries each of them as one
/// line, and the next group's filters land beside them without touching
/// these. The place filter is a choice from what the shop has, and goes
/// through the bar's own choice sheet with the items and categories.

/// [f]'s name, as its chip reads.
String stockFilterName(AppStrings s, ReportFilter f) => switch (f) {
  ReportFilter.location => s.reportFilterPlace,
  ReportFilter.inStockOnly => s.reportFilterInStock,
  ReportFilter.asOf => s.reportFilterAsOf,
  ReportFilter.salesDays => s.reportFilterSalesDays,
  ReportFilter.coverDays => s.reportFilterCoverDays,
  ReportFilter.fastAt => s.reportFilterFastAt,
  ReportFilter.slowBelow => s.reportFilterSlowBelow,
  ReportFilter.serial => s.reportFilterSerial,
  _ => f.name,
};

/// What [f] is set to in [filters], in words, or null when it is not set.
String? stockFilterValue(AppStrings s, ReportFilter f, ReportFilters filters) {
  String? days(int? n) => n == null ? null : s.reportFilterDaysValue(n);
  String? bills(int? n) => n == null ? null : s.reportFilterBillsValue(n);
  return switch (f) {
    ReportFilter.location => switch (filters.location) {
      null => null,
      ReportFilters.shopFloor => s.placesMain,
      final code => filters.locationName ?? code,
    },
    ReportFilter.asOf => filters.asOf?.value,
    ReportFilter.salesDays => days(filters.salesDays),
    ReportFilter.coverDays => days(filters.coverDays),
    ReportFilter.fastAt => bills(filters.fastAt),
    ReportFilter.slowBelow => bills(filters.slowBelow),
    ReportFilter.serial => filters.serial,
    _ => null,
  };
}

/// What a choice from the place list is called on screen: the shop floor
/// in the shop's own words, anything else by its name.
String placeChoiceLabel(AppStrings s, ReportChoice c) =>
    c.id == ReportFilters.shopFloor ? s.placesMain : c.label;

/// Asks for [f]'s value and answers [filters] with it set, or null when the
/// shopkeeper closed the sheet without choosing. The place filter is not
/// asked here; it is a choice from the shop's own places.
Future<ReportFilters?> pickStockFilter(
  BuildContext context,
  ReportFilter f,
  ReportFilters filters,
) async {
  final s = AppStrings.of(context);
  switch (f) {
    case ReportFilter.asOf:
      final clock = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(appServicesProvider).clock;
      final today = BusinessDate.now(clock);
      DateTime asDate(BusinessDate d) => DateTime.utc(d.year, d.month, d.day);
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime.utc(2000),
        lastDate: asDate(today),
        initialDate: asDate(filters.asOf ?? today),
      );
      if (picked == null) return null;
      return filters.copyWith(
        asOf: BusinessDate.fromUtc(
          DateTime.utc(picked.year, picked.month, picked.day),
          Duration.zero,
        ),
      );
    case ReportFilter.salesDays:
      final n = await _pickNumber(context, stockFilterName(s, f), const [
        7,
        15,
        30,
        60,
        90,
        180,
        365,
      ], s.reportFilterDaysValue);
      return n == null ? null : filters.copyWith(salesDays: n);
    case ReportFilter.coverDays:
      final n = await _pickNumber(context, stockFilterName(s, f), const [
        7,
        15,
        30,
        45,
        60,
        90,
      ], s.reportFilterDaysValue);
      return n == null ? null : filters.copyWith(coverDays: n);
    case ReportFilter.fastAt:
      final n = await _pickNumber(context, stockFilterName(s, f), const [
        5,
        10,
        20,
        30,
        50,
        100,
      ], s.reportFilterBillsValue);
      return n == null ? null : filters.copyWith(fastAt: n);
    case ReportFilter.slowBelow:
      final n = await _pickNumber(context, stockFilterName(s, f), const [
        2,
        3,
        5,
        10,
      ], s.reportFilterBillsValue);
      return n == null ? null : filters.copyWith(slowBelow: n);
    case ReportFilter.serial:
      final typed = await showDialog<String>(
        context: context,
        builder: (_) => _SerialDialog(initial: filters.serial ?? ''),
      );
      final serial = typed?.trim() ?? '';
      return serial.isEmpty ? null : filters.copyWith(serial: serial);
    default:
      return null;
  }
}

Future<int?> _pickNumber(
  BuildContext context,
  String title,
  List<int> options,
  String Function(int) label,
) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          BlSectionHeader(title),
          for (final n in options)
            ListTile(
              title: Text(label(n)),
              onTap: () => Navigator.of(context).pop(n),
            ),
        ],
      ),
    ),
  ),
);

/// A serial or IMEI number typed, or pasted, whole or its last digits.
class _SerialDialog extends StatefulWidget {
  const _SerialDialog({required this.initial});

  final String initial;

  @override
  State<_SerialDialog> createState() => _SerialDialogState();
}

class _SerialDialogState extends State<_SerialDialog> {
  late final _typed = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.reportFilterSerial),
      content: BlField(
        controller: _typed,
        label: s.reportFilterSerial,
        hint: s.reportFilterSerialHint,
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_typed.text),
          child: Text(s.actionSearch),
        ),
      ],
    );
  }
}
