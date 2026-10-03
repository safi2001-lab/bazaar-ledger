import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/item_scheme_screen.dart' show showSchemeItemPicker;
import 'loyalty_providers.dart';

/// One customer's own prices (M66): every item agreed with them at a rate
/// of its own, to add to, change and take off.
///
/// Reached from their khata and their details. The counter reads the same
/// list when they are picked, and prices their lines from it before their
/// tier and the item's slabs (party_prices.dart has the order).
class PartyPricesScreen extends ConsumerWidget {
  const PartyPricesScreen({super.key, required this.party});

  final PartySummary party;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ItemSummary item,
    Rate? rate,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PriceSheet(party: party, item: item, rate: rate),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayEdit = ref.watch(appServicesProvider).loyalty.maySetPrices;
    final list = ref.watch(partyPriceListProvider(party.id));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text('${s.partyPricesTitle} · ${party.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            BlTokens.space6,
          ),
          children: [
            Text(
              s.partyPricesIntro,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (!mayEdit) ...[
              const SizedBox(height: BlTokens.space3),
              BlOfflineNote(message: s.partyPricesOwnerOnly),
            ],
            const SizedBox(height: BlTokens.space4),
            list.when(
              loading: () => const BlSkeletonList(rows: 2),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) => rows.isEmpty
                  ? Text(
                      s.partyPricesNone,
                      style: TextStyle(fontSize: 14, color: t.inkMuted),
                    )
                  : Column(
                      children: [
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: BlCard(
                              onTap: mayEdit
                                  ? () => unawaited(
                                      _edit(context, ref, r.item, r.rate),
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.item.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: t.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: BlTokens.space2),
                                  // Flexible and scaled, like every price
                                  // on the counter: a six-figure rate at
                                  // 200% must not push the name off.
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        s.partyPriceEach(
                                          r.rate.amountOnly,
                                          r.item.unitCode,
                                        ),
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: t.accent,
                                          fontFeatures: BlTokens.tabular,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (mayEdit) ...[
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.partyPricesAdd,
                icon: Icons.add,
                kind: BlButtonKind.secondary,
                onPressed: () async {
                  final item = await showSchemeItemPicker(context);
                  if (item == null || !context.mounted) return;
                  final had =
                      (await ref
                              .read(appServicesProvider)
                              .loyalty
                              .pricesOf(party.id))
                          .rateFor(item.id);
                  if (!context.mounted) return;
                  await _edit(context, ref, item, had);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One item's price for the customer: typed, kept, or taken off.
class _PriceSheet extends ConsumerStatefulWidget {
  const _PriceSheet({required this.party, required this.item, this.rate});

  final PartySummary party;
  final ItemSummary item;
  final Rate? rate;

  @override
  ConsumerState<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends ConsumerState<_PriceSheet> {
  late final TextEditingController _rate = TextEditingController(
    text: widget.rate?.amountOnly.replaceAll(',', '') ?? '',
  );
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save({required bool remove}) async {
    final s = AppStrings.of(context);
    final rate = remove ? null : Rate.tryParse(_rate.text.trim());
    if (!remove && (rate == null || rate.inMilliPaisa <= 0)) {
      setState(() => _problem = s.loyaltyProblemFigures);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .loyalty
          .setPartyPrice(widget.party.id, widget.item.id, rate);
      if (!mounted) return;
      ref.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.partyPriceSaved)));
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final item = widget.item;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(item.name),
          Text(
            s.partyPriceEach(item.saleRate.amountOnly, item.unitCode),
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _rate,
            label: s.partyPriceRate(item.unitCode),
            numeric: true,
            autofocus: true,
          ),
          if (_problem != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(_problem!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: BlTokens.space4),
          Row(
            children: [
              if (widget.rate != null) ...[
                Expanded(
                  child: BlButton(
                    label: s.partyPriceRemove,
                    kind: BlButtonKind.danger,
                    onPressed: _busy ? null : () => _save(remove: true),
                  ),
                ),
                const SizedBox(width: BlTokens.space3),
              ],
              Expanded(
                child: BlButton(
                  label: s.actionSave,
                  busy: _busy,
                  onPressed: _busy ? null : () => _save(remove: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
