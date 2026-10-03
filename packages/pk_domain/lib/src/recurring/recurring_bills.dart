/// The bills that come round every week or month, ready on the day (M63).
///
/// A hotel takes twenty litres of milk every morning. A school canteen sends
/// the same list every Monday. An office has its tea, sugar and biscuits on
/// the first of the month. The shopkeeper rings the same bill again and again
/// from memory, and the week he is ill the canteen's order is not billed at
/// all. Vyapar has a "Repeat Invoice", and it works only with the phone
/// logged into their sync server; here it is kept in the shop's own books and
/// made on the phone, with no server anywhere.
///
/// A repeating bill is a TEMPLATE, never a posting. It names a customer, the
/// goods and how many, and how often: every day, every week on one day, every
/// month on one date, or every so many days. It says whether the bill is made
/// at the prices of the day it is made (the default) or at the prices of the
/// bill it was copied from, and whether the phone may make it by itself or
/// only reminds.
///
/// ## When it is due
///
/// There is no alarm and no job in the background. The app follows M20 and
/// M47: things happen when the app is opened or comes to the front. Every day
/// the schedule falls on, from its start, up to and including today, is an
/// occurrence. [RecurringBill.doneThrough] is the last day handled — a bill
/// made for it, or the shopkeeper's word to let it go — and every occurrence
/// after it, up to today, is due. One due day is a bill to make. More than
/// one is days the app was not opened, and those are never made silently:
/// the shopkeeper is asked to make them all, only the latest, or none.
///
/// ## Where it is kept
///
/// One `settings` row per template (`recurring.sale.<id>`, JSON, integers
/// and strings only), the shape M43 keeps a scheme in and M47 a monthly
/// bill. No schema change. The row's id is worked out from the template's
/// own, so two phones that change one template while apart write one row
/// twice and the shop's wi-fi keeps the later, as it does any edit.
///
/// A bill made from a template moves [RecurringBill.doneThrough] on in the
/// sale's own commit and leaves an audit row naming the template and the day
/// it was for. That row is how the template lists the bills it made: no new
/// table, and nothing a bill could be made without.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../catalogue/shelf.dart';
import '../catalogue/unit_converter.dart';
import '../ports/app_queries.dart' show ItemSummary;
import '../ports/sale_writer.dart' show PostedSale;
import '../pricing/price_tier.dart';
import '../pricing/schemes.dart';
import '../sales/bill_copy.dart';
import '../sales/sale_draft.dart';
import '../time/clock.dart';

/// The prefix every repeating bill's settings row starts with.
const recurringBillSettingPrefix = 'recurring.sale.';

/// The settings row the repeating bill [id] is kept in.
String recurringBillSettingKey(String id) => '$recurringBillSettingPrefix$id';

/// The id of that settings row: worked out from the template, never drawn
/// fresh, so the same template is the same row on every phone.
String recurringBillRowId(String id) => 'recurring-sale-$id';

/// The audit action a bill made from a template is recorded under. Its
/// `after` carries `template` (the template's id), `for` (the day it was
/// for) and `auto` (made by itself, not at the counter).
const recurringBillMadeAction = 'RECURRING_BILL_MADE';

// ---------------------------------------------------------------------------
// How often
// ---------------------------------------------------------------------------

enum RepeatKind { daily, weekly, monthly, everyDays }

/// How often a bill comes round.
final class RepeatEvery {
  const RepeatEvery._(this.kind, {this.day = 0, this.days = 1});

  /// Every day: the hotel's milk.
  const RepeatEvery.daily() : this._(RepeatKind.daily);

  /// Every week on [weekday], 1 Monday to 7 Sunday: the canteen's Monday
  /// order.
  const RepeatEvery.weekly(int weekday)
    : this._(RepeatKind.weekly, day: weekday, days: 7);

  /// Every month on [date], 1 to 31; in a month too short for it, the last
  /// day of that month (M47's rule for the rent).
  const RepeatEvery.monthly(int date) : this._(RepeatKind.monthly, day: date);

  /// Every [days] days from the start: a fortnightly order is fourteen.
  const RepeatEvery.everyDays(int days)
    : this._(RepeatKind.everyDays, days: days);

