import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/shelf_guard.dart';
import 'give_goods_sheet.dart';
import 'price_goods_sheet.dart';

/// Goods on the khata now, priced later (M55).
///
/// "Das kilo ghee de diya, rate baad mein." The goods are handed over on a
/// delivery challan whose lines carry no rate (`goods_given.dart` in
/// pk_domain says why a challan is the right document), so they leave the
/// shelf at what they cost and nothing is owed. This file shows them on the
/// khata, apart from the money: what was given, how much, and that its rate
/// is still to be agreed — and, beside them, any challan the counter priced
/// that is not billed yet, because a customer holding goods on a challan is
/// told about them the same way.

/// Every challan to one customer not yet billed, oldest first.
final goodsGivenProvider = FutureProvider.autoDispose
    .family<List<GoodsGiven>, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).collections.goodsGivenTo(partyId);
    });

/// Every customer holding goods with no rate on them yet, oldest first.
final unpricedPartiesProvider = FutureProvider.autoDispose<List<UnpricedParty>>(
  (ref) async {
    ref.watch(refreshTickProvider);
    return ref.watch(appServicesProvider).collections.unpricedParties();
  },
);

/// "10 kg", as a line of goods given is said.
String goodsQty(GoodsGivenLine line) => '${line.qty.display} ${line.unitCode}';

/// The khata's card for goods given and not yet billed.
///
/// Kept apart from the balance above it and never added to it: these are
/// not yet a debt. With nothing given, it is the one button that gives some.
class GoodsGivenCard extends ConsumerWidget {
  const GoodsGivenCard({super.key, required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final mayGive = services.can(Permission.sell);
    final goods =
        ref.watch(goodsGivenProvider(party.id)).valueOrNull ??
        const <GoodsGiven>[];

    if (goods.isEmpty) {
      if (!mayGive) return const SizedBox.shrink();
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: BlButton(
          label: s.goodsGivenRateLater,
          icon: Icons.scale_outlined,
          kind: BlButtonKind.ghost,
          onPressed: () => unawaited(showGiveGoodsSheet(context, party: party)),
        ),
      );
    }

    final unpriced = goods.fold(0, (n, g) => n + g.unpricedCount);
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.goodsGivenTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space1),
          Text(
            s.goodsGivenNotOwed,
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          if (unpriced > 0) ...[
            const SizedBox(height: BlTokens.space2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: BlChip(
                s.goodsGivenUnpriced(unpriced),
                tone: BlChipTone.warn,
                icon: Icons.scale_outlined,
              ),
            ),
          ],
          for (final g in goods) ...[
            const SizedBox(height: BlTokens.space3),
            Text(
              '${g.docNo} · ${shortDate(g.dateLocal)}',
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
            for (final line in g.lines)
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.itemName} · ${goodsQty(line)}',
                        style: TextStyle(fontSize: 14, color: t.ink),
                      ),
                    ),
                    const SizedBox(width: BlTokens.space2),
                    if (line.isUnpriced)
                      Text(
                        s.goodsGivenRateMissing,
                        style: TextStyle(fontSize: 12, color: t.warning),
                      )
                    else
                      BlMoney(line.amount, size: 14),
                  ],
                ),
              ),
          ],
          const SizedBox(height: BlTokens.space3),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              if (mayGive)
                BlButton(
                  label: unpriced > 0 ? s.goodsGivenPrice : s.goodsGivenBill,
                  icon: Icons.price_change_outlined,
                  onPressed: () => unawaited(
                    showPriceGoodsSheet(context, party: party, goods: goods),
                  ),
                ),
              if (mayGive)
                BlButton(
                  label: s.goodsGivenMore,
                  icon: Icons.add,
                  kind: BlButtonKind.ghost,
                  onPressed: () =>
                      unawaited(showGiveGoodsSheet(context, party: party)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The counter's "Rate baad mein" (M55): the goods on the counter handed to
/// its customer with the rate still to be agreed.
///
/// What the tender sheet's own "Challan banayein" does, with the rates left
/// off: the customer is required, a loose line is refused, the shelf is
/// asked (M53), the counter is cleared and the sheet closed. Returns null
/// when the goods went; otherwise what to say, empty when the shelf's own
/// question already said it.
Future<String?> giveFromCounter(BuildContext context, WidgetRef ref) async {
  final s = AppStrings.of(context);
  final cart = ref.read(cartProvider);
  final units = ref.read(unitConverterProvider).valueOrNull;
  final firm = ref.read(firmProvider).valueOrNull;
  if (firm == null || cart.isEmpty) return '';
  if (cart.partyId == null) return s.challanNeedsCustomer;
  if (cart.lines.any((l) => l.isLoose)) return s.looseNotKept;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final cartNotifier = ref.read(cartProvider.notifier);
  final container = ProviderScope.containerOf(context, listen: false);
  if (!await shelfAllowsBill(context, ref, cart, forChallan: true)) return '';
  try {
    final services = ref.read(appServicesProvider);
    final given = await services.collections.giveRateLater(
      SaleDraft(
        lines: [for (final l in cart.lines) ...l.toDrafts(units)],
        partyId: cart.partyId,
        partyName: cart.partyName,
        roundToRupee: firm.roundInvoiceToRupee,
      ),
    );
    cartNotifier.clear();
    container.bumpRefresh();
    messenger.showSnackBar(
      SnackBar(content: Text(s.giveGoodsSaved(given.docNo))),
    );
    navigator.pop();
    return null;
  } on Object catch (error) {
    return '$error';
  }
}

/// The lines a statement adds about goods given and not yet priced (M55),
/// in [s]'s words: the account in money is not the whole of what they hold.
List<String> unpricedNotes(AppStrings s, List<GoodsGiven> goods) {
  final lines = [
    for (final g in goods)
      for (final l in g.lines)
        if (l.isUnpriced) '${l.itemName} ${goodsQty(l)} (${g.docNo})',
  ];
  if (lines.isEmpty) return const [];
  return [s.statementUnpriced(lines.length, lines.join(', '))];
}
