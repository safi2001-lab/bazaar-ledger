import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// The choices M67's reports add to the filters bar: how the shelf is
/// valued, what the ABC classes rank by and where their lines fall, and
/// how late udhaar must be before the attention list names it.
///
/// Kept apart from the bar, as M34's stock filters are, so the bar carries
/// each as one line. A choice that would show what goods cost (a valuation
/// at cost, a ranking by profit) is not offered to a role that may not see
/// costs; the engine refuses or strikes it for them as well.

/// [f]'s name, as its chip reads.
String insightFilterName(AppStrings s, ReportFilter f) => switch (f) {
  ReportFilter.valuation => s.reportFilterValuation,
  ReportFilter.abcBasis => s.reportFilterAbcBasis,
  ReportFilter.abcBands => s.reportFilterAbcBands,
  ReportFilter.lateDays => s.reportFilterLateDays,
  _ => f.name,
};

/// What [f] is set to in [filters], in words, or null when it is not set.
String? insightFilterValue(
  AppStrings s,
  ReportFilter f,
  ReportFilters filters,
) => switch (f) {
  ReportFilter.valuation => switch (filters.valuation) {
    final v? => valuationLabel(s, v),
    null => null,
  },
  ReportFilter.abcBasis => switch (filters.abcBasis) {
    AbcBasis.sales => s.reportAbcBySales,
    AbcBasis.margin => s.reportAbcByProfit,
    null => null,
  },
  ReportFilter.abcBands =>
    filters.abcA == null && filters.abcB == null
        ? null
        : s.reportFilterAbcBandsValue(
            filters.abcA ?? AbcDefaults.a,
            filters.abcB ?? AbcDefaults.b,
          ),
  ReportFilter.lateDays => switch (filters.lateDays) {
    final n? => s.reportFilterDaysValue(n),
    null => null,
  },
  _ => null,
};

/// A valuation as the shop reads it.
String valuationLabel(AppStrings s, StockValuation v) => switch (v) {
  StockValuation.cost => s.reportValuationCost,
  StockValuation.costWithTax => s.reportValuationCostTax,
  StockValuation.salePrice => s.reportValuationSale,
  StockValuation.salePriceWithTax => s.reportValuationSaleTax,
};

/// Asks for [f]'s value and answers [filters] with it set, or null when
/// the sheet was closed without a choice.
Future<ReportFilters?> pickInsightFilter(
  BuildContext context,
  ReportFilter f,
  ReportFilters filters,
) async {
  final s = AppStrings.of(context);
  final costs = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appServicesProvider).can(Permission.seeCosts);
  switch (f) {
    case ReportFilter.valuation:
      final v = await _pickOne(context, insightFilterName(s, f), [
        for (final v in StockValuation.values)
          if (costs || !v.isCost) (v, valuationLabel(s, v)),
      ]);
      return v == null ? null : filters.copyWith(valuation: v);
    case ReportFilter.abcBasis:
      final b = await _pickOne(context, insightFilterName(s, f), [
        (AbcBasis.sales, s.reportAbcBySales),
        if (costs) (AbcBasis.margin, s.reportAbcByProfit),
      ]);
      return b == null ? null : filters.copyWith(abcBasis: b);
    case ReportFilter.abcBands:
      final lines = await showDialog<(int, int)>(
        context: context,
        builder: (_) => _AbcLinesDialog(
          a: filters.abcA ?? AbcDefaults.a,
          b: filters.abcB ?? AbcDefaults.b,
        ),
      );
      return lines == null
          ? null
          : filters.copyWith(abcA: lines.$1, abcB: lines.$2);
    case ReportFilter.lateDays:
      final n = await _pickOne(context, insightFilterName(s, f), [
        for (final n in const [7, 15, 30, 45, 60, 90])
          (n, s.reportFilterDaysValue(n)),
      ]);
      return n == null ? null : filters.copyWith(lateDays: n);
    default:
      return null;
  }
}

Future<T?> _pickOne<T>(
  BuildContext context,
  String title,
  List<(T, String)> options,
) => showModalBottomSheet<T>(
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
          for (final (value, label) in options)
            ListTile(
              title: Text(label),
              onTap: () => Navigator.of(context).pop(value),
            ),
        ],
      ),
    ),
  ),
);

/// Where class A ends and where class B ends, in whole per cent.
class _AbcLinesDialog extends StatefulWidget {
  const _AbcLinesDialog({required this.a, required this.b});

  final int a;
  final int b;

  @override
  State<_AbcLinesDialog> createState() => _AbcLinesDialogState();
}

class _AbcLinesDialogState extends State<_AbcLinesDialog> {
  late final _a = TextEditingController(text: '${widget.a}');
  late final _b = TextEditingController(text: '${widget.b}');

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  (int, int)? get _lines {
    final a = int.tryParse(_a.text.trim());
    final b = int.tryParse(_b.text.trim());
    if (a == null || b == null || a < 1 || b > 100 || a >= b) return null;
    return (a, b);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final lines = _lines;
    return AlertDialog(
      title: Text(s.reportFilterAbcBands),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlField(
              controller: _a,
              label: s.reportAbcLineA,
              numeric: true,
              decimals: 0,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _b,
              label: s.reportAbcLineB,
              numeric: true,
              decimals: 0,
              onChanged: (_) => setState(() {}),
            ),
            if (lines == null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(
                s.reportAbcLinesWrong,
                style: TextStyle(fontSize: 13, color: t.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        FilledButton(
          onPressed: lines == null
              ? null
              : () => Navigator.of(context).pop(lines),
          child: Text(s.actionSave),
        ),
      ],
    );
  }
}