  final RepeatKind kind;

  /// The weekday (weekly) or the date (monthly); nothing otherwise.
  final int day;

  /// The gap in days (every so many days).
  final int days;

  /// Whether this is a schedule the phone can keep.
  bool get isValid => switch (kind) {
    RepeatKind.daily => true,
    RepeatKind.weekly => day >= 1 && day <= 7,
    RepeatKind.monthly => day >= 1 && day <= 31,
    RepeatKind.everyDays => days >= 2 && days <= 366,
  };

  /// Every day the schedule falls on from [start], for ever, in order.
  ///
  /// Endless; a caller takes what it needs. Monthly dates are worked out
  /// from the date asked for each month, never from the month before, so a
  /// bill on the 31st is on the 28th in February and back on the 31st in
  /// March.
  Iterable<BusinessDate> from(BusinessDate start) sync* {
    // A schedule no phone could keep (a weekday of nine, read from a row
    // written by hand or by a build that did not check) falls on no day,
    // rather than looking for one for ever.
    if (!isValid) return;
    switch (kind) {
      case RepeatKind.daily:
      case RepeatKind.everyDays:
        final step = kind == RepeatKind.daily ? 1 : days;
        var on = start;
        while (true) {
          yield on;
          on = on.addDays(step);
        }
      case RepeatKind.weekly:
        var on = start;
        while (weekdayOf(on) != day) {
          on = on.addDays(1);
        }
        while (true) {
          yield on;
          on = on.addDays(7);
        }
      case RepeatKind.monthly:
        var year = start.year;
        var month = start.month;
        while (true) {
          final on = _dateIn(year, month, day);
          if (on.value.compareTo(start.value) >= 0) yield on;
          month++;
          if (month > 12) {
            month = 1;
            year++;
          }
        }
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (kind == RepeatKind.weekly || kind == RepeatKind.monthly) 'day': day,
    if (kind == RepeatKind.everyDays) 'days': days,
  };

  static RepeatEvery? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final day = raw['day'];
    final days = raw['days'];
    return switch (raw['kind']) {
      'daily' => const RepeatEvery.daily(),
      'weekly' when day is int => RepeatEvery.weekly(day),
      'monthly' when day is int => RepeatEvery.monthly(day),
      'everyDays' when days is int => RepeatEvery.everyDays(days),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is RepeatEvery &&
      other.kind == kind &&
      other.day == day &&
      other.days == days;

  @override
  int get hashCode => Object.hash(kind, day, days);
}

/// 1 Monday to 7 Sunday, as `DateTime.weekday` counts.
int weekdayOf(BusinessDate date) =>
    DateTime.utc(date.year, date.month, date.day).weekday;

BusinessDate _dateIn(int year, int month, int day) {
  final last = DateTime.utc(year, month + 1, 0).day;
  final d = day > last ? last : day;
  return BusinessDate(
    '${year.toString().padLeft(4, '0')}-'
    '${month.toString().padLeft(2, '0')}-'
    '${d.toString().padLeft(2, '0')}',
  );
}

bool _after(BusinessDate a, BusinessDate b) => a.value.compareTo(b.value) > 0;

BusinessDate _later(BusinessDate a, BusinessDate? b) =>
    b == null || _after(a, b) ? a : b;

// ---------------------------------------------------------------------------
// The template
// ---------------------------------------------------------------------------

/// Which prices a repeating bill is made at.
enum RecurringPrices {
  /// What the counter would charge this customer on the day the bill is
  /// made: their price list, their standing discount, the shop's schemes.
  /// The default, because a price that moved moved for a reason.
  today,

  /// The prices, discounts and all, of the bill it was copied from: the
  /// office promised a rate for the year.
  fixed,
}

/// Whether the phone may make it by itself.
enum RecurringMode {
  /// Made on udhaar from the home screen's "Sab bana dein", every check the
  /// counter makes still made.
  automatic,

  /// Only said on the day. The cashier puts it on the counter, checks it and
  /// takes the money as for any bill. The default.
  remind,
}

/// One line of a repeating bill.
///
/// The item is named by its id, with its name as it was when the template
/// was made, so a template whose item has since been hidden still says
/// what it was ("Doodh — no longer kept") instead of failing to open.
final class RecurringLine {
  const RecurringLine({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.unitCode,
    required this.rate,
    this.unitId,
    this.discountBp = 0,
    this.discount,
  });

  /// The item, or null for khula maal (M37), which goes as what it was
  /// called and what it came to.
  final String? itemId;

  /// The item's name when the template was made or last changed.
  final String name;

  /// How many, in [unitId]: two maunds is two, not eighty kilos.
  final Qty qty;

  /// The unit the line is sold in; null is the item's own.
  final String? unitId;
  final String unitCode;

  /// Per [unitCode], as on the bill it came from. Used when the template's
  /// prices are fixed, and always for khula maal, which has no price list.
  final Rate rate;

  /// The line's own discount as typed on that bill: a percentage, or rupees.
  /// Used only when the prices are fixed.
  final int discountBp;
  final Money? discount;

  bool get isLoose => itemId == null;

  RecurringLine withQty(Qty qty) => RecurringLine(
    itemId: itemId,
    name: name,
    qty: qty,
    unitId: unitId,
    unitCode: unitCode,
    rate: rate,
    discountBp: discountBp,
    discount: discount,
  );

  Map<String, Object?> toJson() => {
    'item': itemId,
    'name': name,
    'qty': qty.inThousandths,
    'unit': ?unitId,
    'unitCode': unitCode,
    'rate': rate.inMilliPaisa,
    if (discountBp != 0) 'bp': discountBp,
    if (discount case final d?) 'discountPaisa': d.inPaisa,
  };

  static RecurringLine? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final item = raw['item'];
    final name = raw['name'];
    final qty = raw['qty'];
    final unit = raw['unit'];
    final unitCode = raw['unitCode'];
    final rate = raw['rate'];
    final bp = raw['bp'] ?? 0;
    final discount = raw['discountPaisa'];
    if ((item != null && item is! String) ||
        name is! String ||
        qty is! int ||
        (unit != null && unit is! String) ||
        unitCode is! String ||
        rate is! int ||
        bp is! int ||
        (discount != null && discount is! int)) {
      return null;
    }
    return RecurringLine(
      itemId: item as String?,
      name: name,
      qty: Qty.raw(qty),
      unitId: unit as String?,
      unitCode: unitCode,
      rate: Rate.raw(rate),
      discountBp: bp,
      discount: discount == null ? null : Money.paisa(discount as int),
    );
  }
}

/// Why a repeating bill could not be kept or made.
enum RecurringProblem {
  /// A repeating bill is for a customer in the khata: it goes on udhaar.
  noCustomer,

