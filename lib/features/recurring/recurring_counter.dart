import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart';
import '../sales/bill_again.dart';
import 'recurring_providers.dart';

/// A repeating bill put on the counter for the cashier to check (M63).
///
/// "Banayein" on the home screen's card. It is M36's copy flow with the
/// template in place of a bill: the goods in the units kept, the customer at
/// their prices today — their tier, their standing discount, and the item's
/// quantity slab where that is lower (M43) — or at the prices the template
/// keeps when it was set to keep them. Nothing is written until the cashier
/// takes the money; the sale then moves the template on to [forDate] in the
/// same commit (tender_sheet.dart hands the cart's mark to the sale path).
///
/// Never over a bill somebody is ringing, in the quotation's words.
Future<bool> makeOnCounter(
  BuildContext context,
  WidgetRef ref, {
  required RecurringBill bill,
  required BusinessDate forDate,
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
  // Every read of [ref] before the first wait: a sheet that called this
  // may be gone by the time the books answer.
  final firmFuture = ref.read(firmProvider.future);
  // A counter that cannot convert units still rings what it can: a line in
  // another unit keeps the price it was kept at.
  final unitsFuture = ref
      .read(unitConverterProvider.future)
      .then<UnitConverter?>((u) => u, onError: (Object _) => null);
  try {
    final firm = await firmFuture;
    if (firm == null) return false;
    final units = await unitsFuture;
    final built = await counterLinesOf(
      services,
      firm.id,
      bill,
      book: await services.schemeBook(),
      units: units,
    );
    final party = built.party;
    if (party == null) {
      throw const RecurringRefused(RecurringProblem.customerGone);
    }
    if (built.lines.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [s.recurringNoLines, ?leftOutWords(s, built)].join('\n'),
          ),
        ),
      );
      return false;
    }
    cart.loadCopy(
      built.lines,
      party: party,
      billDiscount: built.billDiscount,
      copiedFromNo: bill.fromDocNo ?? bill.partyName,
      copyNote: leftOutWords(s, built),
      recurring: RecurringMark(
        billId: bill.id,
        forDate: forDate,
        partyId: party.id,
        partyName: party.name,
      ),
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const PosScreen()),
      ),
    );
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(recurringProblemText(s, error))),
    );
    return false;
  }
}

/// [bill]'s lines as the counter holds them, priced the way it says.
///
/// What cannot come is left off and said in M36's words: an item hidden
/// since, a piece sold by serial number, the same item twice at two prices.
Future<CounterCopy> counterLinesOf(
  AppServices services,
  String firmId,
  RecurringBill bill, {
  required SchemeBook book,
  UnitConverter? units,
}) async {
  final party = await services.queries.partyById(firmId, bill.partyId);
  final tier = party?.priceTier ?? PriceTier.retail;
  final standing = party?.defaultDiscountBp ?? 0;
  final fixed = bill.prices == RecurringPrices.fixed;

  final lines = <CartLine>[];
  final leftOut = <({String name, CopyLeftOut why})>[];
  var looseKey = 0;

  for (final l in bill.lines) {
    // Khula maal (M37): what it was called and what it came to.
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
          discountBp: fixed ? l.discountBp : 0,
          explicitDiscount: fixed ? l.discount : null,
        ),
      );
      continue;
    }

    final item = await services.queries.itemById(firmId, l.itemId!);
    if (item == null) {
      leftOut.add((name: l.name, why: CopyLeftOut.gone));
      continue;
    }
    if (item.tracksSerial) {
      leftOut.add((name: l.name, why: CopyLeftOut.serial));
      continue;
    }

    final converted = l.unitId != null && l.unitId != item.unitId;
    var rate = l.rate;
    if (!fixed) {
      try {
        final base = converted
            ? units!.convert(
                l.qty,
                fromUnitId: l.unitId!,
                toUnitId: item.unitId,
                itemId: item.id,
              )
            : l.qty;
        final perBase = book.priceAt(item, tier, base);
        rate = converted
            ? units!.convertRate(
                perBase,
                fromUnitId: item.unitId,
                toUnitId: l.unitId!,
                itemId: item.id,
              )
            : perBase;
      } on Object {
        rate = l.rate;
      }
    }
    final line = CartLine(
      item: item,
      qty: l.qty,
      rate: rate,
      discountBp: fixed ? l.discountBp : standing,
      explicitDiscount: fixed ? l.discount : null,
      unitId: converted ? l.unitId : null,
      unitCode: converted ? l.unitCode : null,
    );
    if (lines.any((c) => c.item.id == item.id)) {
      leftOut.add((name: l.name, why: CopyLeftOut.twice));
      continue;
    }
    lines.add(line);
  }

  return CounterCopy(
    lines: lines,
    billDiscount: fixed ? bill.billDiscount : Money.zero,
    party: party,
    leftOut: leftOut,
    lostCustomer: party == null ? bill.partyName : null,
  );
}
