import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart';

/// A bill rung again without typing it twice (M36).
///
/// A wholesaler's customer rings on Thursday and says "same as last week";
/// a kiryana sends the same monthly list; a bill was cancelled by mistake
/// and has to be made again. Each was thirty lines of searching and typing
/// while the customer waited. Now the bill's lines, units, quantities and
/// customer go onto the counter as a NEW bill — new number, every check the
/// counter makes, nothing written until the cashier takes the money — from
/// the bill itself, from its row in the sales list, or from the counter once
/// the customer is named ("Pichhla order dobara").
///
/// The bill it came from is never touched. A posted bill is the paper the
/// customer holds, and this is a second piece of paper, not an edit.

/// Which prices a bill rung again is at.
///
/// Asked, not assumed: "same as last time" means the same goods to every
/// shopkeeper and the same PRICE to some. Today's is the default — what the
/// counter would charge this customer for a line rung fresh, at their price
/// list and with their standing discount — because a price list that moved
/// since last week moved for a reason. The old prices are one tap away, with
/// the bill's own discounts, for the customer who was promised them.
enum CopyRates { today, asBilled }

/// Why a line of the old bill did not come onto the counter.
enum CopyLeftOut {
  /// The item was archived or deleted since; the counter would not offer it.
  gone,

  /// A free line; the counter has no free lines.
  free,

  /// A phone or anything sold by serial: the piece sold is not on the shelf,
  /// so the cashier scans the one being sold now.
  serial,

  /// The same item twice at different prices or units; the counter holds an
  /// item once.
  twice,
}

/// The bill as the counter will hold it.
final class CounterCopy {
  const CounterCopy({
    required this.lines,
    required this.billDiscount,
    this.party,
    this.leftOut = const [],
    this.lostCustomer,
  });

  final List<CartLine> lines;
  final Money billDiscount;
  final PartySummary? party;

  /// The lines that did not come, by name and why.
  final List<({String name, CopyLeftOut why})> leftOut;

  /// The customer the bill named, when they are no longer in the khata.
  final String? lostCustomer;
}