  /// It has no goods.
  noLines,

  /// A line has nothing on it.
  badQty,

  /// The schedule makes no sense (a weekday of nine).
  badEvery,

  /// It ends before it starts.
  endBeforeStart,

  /// "Ends after nought bills".
  badTimes,

  /// An item on it is no longer kept.
  itemGone,

  /// An item on it is sold by serial number, one piece at a time.
  serialItem,

  /// A line's unit no longer converts to its item's.
  unitGone,

  /// The customer is no longer in the khata.
  customerGone,

  /// This day's bill is already made.
  alreadyMade,

  /// The template is no longer kept.
  notKept,
}

/// A repeating bill refused, with what it concerns.
final class RecurringRefused implements Exception {
  const RecurringRefused(this.problem, {this.names = const [], this.docNo});

  final RecurringProblem problem;

  /// The items it concerns, by name.
  final List<String> names;

  /// The bill already made, for [RecurringProblem.alreadyMade].
  final String? docNo;

  @override
  String toString() => switch (problem) {
    RecurringProblem.noCustomer =>
      'A repeating bill goes on a customer\'s khata. Pick the customer first.',
    RecurringProblem.noLines => 'A repeating bill needs at least one item.',
    RecurringProblem.badQty => 'Every line needs a quantity above nothing.',
    RecurringProblem.badEvery => 'That is not a day the bill can come round.',
    RecurringProblem.endBeforeStart => 'It cannot end before it starts.',
    RecurringProblem.badTimes => 'It has to be made at least once.',
    RecurringProblem.itemGone =>
      '${names.join(', ')} is no longer kept. Open the bill on the counter '
          'to check it, or take the item off the repeating bill.',
    RecurringProblem.serialItem =>
      '${names.join(', ')} is sold by serial number, one piece at a time. '
          'Make this bill on the counter.',
    RecurringProblem.unitGone =>
      "${names.join(', ')}'s unit no longer converts to the item's own.",
    RecurringProblem.customerGone => 'The customer is no longer in the khata.',
    RecurringProblem.alreadyMade =>
      "This day's bill is already made${docNo == null ? '' : ' as $docNo'}.",
    RecurringProblem.notKept => 'That repeating bill is no longer kept.',
  };
}

/// A bill that comes round: who, what, and how often.
final class RecurringBill {
  const RecurringBill({
    required this.id,
    required this.partyId,
    required this.partyName,
    required this.lines,
    required this.every,
    required this.startOn,
    this.endOn,
    this.times,
    this.prices = RecurringPrices.today,
    this.mode = RecurringMode.remind,
    this.paused = false,
    this.endedOn,
    this.doneThrough,
    this.billDiscount = Money.zero,
    this.fromDocNo,
  });

