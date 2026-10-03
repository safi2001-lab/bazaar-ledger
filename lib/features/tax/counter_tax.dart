import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';

/// Pakistan's rules, as the counter shows them (M59): the printed price on a
/// Third Schedule line, the province's tax on a service at the rate of the
/// tender, and the buyer's name on a bill over Rs 100,000.
///
/// Each is a small widget the counter's own screens put in one place, so
/// the billing screens carry a line each and the rules live here.

/// "MRP Rs 120" under a Third Schedule line, and in red when the line is
/// being sold above it.
///
/// A warning and never a block: the MRP typed into the item may be last
/// year's, and the customer is standing there. The tax is still worked out
/// on the printed price (third_schedule.dart), and the cashier sees that the
/// price is above it before the money is taken.
class ThirdScheduleLineNote extends ConsumerWidget {
  const ThirdScheduleLineNote({super.key, required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mrp = line.item.mrp;
    if (!line.item.isThirdSchedule || line.isLoose || mrp == null) {
      return const SizedBox.shrink();
    }
    final s = AppStrings.of(context);
    final t = context.bl;
    final above = sellsAboveMrp(
      mrp: mrp,
      baseQty: _baseQty(ref),
      lineValue: line.net,
    );
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space1),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          above
              ? '${s.mrpOnLine(mrp.amountOnly)} · ${s.mrpAbove}'
              : s.mrpOnLine(mrp.amountOnly),
          style: TextStyle(
            fontSize: 12,
            fontWeight: above ? FontWeight.w600 : FontWeight.w400,
            color: above ? t.danger : t.inkMuted,
          ),
        ),
      ),
    );
  }

  /// What leaves the shelf, in the unit the MRP is printed for: a carton of
  /// 24 is 24 packs.
  Qty _baseQty(WidgetRef ref) {
    try {
      return line.toDraft(ref.watch(unitConverterProvider).valueOrNull).baseQty;
    } on Object {
      return line.qty;
    }
  }
}

/// The province's tax on the bill's services at the mode picked, one row
/// per rate — "PRA 8% (card)" — under the amount due on the payment sheet,
/// so the cashier sees why the total moved when the mode did. Nothing when
/// the bill has no service tax.
class ServiceTaxNote extends StatelessWidget {
  const ServiceTaxNote({super.key, required this.sale});

  final CalculatedSale sale;

  @override
  Widget build(BuildContext context) {
    final rows = <String, Money>{};
    for (final l in sale.lines) {
      for (final tax in l.taxes) {
        if (tax.kind != TaxKind.provincialSt) continue;
        final label = serviceTaxLabel(tax.code, tax.rateBp);
        rows[label] = (rows[label] ?? Money.zero) + tax.amount;
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: Column(
        children: [
          for (final MapEntry(key: label, value: amount) in rows.entries)
            BlAmountRow(
              padding: const EdgeInsets.symmetric(vertical: 2),
              label: label,
              labelStyle: TextStyle(fontSize: 13, color: t.inkMuted),
              child: BlMoney(
                amount,
                size: 13,
                colour: t.inkMuted,
                semanticPrefix: label,
              ),
            ),
        ],
      ),
    );
  }
}

/// The buyer's name, and their CNIC if they will give it, on a walk-in bill
/// over Rs 100,000.
///
/// [required] for a shop registered for sales tax, where FBR asks for it and
/// the sale path refuses the bill without it; a warning for any other shop,
/// which may leave it blank.
class BuyerNameFields extends StatelessWidget {
  const BuyerNameFields({
    super.key,
    required this.name,
    required this.cnic,
    required this.required,
    this.onChanged,
  });

  final TextEditingController name;
  final TextEditingController cnic;
  final bool required;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Container(
      margin: const EdgeInsets.only(top: BlTokens.space3),
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.buyerNameTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.warning,
            ),
          ),
          Text(
            required ? s.buyerNameRequiredHint : s.buyerNameWarnHint,
            style: TextStyle(fontSize: 12, color: t.warning),
          ),
          const SizedBox(height: BlTokens.space2),
          BlField(
            controller: name,
            label: s.buyerName,
            textInputAction: TextInputAction.next,
            onChanged: (_) => onChanged?.call(),
          ),
          const SizedBox(height: BlTokens.space2),
          BlField(
            controller: cnic,
            label: s.buyerCnic,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged?.call(),
          ),
        ],
      ),
    );
  }
}

/// What is wrong with the buyer's name and CNIC as typed, in words, or null
/// when the bill may go: a name for a registered shop, and a CNIC that is
/// thirteen digits if one is typed at all.
String? buyerNameProblem(
  AppStrings s, {
  required String name,
  required String cnic,
  required bool required,
}) {
  if (required && name.trim().isEmpty) return s.buyerNameMissing;
  if (cnic.trim().isNotEmpty && tidyCnic(cnic) == null) return s.buyerCnicWrong;
  return null;
}