/// Reads [copy] onto counter lines, priced the way [rates] says.
///
/// [piecesBack] is for a bill being put right: cancelling it has just put
/// its serial-numbered pieces back on the shelf, so the corrected bill
/// sells the very same ones. A bill merely copied never carries a piece —
/// that phone was sold.
Future<CounterCopy> counterCopyOf(
  AppServices services,
  String firmId,
  BillCopy copy, {
  required CopyRates rates,
  bool piecesBack = false,
  UnitConverter? units,
}) async {
  final party = copy.partyId == null
      ? null
      : await services.queries.partyById(firmId, copy.partyId!);
  final tier = party?.priceTier ?? PriceTier.retail;
  final standing = party?.defaultDiscountBp ?? 0;
  final asBilled = rates == CopyRates.asBilled;
  final billed = asBilled
      ? discountsAsBilled(
          copy.lines,
          billDiscount: copy.billDiscount,
          roundingMode: copy.roundingMode,
        )
      : null;

  final lines = <CartLine>[];
  final leftOut = <({String name, CopyLeftOut why})>[];
  var looseKey = 0;

  for (var i = 0; i < copy.lines.length; i++) {
    final l = copy.lines[i];
    final discount = billed?.lines[i];
    if (l.isFree) {
      leftOut.add((name: l.name, why: CopyLeftOut.free));
      continue;
    }

    // Khula maal (M37): what it was called and what it came to. There is no
    // price list for it to move along, so "today" is the price typed then.
    if (l.isLoose) {
      looseKey++;
      lines.add(
        CartLine.loose(
          key: 'loose-$looseKey',
          name: l.name,
          qty: l.qty,
          rate: l.rate,
          unitId: l.unitId,
          unitCode: l.unitCode,
        ).copyWith(
          discountBp: discount?.discountBp ?? 0,
          explicitDiscount: discount?.explicitDiscount,
        ),
      );
      continue;
    }

    final item = l.itemGone
        ? null
        : await services.queries.itemById(firmId, l.itemId!);
    if (item == null) {
      leftOut.add((name: l.name, why: CopyLeftOut.gone));
      continue;
    }

    if (item.tracksSerial) {
      if (!piecesBack || l.lotId == null) {
        leftOut.add((name: l.name, why: CopyLeftOut.serial));
        continue;
      }
      // One line per piece on the bill; one line of pieces on the counter.
      final at = lines.indexWhere((c) => c.item.id == item.id);
      final rate = asBilled ? l.rate : priceFor(item, tier);
      if (at < 0) {
        lines.add(
          CartLine(
            item: item,
            qty: Qty.one,
            rate: rate,
            discountBp: discount?.discountBp ?? standing,
            explicitDiscount: discount?.explicitDiscount,
            lotIds: [l.lotId!],
            lotLabels: [l.lotNo ?? ''],
          ),
        );
      } else {
        final had = lines[at];
        lines[at] = had.copyWith(
          qty: Qty.units(had.lotIds.length + 1),
          lotIds: [...had.lotIds, l.lotId!],
          lotLabels: [...had.lotLabels, l.lotNo ?? ''],
          explicitDiscount:
              had.explicitDiscount == null && discount?.explicitDiscount == null
              ? null
              : (had.explicitDiscount ?? Money.zero) +
                    (discount?.explicitDiscount ?? Money.zero),
        );
      }
      continue;
    }

    // Sold in another unit (a maund of what the shelf counts in kilos): the
    // quantity stays as billed, in that unit, and today's price is carried
    // into it exactly or the line keeps the price it was billed at.
    final converted = l.unitId != null && l.unitId != item.unitId;
    Rate rate;
    if (asBilled) {
      rate = l.rate;
    } else if (!converted) {
      rate = priceFor(item, tier);
    } else {
      rate = l.rate;
      if (units != null) {
        try {
          rate = units.convertRate(
            priceFor(item, tier),
            fromUnitId: item.unitId,
            toUnitId: l.unitId!,
            itemId: item.id,
          );
        } on Object {
          rate = l.rate;
        }
      }
    }
    final line = CartLine(
      item: item,
      qty: l.qty,
      rate: rate,
      discountBp: discount?.discountBp ?? standing,
      explicitDiscount: discount?.explicitDiscount,
      unitId: converted ? l.unitId : null,
      unitCode: converted ? l.unitCode : null,
    );

    final at = lines.indexWhere((c) => c.item.id == item.id);
    if (at < 0) {
      lines.add(line);
      continue;
    }
    final had = lines[at];
    if (had.unitId == line.unitId &&
        had.rate == line.rate &&
        had.discountBp == line.discountBp &&
        had.explicitDiscount == null &&
        line.explicitDiscount == null) {
      lines[at] = had.copyWith(qty: had.qty + line.qty);
    } else {
      leftOut.add((name: l.name, why: CopyLeftOut.twice));
    }
  }

  return CounterCopy(
    lines: lines,
    billDiscount: billed?.billDiscount ?? Money.zero,
    party: party,
    leftOut: leftOut,
    lostCustomer: copy.partyId != null && party == null ? copy.partyName : null,
  );
}

/// What did not come onto the counter, in words; null when everything did.
String? leftOutWords(AppStrings s, CounterCopy copy) {
  final names = [
    for (final l in copy.leftOut)
      switch (l.why) {
        CopyLeftOut.gone => s.copyWhyGone(l.name),
        CopyLeftOut.free => s.copyWhyFree(l.name),
        CopyLeftOut.serial => s.copyWhySerial(l.name),
        CopyLeftOut.twice => s.copyWhyTwice(l.name),
      },
  ];
  final parts = [
    if (names.isNotEmpty) s.copyLeftOut(names.join(', ')),
    if (copy.lostCustomer case final name?) s.copyNoCustomer(name),
  ];
  return parts.isEmpty ? null : parts.join('\n');
}