  final String id;

  /// The customer whose khata it goes on, and their name when it was kept.
  final String partyId;
  final String partyName;

  final List<RecurringLine> lines;

  final RepeatEvery every;

  /// The first day it may fall on.
  final BusinessDate startOn;

  /// The last day it may fall on, when it has one.
  final BusinessDate? endOn;

  /// How many times it comes round in all, counted from the start, made or
  /// let go: "six months" on the first is six.
  final int? times;

  final RecurringPrices prices;
  final RecurringMode mode;

  /// Stopped for now. A paused bill never comes due; when it is resumed the
  /// days it was paused through are not owed.
  final bool paused;

  /// Ended by the shopkeeper on this day. Kept, with its history, and never
  /// due again.
  final BusinessDate? endedOn;

  /// The last day handled: a bill made for it, or let go.
  final BusinessDate? doneThrough;

  /// The bill's own discount, for fixed prices: as typed on the bill it was
  /// copied from.
  final Money billDiscount;

  /// The bill it was copied from, for the screen.
  final String? fromDocNo;

  bool get byItself => mode == RecurringMode.automatic;
  bool get isEnded => endedOn != null;

  /// Every day it falls on up to and including [through], from the start.
  List<BusinessDate> occurrences({required BusinessDate through}) {
    final out = <BusinessDate>[];
    var count = 0;
    for (final on in every.from(startOn)) {
      if (times case final limit? when count >= limit) break;
      if (endOn case final end? when _after(on, end)) break;
      if (_after(on, through)) break;
      out.add(on);
      count++;
    }
    return out;
  }

  /// The days up to and including [today] it fell on and that are not yet
  /// handled, oldest first. Nothing while paused or once ended.
  List<BusinessDate> dueOn(BusinessDate today) {
    if (paused || isEnded) return const [];
    final done = doneThrough;
    return [
      for (final on in occurrences(through: today))
        if (done == null || _after(on, done)) on,
    ];
  }

  /// The first day after [today] — and after the last day handled — it
  /// falls on; null once it has come round for the last time or was ended.
  BusinessDate? nextAfter(BusinessDate today) {
    if (isEnded) return null;
    final from = _later(today, doneThrough);
    var count = 0;
    for (final on in every.from(startOn)) {
      if (times case final limit? when count >= limit) return null;
      if (endOn case final end? when _after(on, end)) return null;
      count++;
      if (_after(on, from)) return on;
    }
    return null;
  }

  /// Whether it will never come round again after [today], nor is owed.
  bool isOver(BusinessDate today) =>
      isEnded || (nextAfter(today) == null && dueOn(today).isEmpty);

  /// Handled up to [date]: a bill made for it, or let go.
  RecurringBill handledThrough(BusinessDate date) =>
      copyWith(doneThrough: _later(date, doneThrough));

