import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../reports/reports_screen.dart';

final _thisMonthTurnover = FutureProvider.autoDispose<Money>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.reports)) return Money.zero;
  final today = BusinessDate.now(services.clock);
  final table = await services.reports.run(
    ReportKind.tajirDost,
    firmId: firm.id,
    period: ReportPeriod.monthOf(today),
    today: today,
  );
  return (table.totals.single.cells[1] as Money?) ?? Money.zero;
});

/// The shop's tax standing, and what it owes.
///
/// Everything here is computed on this phone and nothing is sent anywhere:
/// the figures are for the shop or its accountant to file.
class TaxScreen extends ConsumerStatefulWidget {
  const TaxScreen({super.key});

  @override
  ConsumerState<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends ConsumerState<TaxScreen> {
  final _wht = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _wht.dispose();
    super.dispose();
  }

  Future<void> _set(String column, bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).updateFirm({column: value ? 1 : 0});
      container.bumpRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final firm = ref.watch(firmProvider).valueOrNull;
    final turnover = ref.watch(_thisMonthTurnover).valueOrNull ?? Money.zero;
    final fixedTax = turnover.percentBp(tajirDostBp);
    final wht = Money.tryParse(_wht.text) ?? Money.zero;
    final payable = fixedTax - wht;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.taxTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlOfflineNote(message: s.taxNeverSent),
            const SizedBox(height: BlTokens.space3),
            SwitchListTile.adaptive(
              value: firm?.isSalesTaxRegistered ?? false,
              onChanged: _busy
                  ? null
                  : (v) => unawaited(_set('is_sales_tax_registered', v)),
              contentPadding: EdgeInsets.zero,
              title: Text(s.taxRegistered),
              subtitle: Text(s.taxRegisteredHint),
            ),
            SwitchListTile.adaptive(
              value: firm?.pricesIncludeTax ?? false,
              onChanged: _busy || !(firm?.isSalesTaxRegistered ?? false)
                  ? null
                  : (v) => unawaited(_set('prices_include_tax', v)),
              contentPadding: EdgeInsets.zero,
              title: Text(s.taxPricesInclude),
            ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.taxTajirDost),
            const SizedBox(height: BlTokens.space2),
            BlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.taxTurnoverThisMonth,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  BlMoney(turnover, size: 20, withSymbol: true),
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    s.taxFixedAtOnePercent,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  BlMoney(fixedTax, size: 20, withSymbol: true),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _wht,
                    label: s.taxUtilityWht,
                    numeric: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  Text(
                    s.taxToPay,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  BlMoney(
                    payable.isNegative ? Money.zero : payable,
                    size: 26,
                    withSymbol: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            for (final kind in [ReportKind.salesTax, ReportKind.tajirDost])
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: BlButton(
                  label: reportName(s, kind),
                  icon: Icons.receipt_long_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportScreen(kind: kind),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
