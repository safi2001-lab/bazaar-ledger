import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'cart.dart';
import 'scheme_book.dart';

/// The shop's schemes where the cashier can see them (M43).
///
/// Nothing here decides anything. What a scheme gives is worked out by the
/// pure book (schemes.dart) from the lines on the counter, by the same call
/// the bill is written with (`Cart.forBooks`), so what the cashier is shown
/// is what goes on the paper. These widgets only say it, and let the
/// cashier take it off.

/// What the bill as rung takes off the shelf, by the cart's own drafts.
List<SaleLineDraft>? _rung(Cart cart, UnitConverter? units) {
  try {
    return [for (final l in cart.lines) ...l.toDrafts(units)];
  } on Object {
    // A unit that will not convert is the sale path's to refuse, in words.
    return null;
  }
}

/// Under a line on the counter: the bonus it earns, marked free, with a way
/// to take it off — or, when it earns none yet, the scheme it is on, so the
/// cashier can tell a customer buying nine that the tenth brings one free.
///
/// Taking a bonus off gives less away, so any cashier may, and it is put
/// back with a tap. Shown under the line of the item that earns it, even
/// when the goods given are another item's.
class CounterBonus extends ConsumerWidget {
  const CounterBonus({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // M54: a bill made from challans gives the bonus they sent, which is
    // shown as it went — under its own item's line, or the last line for a
    // free item the bill has no paid line of — with no cross, because those
    // goods are already at the customer's.
    final sent = ref.watch(cartProvider.select((c) => c.sentBonus));
    if (sent != null) return _SentBonus(itemId: itemId, sent: sent);

    final book = ref.watch(schemeBookProvider).valueOrNull;
    final offer = book?.bonuses[itemId];
    if (book == null || offer == null) return const SizedBox.shrink();
    final cart = ref.watch(cartProvider);
    final rung = _rung(cart, ref.watch(unitConverterProvider).valueOrNull);
    if (rung == null) return const SizedBox.shrink();

    final s = AppStrings.of(context);
    final t = context.bl;
    final paid = SchemeBook.paidBaseOf(rung)[itemId] ?? Qty.zero;
    final grant = book.bonusFor({itemId: paid}).firstOrNull;
    final waived = cart.bonusWaived.contains(itemId);
    final notifier = ref.read(cartProvider.notifier);

    if (grant == null) {
      return Padding(
        padding: const EdgeInsets.only(
          left: BlTokens.space3,
          bottom: BlTokens.space1,
        ),
        child: Text(
          s.bonusSchemeHint(offer.rule.label),
          style: TextStyle(fontSize: 12, color: t.inkMuted),
        ),
      );
    }

    final what =
        '${grant.offer.freeItemName} ${grant.qty.display} '
        '${grant.offer.freeUnitCode}';
    if (waived) {
      return Padding(
        padding: const EdgeInsets.only(left: BlTokens.space3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.bonusTakenOff(what),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ),
            TextButton(
              onPressed: () => notifier.setBonusWaived(itemId, waived: false),
              child: Text(s.bonusPutBack),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(
        left: BlTokens.space3,
        bottom: BlTokens.space2,
      ),
      padding: const EdgeInsets.only(left: BlTokens.space3),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.card_giftcard, size: 18, color: t.accent),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Text(
              s.bonusOnCounter(what),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
          ),
          BlMoney(Money.zero, size: 14),
          BlIconButton(
            icon: Icons.close,
            label: s.bonusTakeOff,
            onPressed: () => notifier.setBonusWaived(itemId, waived: true),
          ),
        ],
      ),
    );
  }
}

/// M54: the free lines a challan sent, under [itemId]'s line on a bill made
/// from it.
class _SentBonus extends ConsumerWidget {
  const _SentBonus({required this.itemId, required this.sent});

  final String itemId;
  final List<SaleLineDraft> sent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider.select((c) => c.lines));
    final paid = {for (final l in lines) l.item.id};
    final last = lines.isEmpty ? null : lines.last.item.id;
    final here = [
      for (final f in sent)
        if (f.itemId == itemId || (!paid.contains(f.itemId) && itemId == last))
          f,
    ];
    if (here.isEmpty) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in here)
          Container(
            margin: const EdgeInsets.only(
              left: BlTokens.space3,
              bottom: BlTokens.space2,
            ),
            padding: const EdgeInsets.all(BlTokens.space2),
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(BlTokens.radiusMd),
            ),
            child: Row(
              children: [
                Icon(Icons.card_giftcard, size: 18, color: t.accent),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: Text(
                    s.bonusSentOnChallan(
                      '${f.itemName} ${f.qty.display} ${f.unitCode}',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                BlMoney(Money.zero, size: 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// On the payment sheet, under what is due: the shop's discount on a big
/// bill, said before the money is taken — what it is, from what figure,
/// and a way to take it off. Under the first slab, how far the bill is
/// from it, which is the sentence a shopkeeper says across the counter
/// anyway ("Rs 300 ka aur le lein, 2% kam ho jayega").
///
/// Nothing at all for a shop with no bill slabs, or a bill whose discount
/// the cashier typed: their figure is the bill's.
class BillSlabRow extends ConsumerWidget {
  const BillSlabRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(schemeBookProvider).valueOrNull;
    final cart = ref.watch(cartProvider);
    if (book == null || book.billSlabs.isEmpty) return const SizedBox.shrink();
    if (cart.billDiscount.isPositive) return const SizedBox.shrink();
    final rung = _rung(cart, ref.watch(unitConverterProvider).valueOrNull);
    if (rung == null) return const SizedBox.shrink();

    final s = AppStrings.of(context);
    final t = context.bl;
    final notifier = ref.read(cartProvider.notifier);
    final value = SchemeBook.billValueOf(rung);
    final hit = book.billSlabFor(value);

    // The words on a line of their own, and the figure and the button
    // under them, so neither is squeezed off a small phone at 200%.
    Widget line(String text, {Widget? action, Money? amount}) => Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_offer_outlined, size: 18, color: t.accent),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(fontSize: 13, color: t.ink)),
                if (amount != null || action != null)
                  Wrap(
                    spacing: BlTokens.space3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (amount != null) BlMoney(-amount, size: 14),
                      ?action,
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (hit == null) {
      final next = book.billSlabs.firstWhere(
        (b) => b.from > value,
        orElse: () => book.billSlabs.last,
      );
      if (next.from <= value) return const SizedBox.shrink();
      return line(
        s.billSlabNext((next.from - value).amountOnly, next.percentLabel),
      );
    }
    if (cart.slabWaived) {
      return line(
        s.billSlabTakenOff(hit.slab.percentLabel),
        action: TextButton(
          onPressed: () => notifier.setSlabWaived(waived: false),
          child: Text(s.bonusPutBack),
        ),
      );
    }
    return line(
      s.billSlabApplied(hit.slab.percentLabel, hit.slab.from.amountOnly),
      amount: hit.discount,
      action: TextButton(
        onPressed: () => notifier.setSlabWaived(waived: true),
        child: Text(s.billSlabTakeOff),
      ),
    );
  }
}