  /// This, as changed on a screen, keeping what the books say of [kept]:
  /// whether it is paused or ended, and the last day handled. The set-up
  /// screen changes what and when; a bill made, a pause or an end on
  /// another screen meanwhile is never taken back by its Save.
  RecurringBill keepingStateOf(RecurringBill kept) => RecurringBill(
    id: id,
    partyId: partyId,
    partyName: partyName,
    lines: lines,
    every: every,
    startOn: startOn,
    endOn: endOn,
    times: times,
    prices: prices,
    mode: mode,
    paused: kept.paused,
    endedOn: kept.endedOn,
    doneThrough: switch (kept.doneThrough) {
      final done? => _later(done, doneThrough),
      null => doneThrough,
    },
    billDiscount: billDiscount,
    fromDocNo: fromDocNo,
  );

  RecurringBill copyWith({
    String? partyName,
    List<RecurringLine>? lines,
    RepeatEvery? every,
    BusinessDate? startOn,
    BusinessDate? endOn,
    bool clearEnd = false,
    int? times,
    bool clearTimes = false,
    RecurringPrices? prices,
    RecurringMode? mode,
    bool? paused,
    BusinessDate? endedOn,
    BusinessDate? doneThrough,
  }) => RecurringBill(
    id: id,
    partyId: partyId,
    partyName: partyName ?? this.partyName,
    lines: lines ?? this.lines,
    every: every ?? this.every,
    startOn: startOn ?? this.startOn,
    endOn: clearEnd ? null : endOn ?? this.endOn,
    times: clearTimes ? null : times ?? this.times,
    prices: prices ?? this.prices,
    mode: mode ?? this.mode,
    paused: paused ?? this.paused,
    endedOn: endedOn ?? this.endedOn,
    doneThrough: doneThrough ?? this.doneThrough,
    billDiscount: billDiscount,
    fromDocNo: fromDocNo,
  );

  /// Throws [RecurringRefused] unless this can be kept.
  void check() {
    if (partyId.trim().isEmpty) {
      throw const RecurringRefused(RecurringProblem.noCustomer);
    }
    if (lines.isEmpty) throw const RecurringRefused(RecurringProblem.noLines);
    for (final l in lines) {
      if (!l.qty.isPositive) {
        throw RecurringRefused(RecurringProblem.badQty, names: [l.name]);
      }
    }
    if (!every.isValid) throw const RecurringRefused(RecurringProblem.badEvery);
    if (endOn case final end? when _after(startOn, end)) {
      throw const RecurringRefused(RecurringProblem.endBeforeStart);
    }
    if (times case final n? when n < 1) {
      throw const RecurringRefused(RecurringProblem.badTimes);
    }
  }

  String toJson() => jsonEncode({
    'v': 1,
    'party': partyId,
    'partyName': partyName,
    'lines': [for (final l in lines) l.toJson()],
    'every': every.toJson(),
    'start': startOn.value,
    'end': ?endOn?.value,
    'times': ?times,
    'prices': prices.name,
    'mode': mode.name,
    if (paused) 'paused': true,
    'endedOn': ?endedOn?.value,
    'doneThrough': ?doneThrough?.value,
    if (billDiscount.isPositive) 'billDiscountPaisa': billDiscount.inPaisa,
    'fromNo': ?fromDocNo,
  });

  /// Read back from its settings row; null for a row this build cannot
  /// read, which is left alone rather than guessed at.
  static RecurringBill? fromJson(String id, String raw) {
    final Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (root is! Map<String, Object?> || root['v'] != 1) return null;
    final party = root['party'];
    final partyName = root['partyName'];
    final rawLines = root['lines'];
    final every = RepeatEvery.fromJson(root['every']);
    final start = _date(root['start']);
    if (party is! String ||
        partyName is! String ||
        rawLines is! List ||
        every == null ||
        start == null) {
      return null;
    }
    final lines = <RecurringLine>[];
    for (final raw in rawLines) {
      final line = RecurringLine.fromJson(raw);
      if (line == null) return null;
      lines.add(line);
    }
    final times = root['times'];
    final discount = root['billDiscountPaisa'];
    final from = root['fromNo'];
    return RecurringBill(
      id: id,
      partyId: party,
      partyName: partyName,
      lines: lines,
      every: every,
      startOn: start,
      endOn: _date(root['end']),
      times: times is int ? times : null,
      prices: root['prices'] == RecurringPrices.fixed.name
          ? RecurringPrices.fixed
          : RecurringPrices.today,
      mode: root['mode'] == RecurringMode.automatic.name
          ? RecurringMode.automatic
          : RecurringMode.remind,
      paused: root['paused'] == true,
      endedOn: _date(root['endedOn']),
      doneThrough: _date(root['doneThrough']),
      billDiscount: discount is int ? Money.paisa(discount) : Money.zero,
      fromDocNo: from is String ? from : null,
    );
  }