/// Asks which prices; null when the cashier changed their mind.
Future<CopyRates?> askCopyRates(
  BuildContext context, {
  required String docNo,
}) => showModalBottomSheet<CopyRates>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.copyRatesTitle(docNo),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.copyRatesToday,
              icon: Icons.today_outlined,
              big: true,
              onPressed: () => Navigator.of(context).pop(CopyRates.today),
            ),
            const SizedBox(height: BlTokens.space1),
            Text(
              s.copyRatesTodayHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.copyRatesOld,
              icon: Icons.history,
              kind: BlButtonKind.secondary,
              big: true,
              onPressed: () => Navigator.of(context).pop(CopyRates.asBilled),
            ),
            const SizedBox(height: BlTokens.space1),
            Text(
              s.copyRatesOldHint(docNo),
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
          ],
        ),
      ),
    );
  },
);

/// Puts [documentId] on the counter as a new bill (M36), asking first
/// which prices. Returns whether it went on.
///
/// Never over a bill somebody is ringing: the quotation's rule, said in the
/// same words. A customer named on an empty counter is not a bill yet, and
/// is replaced by the copy's — the counter's own "Pichhla order dobara" is
/// exactly that case.
///
/// [openCounter] is false from the counter itself, which is already open.
Future<bool> billAgain(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
  required String docNo,
  bool openCounter = true,
}) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final services = ref.read(appServicesProvider);
  final cart = ref.read(cartProvider.notifier);
  if (!ref.read(cartProvider).isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s.quotationCounterBusy)));
    return false;
  }
  final firmFuture = ref.read(firmProvider.future);
  // A counter that cannot convert units still rings what it can (a line
  // in another unit keeps the price it was billed at), so a failure here
  // is no answer rather than an error left unheard.
  final unitsFuture = ref
      .read(unitConverterProvider.future)
      .then<UnitConverter?>((u) => u, onError: (Object _) => null);

  final rates = await askCopyRates(context, docNo: docNo);
  if (rates == null) return false;

  try {
    final firm = await firmFuture;
    if (firm == null) return false;
    final copy = await services.queries.billCopy(firm.id, documentId);
    if (copy == null) throw StateError(s.commonNothingSaved);
    final units = await unitsFuture;
    final built = await counterCopyOf(
      services,
      firm.id,
      copy,
      rates: rates,
      units: units,
    );
    if (built.lines.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [s.copyNothing(docNo), ?leftOutWords(s, built)].join('\n'),
          ),
        ),
      );
      return false;
    }
    // Said at the head of the lines rather than in a SnackBar: the counter
    // clears whatever the last screen was saying the moment it opens, so a
    // SnackBar about what was left behind would be gone before it was read.
    cart.loadCopy(
      built.lines,
      party: built.party,
      billDiscount: built.billDiscount,
      copiedFromNo: docNo,
      copyNote: leftOutWords(s, built),
    );
    if (openCounter) {
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const PosScreen()),
        ),
      );
    }
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
    );
    return false;
  }
}

/// A customer's most recent bill still standing, for the counter (M36).
final lastBillProvider = FutureProvider.autoDispose.family<LinkedBill?, String>(
  (ref, partyId) async {
    ref.watch(refreshTickProvider);
    final firm = await ref.watch(firmProvider.future);
    if (firm == null) return null;
    return ref.watch(appServicesProvider).queries.lastBillFor(firm.id, partyId);
  },
);

/// Which bill a bill replaced and which replaced it (M36).
final billLinksProvider = FutureProvider.autoDispose.family<BillLinks, String>((
  ref,
  documentId,
) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return BillLinks.none;
  return ref.watch(appServicesProvider).queries.billLinks(firm.id, documentId);
});

/// One bill read for ringing again, for a sheet that says what it holds.
final billCopyProvider = FutureProvider.autoDispose.family<BillCopy?, String>((
  ref,
  documentId,
) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  return ref.watch(appServicesProvider).queries.billCopy(firm.id, documentId);
});