  static BusinessDate? _date(Object? raw) =>
      raw is String ? BusinessDate.tryParse(raw) : null;
}

// ---------------------------------------------------------------------------
// From a bill
// ---------------------------------------------------------------------------

/// Why a line of the bill did not go onto the template.
enum RecurringLeftOut {
  /// A free line: the shop's schemes give the bonus again each time.
  free,

  /// An item sold by serial number: that phone was sold.
  serial,

  /// The item was hidden since.
  gone,

  /// The same item again at another price or unit; the counter holds an
  /// item once.
  twice,
}

/// What of [copy] a repeating bill carries, and what it leaves.
///
/// The discounts are taken apart into what the cashier typed (M36's
/// [discountsAsBilled]), so a template at fixed prices makes the bill it
/// was copied from, to the paisa. [serialItemIds] are the items sold by
/// serial number, and [goneItemIds] those hidden since; both are left off.
({
  List<RecurringLine> lines,
  Money billDiscount,
  List<({String name, RecurringLeftOut why})> leftOut,
})
recurringLinesOf(
  BillCopy copy, {
  Set<String> serialItemIds = const {},
  Set<String> goneItemIds = const {},
}) {
  final typed = discountsAsBilled(
    copy.lines,
    billDiscount: copy.billDiscount,
    roundingMode: copy.roundingMode,
  );
  final lines = <RecurringLine>[];
  final leftOut = <({String name, RecurringLeftOut why})>[];
  for (var i = 0; i < copy.lines.length; i++) {
    final l = copy.lines[i];
    final d = typed.lines[i];
    if (l.isFree) {
      leftOut.add((name: l.name, why: RecurringLeftOut.free));
      continue;
    }
    final itemId = l.itemId;
    if (itemId != null && (l.itemGone || goneItemIds.contains(itemId))) {
      leftOut.add((name: l.name, why: RecurringLeftOut.gone));
      continue;
    }
    if (itemId != null && serialItemIds.contains(itemId)) {
      if (!leftOut.any((o) => o.name == l.name)) {
        leftOut.add((name: l.name, why: RecurringLeftOut.serial));
      }
      continue;
    }
    final line = RecurringLine(
      itemId: itemId,
      name: l.name,
      qty: l.qty,
      unitId: l.unitId,
      unitCode: l.unitCode,
      rate: l.rate,
      discountBp: d.discountBp,
      discount: d.explicitDiscount,
    );
    final at = itemId == null
        ? -1
        : lines.indexWhere((x) => x.itemId == itemId);
    if (at < 0) {
      lines.add(line);
      continue;
    }
    final had = lines[at];
    if (had.unitId == line.unitId &&
        had.rate == line.rate &&
        had.discountBp == line.discountBp &&
        had.discount == null &&
        line.discount == null) {
      lines[at] = had.withQty(had.qty + line.qty);
    } else {
      leftOut.add((name: l.name, why: RecurringLeftOut.twice));
    }
  }
  return (lines: lines, billDiscount: typed.billDiscount, leftOut: leftOut);
}

// ---------------------------------------------------------------------------
// Making one
// ---------------------------------------------------------------------------

/// The bill [bill] makes today, for nobody at the counter to check.
///
/// Priced exactly as the counter prices a bill rung fresh (M43's
/// `Cart.forBooks`): at today's prices, each line at the customer's tier or
/// the item's quantity slab where that is lower, carried into the line's
/// unit exactly, with the customer's standing discount; the bonus each
/// item's scheme gives, under the last line of that item; and the shop's
/// discount on a big bill unless the bill has its own. At fixed prices the
/// lines keep the rates and discounts they were copied with.
///
/// On udhaar: there is nobody to take money from. Refused with
/// [RecurringRefused] for an item hidden since, one sold by serial number,
/// or a unit that no longer converts — each a bill for somebody to look at
/// on the counter, never one to make without the goods it promised.
///
/// [items] holds the items still kept; a line whose item is missing from it
/// is gone.
SaleDraft recurringSaleDraft(
  RecurringBill bill, {
  required Map<String, ItemSummary> items,
  required PriceTier tier,
  required int standingBp,
  required SchemeBook book,
  required UnitConverter units,
  required bool roundToRupee,
  String? partyName,
  String locationCode = 'MAIN',
}) {
  final fixed = bill.prices == RecurringPrices.fixed;
  final gone = [
    for (final l in bill.lines)
      if (l.itemId case final id? when !items.containsKey(id)) l.name,
  ];
  if (gone.isNotEmpty) {
    throw RecurringRefused(RecurringProblem.itemGone, names: gone);
  }
  final serial = [
    for (final l in bill.lines)
      if (items[l.itemId]?.tracksSerial ?? false) l.name,
  ];
  if (serial.isNotEmpty) {
    throw RecurringRefused(RecurringProblem.serialItem, names: serial);
  }

  final rung = <SaleLineDraft>[];
  for (final l in bill.lines) {
    final item = l.itemId == null ? null : items[l.itemId];
    if (item == null) {
      rung.add(
        SaleLineDraft(
          itemId: null,
          itemName: l.name,
          qty: l.qty,
          baseQty: l.qty,
          unitId: l.unitId,
          unitCode: l.unitCode,
          rate: l.rate,
          discountBp: fixed ? l.discountBp : 0,
          explicitDiscount: fixed ? l.discount : null,
          tracksStock: false,
        ),
      );
      continue;
    }
    final converted = l.unitId != null && l.unitId != item.unitId;
    final Qty base;
    final Rate rate;
    try {
      base = converted
          ? units.convert(
              l.qty,
              fromUnitId: l.unitId!,
              toUnitId: item.unitId,
              itemId: item.id,
            )
          : l.qty;
      if (fixed) {
        rate = l.rate;
      } else {
        final perBase = book.priceAt(item, tier, base);
        rate = converted
            ? units.convertRate(
                perBase,
                fromUnitId: item.unitId,
                toUnitId: l.unitId!,
                itemId: item.id,
              )
            : perBase;
      }
    } on UnitConversionException {
      throw RecurringRefused(RecurringProblem.unitGone, names: [item.name]);
    }
    rung.add(
      SaleLineDraft(
        itemId: item.id,
        itemName: item.name,
        itemCode: item.code,
        hsCode: item.hsCode,
        qty: l.qty,
        baseQty: base,
        unitId: converted ? l.unitId : item.unitId,
        unitCode: converted ? l.unitCode : item.unitCode,
        rate: rate,
        discountBp: fixed ? l.discountBp : standingBp,
        explicitDiscount: fixed ? l.discount : null,
        tracksStock: item.tracksStock,
        mrp: item.mrp,
        isThirdSchedule: item.isThirdSchedule,
        isService: item.isService,
      ),
    );
  }

  // The bonus, under the last line of the item that earned it, as the
  // counter puts it.
  final bonus = book.bonusFor(SchemeBook.paidBaseOf(rung));
  final lines = <SaleLineDraft>[];
  if (bonus.isEmpty) {
    lines.addAll(rung);
  } else {
    final last = <String, int>{
      for (var i = 0; i < rung.length; i++) ?rung[i].itemId: i,
    };
    for (var i = 0; i < rung.length; i++) {
      lines.add(rung[i]);
      for (final g in bonus) {
        if (last[g.forItemId] == i) lines.add(g.toLine());
      }
    }
  }

  final own = fixed ? bill.billDiscount : Money.zero;
  final billDiscount = own.isPositive
      ? own
      : book.billSlabFor(SchemeBook.billValueOf(rung))?.discount ?? Money.zero;

  return SaleDraft(
    lines: lines,
    partyId: bill.partyId,
    partyName: partyName ?? bill.partyName,
    billDiscount: billDiscount,
    roundToRupee: roundToRupee,
    locationCode: locationCode,
  );
}

// ---------------------------------------------------------------------------
// On the day
// ---------------------------------------------------------------------------

/// A repeating bill whose day has come.
final class RecurringDue {
  const RecurringDue({
    required this.bill,
    required this.dates,
    this.gone = const [],
  });

  final RecurringBill bill;

  /// The days owed, oldest first; never empty.
  final List<BusinessDate> dates;

  /// Items on it that are no longer kept, by name.
  final List<String> gone;

  BusinessDate get latest => dates.last;
  BusinessDate get earliest => dates.first;

  /// More than one day owed: days the app was not opened. Asked about,
  /// never made by themselves.
  bool get missed => dates.length > 1;
}

/// The bill on the counter is a repeating bill's (M63): which, and for
/// which day. Carried by the counter's cart, and handed to the sale path so
/// the bill and its template move together.
final class RecurringMark {
  const RecurringMark({
    required this.billId,
    required this.forDate,
    required this.partyId,
    required this.partyName,
  });

  final String billId;
  final BusinessDate forDate;
  final String partyId;
  final String partyName;

  Map<String, Object?> toJson() => {
    'bill': billId,
    'for': forDate.value,
    'party': partyId,
    'partyName': partyName,
  };

  static RecurringMark? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final bill = raw['bill'];
    final on = raw['for'];
    final party = raw['party'];
    final name = raw['partyName'];
    if (bill is! String || on is! String || party is! String) return null;
    final date = BusinessDate.tryParse(on);
    if (date == null) return null;
    return RecurringMark(
      billId: bill,
      forDate: date,
      partyId: party,
      partyName: name is String ? name : '',
    );
  }
}

/// One bill a template made, read back from its audit row.
final class RecurringMade {
  const RecurringMade({
    required this.documentId,
    required this.docNo,
    required this.forDate,
    required this.madeOn,
    required this.total,
    this.isVoid = false,
    this.byItself = false,
  });

  final String documentId;
  final String docNo;

  /// The day it was for, and the day it was made: the same unless it was
  /// a day the app was not opened.
  final BusinessDate forDate;
  final BusinessDate madeOn;

  final Money total;

  /// Cancelled since.
  final bool isVoid;

  /// Made by itself from the home screen, not on the counter.
  final bool byItself;
}

/// What became of one repeating bill asked to be made by itself.
final class RecurringOutcome {
  const RecurringOutcome._({
    required this.bill,
    required this.forDate,
    this.posted,
    this.overLimit,
    this.bounced = false,
    this.short = const [],
    this.refusal,
  });

  /// Made: a bill on the customer's khata.
  const RecurringOutcome.made(
    RecurringBill bill,
    BusinessDate forDate,
    PostedSale posted,
  ) : this._(bill: bill, forDate: forDate, posted: posted);

  /// Not made, and waiting on the cashier's word, as the counter would ask:
  /// over the customer's credit limit, a bounced cheque still owed, or a
  /// shelf set to warn that would go below nothing.
  const RecurringOutcome.held(
    RecurringBill bill,
    BusinessDate forDate, {
    ({Money limit, Money after})? overLimit,
    bool bounced = false,
    List<ShelfShort> short = const [],
  }) : this._(
         bill: bill,
         forDate: forDate,
         overLimit: overLimit,
         bounced: bounced,
         short: short,
       );

  /// Not made, and why: an item set to block, a discount past the
  /// cashier's ceiling, an item hidden since.
  const RecurringOutcome.refused(
    RecurringBill bill,
    BusinessDate forDate,
    Object refusal,
  ) : this._(bill: bill, forDate: forDate, refusal: refusal);

  final RecurringBill bill;
  final BusinessDate forDate;
  final PostedSale? posted;
  final ({Money limit, Money after})? overLimit;
  final bool bounced;
  final List<ShelfShort> short;
  final Object? refusal;

  bool get made => posted != null;
  bool get held => posted == null && refusal == null;
}
