/// The recovery man's round, on one sheet (M55).
///
/// A wholesaler does not wait for his retailers to come to him. On Tuesday
/// the recovery man takes Route 3: fifteen shops, each with two or three
/// bills open, and comes back at six with a bag of cash and a story for
/// every name — paid, paid some, "Jumma ko", shutter down, would not pay.
/// Marg calls the paper he carries bill tagging: a party's open bills given
/// to a salesman as a numbered collection sheet, marked on his return.
///
/// Here the sheet is made from the chase list — a route (M40's groups), or
/// everybody late (M38's due dates) — and numbered `WS-2627-0001` from its
/// own series, so the man's paper, the owner's screen and the activity log
/// name the same round. Each line is one customer: what the khata said they
/// owed when the sheet was made, and the bills behind it. It goes out on
/// the receipt printer, as a PDF, or as a WhatsApp message.
///
/// ## On his return
///
/// The owner marks each line: paid in full, paid part (how much), promised
/// (the day, and M38's promise is written on the khata), shop closed, or
/// refused; a line left unmarked was not reached. Saving the marks takes
/// every payment as a receipt on its khata — the receipt path every receipt
/// goes through, oldest bill first, the recovery man named in its note —
/// writes every promise, and closes the sheet, in one transaction: a round
/// is recorded whole or not at all. The sheet then says what was expected,
/// what came, and how much cash he should be handing over.
///
/// ## Kept as a setting
///
/// A sheet is a row in the shop's `settings` — `collection.sheet.<id>`,
/// JSON — written through the TxRunner with an audit row, the way M38 keeps
/// promises. No schema change was open to this milestone, and none is
/// needed: a sheet is a small record written twice (made, then settled),
/// and the money in it is not in it — the receipts are the books' own rows.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';

/// Where sheets live in the shop's settings, one row per sheet.
const collectionSheetKeyPrefix = 'collection.sheet.';

String collectionSheetKey(String sheetId) =>
    '$collectionSheetKeyPrefix$sheetId';

/// The series sheets are numbered from: `WS-2627-0001`.
const collectionSheetDocType = 'collection_sheet';

/// Why a sheet cannot be made or settled, in words.
final class CollectionRefused implements Exception {
  const CollectionRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What became of one customer on the round.
enum CollectionOutcome {
  /// Paid everything the sheet said.
  paid('paid'),

  /// Paid some of it.
  partial('partial'),

  /// Said when they would pay: written on the khata as a promise (M38).
  promise('promise'),

  /// The shutter was down.
  shopClosed('shop_closed'),

  /// Would not pay.
  refused('refused');

  const CollectionOutcome(this.code);

  /// As stored in the sheet's JSON.
  final String code;

  /// Money came in on this line.
  bool get tookMoney => this == paid || this == partial;

  static CollectionOutcome? parse(String? code) {
    for (final o in values) {
      if (o.code == code) return o;
    }
    return null;
  }
}

/// One open bill behind a line, as it stood when the sheet was made.
final class SheetBill {
  const SheetBill({
    required this.documentId,
    required this.docNo,
    required this.dateLocal,
    required this.outstanding,
  });

  final String documentId;
  final String docNo;
  final String dateLocal;
  final Money outstanding;

  Map<String, Object?> toJson() => {
    'id': documentId,
    'no': docNo,
    'date': dateLocal,
    'paisa': outstanding.inPaisa,
  };

  static SheetBill fromJson(Map<String, Object?> json) => SheetBill(
    documentId: json['id'] as String? ?? '',
    docNo: json['no'] as String? ?? '',
    dateLocal: json['date'] as String? ?? '',
    outstanding: Money.paisa(json['paisa'] as int? ?? 0),
  );
}

/// What the owner marked against one line, and what it wrote.
final class SheetResult {
  const SheetResult({
    required this.outcome,
    this.amount,
    this.promisedFor,
    this.mode,
    this.paymentAccountId,
    this.note,
    this.paymentNo,
    this.promiseId,
  });

  final CollectionOutcome outcome;

  /// Paid, or paid in part: what came. A promise: what was promised, if a
  /// figure was said.
  final Money? amount;

  /// A promise's day, `YYYY-MM-DD`.
  final String? promisedFor;

  /// How the money came (`cash`, `jazzcash`, ...), and into which of the
  /// shop's accounts.
  final String? mode;
  final String? paymentAccountId;

  /// What the man said about it: "beta dukaan par tha", "agle hafte".
  final String? note;

  /// The receipt it was taken on, once saved.
  final String? paymentNo;

  /// The promise written on the khata, once saved.
  final String? promiseId;

  /// Money that came in on this line; nothing for any other outcome.
  Money get received => outcome.tookMoney ? (amount ?? Money.zero) : Money.zero;

  SheetResult written({String? paymentNo, String? promiseId}) => SheetResult(
    outcome: outcome,
    amount: amount,
    promisedFor: promisedFor,
    mode: mode,
    paymentAccountId: paymentAccountId,
    note: note,
    paymentNo: paymentNo ?? this.paymentNo,
    promiseId: promiseId ?? this.promiseId,
  );

  Map<String, Object?> toJson() => {
    'outcome': outcome.code,
    'paisa': amount?.inPaisa,
    'for': promisedFor,
    'mode': mode,
    'account': paymentAccountId,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'payment_no': paymentNo,
    'promise_id': promiseId,
  };

  static SheetResult? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final outcome = CollectionOutcome.parse(json['outcome'] as String?);
    if (outcome == null) return null;
    final paisa = json['paisa'] as int?;
    return SheetResult(
      outcome: outcome,
      amount: paisa == null ? null : Money.paisa(paisa),
      promisedFor: json['for'] as String?,
      mode: json['mode'] as String?,
      paymentAccountId: json['account'] as String?,
      note: json['note'] as String?,
      paymentNo: json['payment_no'] as String?,
      promiseId: json['promise_id'] as String?,
    );
  }
}

/// One customer on the sheet.
final class SheetLine {
  const SheetLine({
    required this.lineNo,
    required this.partyId,
    required this.partyName,
    required this.due,
    required this.bills,
    this.phone,
    this.group,
    this.unpriced = 0,
    this.result,
  });

  /// 1, 2, 3 — the number the man calls the line by.
  final int lineNo;
  final String partyId;
  final String partyName;
  final String? phone;

  /// Their route or area (M40), printed so the man can find the shop.
  final String? group;

  /// What the khata said they owed when the sheet was made.
  final Money due;

  /// The open bills behind [due], oldest first.
  final List<SheetBill> bills;

  /// Lines of goods given them with the rate still to be agreed, said on the
  /// paper so the man can mention them. Not in [due].
  final int unpriced;

  /// What became of them; null while the sheet is out, or when the man did
  /// not reach them.
  final SheetResult? result;

  /// What they owed from before the bills: an opening balance, or a charge
  /// not on a bill. Nothing when the bills cover it.
  Money get earlier {
    final onBills = Money.sum([for (final b in bills) b.outstanding]);
    final rest = due - onBills;
    return rest.isPositive ? rest : Money.zero;
  }

  SheetLine withResult(SheetResult? result) => SheetLine(
    lineNo: lineNo,
    partyId: partyId,
    partyName: partyName,
    due: due,
    bills: bills,
    phone: phone,
    group: group,
    unpriced: unpriced,
    result: result,
  );

  Map<String, Object?> toJson() => {
    'no': lineNo,
    'party_id': partyId,
    'name': partyName,
    'phone': phone,
    'group': group,
    'due_paisa': due.inPaisa,
    'unpriced': unpriced,
    'bills': [for (final b in bills) b.toJson()],
    'result': result?.toJson(),
  };

  static SheetLine fromJson(Map<String, Object?> json) => SheetLine(
    lineNo: json['no'] as int? ?? 0,
    partyId: json['party_id'] as String? ?? '',
    partyName: json['name'] as String? ?? '',
    phone: json['phone'] as String?,
    group: json['group'] as String?,
    due: Money.paisa(json['due_paisa'] as int? ?? 0),
    unpriced: json['unpriced'] as int? ?? 0,
    bills: [
      for (final b in (json['bills'] as List<Object?>? ?? const []))
        if (b is Map<String, Object?>) SheetBill.fromJson(b),
    ],
    result: SheetResult.fromJson(json['result']),
  );
}

/// A numbered round for one recovery man.
final class CollectionSheet {
  const CollectionSheet({
    required this.id,
    required this.sheetNo,
    required this.dateLocal,
    required this.collector,
    required this.lines,
    this.collectorUserId,
    this.madeBy = '',
    this.title,
    this.settledOn,
    this.settledBy,
  });

  /// The settings row's id.
  final String id;

  /// `WS-2627-0001`.
  final String sheetNo;

  /// The day it was made, `YYYY-MM-DD`.
  final String dateLocal;

  /// Who took it: a member of staff, or a name typed in.
  final String collector;
  final String? collectorUserId;

  /// Who made it.
  final String madeBy;

  /// What it was made from, in words: "Route 3", "Late".
  final String? title;

  /// The day his return was recorded, and by whom. Null while it is out.
  final String? settledOn;
  final String? settledBy;

  final List<SheetLine> lines;

  bool get isSettled => settledOn != null;

  /// What the khata said all of them owed when it was made.
  Money get expected => Money.sum([for (final l in lines) l.due]);

  /// What came in on the round.
  Money get collected =>
      Money.sum([for (final l in lines) l.result?.received ?? Money.zero]);

  /// The cash the man should be handing over: what came in cash.
  Money get cashToHandOver => Money.sum([
    for (final l in lines)
      if (l.result case final r? when r.mode == 'cash') r.received,
  ]);

  /// What was promised, where a figure was said.
  Money get promised => Money.sum([
    for (final l in lines)
      if (l.result case final r? when r.outcome == CollectionOutcome.promise)
        r.amount ?? Money.zero,
  ]);

  /// How many lines ended each way.
  int count(CollectionOutcome outcome) =>
      lines.where((l) => l.result?.outcome == outcome).length;

  /// Lines the man did not reach (or that were left unmarked).
  int get notReached => lines.where((l) => l.result == null).length;

  CollectionSheet settled({
    required String on,
    required String by,
    required List<SheetLine> lines,
  }) => CollectionSheet(
    id: id,
    sheetNo: sheetNo,
    dateLocal: dateLocal,
    collector: collector,
    collectorUserId: collectorUserId,
    madeBy: madeBy,
    title: title,
    settledOn: on,
    settledBy: by,
    lines: lines,
  );

  CollectionSheet withId(String id) => CollectionSheet(
    id: id,
    sheetNo: sheetNo,
    dateLocal: dateLocal,
    collector: collector,
    collectorUserId: collectorUserId,
    madeBy: madeBy,
    title: title,
    settledOn: settledOn,
    settledBy: settledBy,
    lines: lines,
  );

  /// The row's value. The id is the row's own, and not repeated in it.
  Map<String, Object?> toJson() => {
    'no': sheetNo,
    'date': dateLocal,
    'collector': collector,
    'collector_user_id': collectorUserId,
    'made_by': madeBy,
    'title': title,
    'settled_on': settledOn,
    'settled_by': settledBy,
    'lines': [for (final l in lines) l.toJson()],
  };

  /// Read back from its row; null when the value is not a sheet.
  static CollectionSheet? fromJson(String id, Object? json) {
    if (json is! Map<String, Object?>) return null;
    final no = json['no'];
    if (no is! String) return null;
    return CollectionSheet(
      id: id,
      sheetNo: no,
      dateLocal: json['date'] as String? ?? '',
      collector: json['collector'] as String? ?? '',
      collectorUserId: json['collector_user_id'] as String?,
      madeBy: json['made_by'] as String? ?? '',
      title: json['title'] as String?,
      settledOn: json['settled_on'] as String?,
      settledBy: json['settled_by'] as String?,
      lines: [
        for (final l in (json['lines'] as List<Object?>? ?? const []))
          if (l is Map<String, Object?>) SheetLine.fromJson(l),
      ],
    );
  }
}

/// What the owner asks for when making a sheet.
final class SheetDraft {
  const SheetDraft({
    required this.partyIds,
    required this.collector,
    this.collectorUserId,
    this.title,
  });

  /// The customers, in the order the man is to visit them.
  final List<String> partyIds;
  final String collector;
  final String? collectorUserId;
  final String? title;

  /// Why this cannot be made, in words, or null when it can.
  String? get problem {
    if (collector.trim().isEmpty) {
      return 'Name the man taking the sheet.';
    }
    if (partyIds.isEmpty) {
      return 'Pick at least one customer for the sheet.';
    }
    if (partyIds.toSet().length != partyIds.length) {
      return 'A customer is on the sheet twice.';
    }
    return null;
  }
}

/// What the owner marks against one line on the man's return.
final class SheetMark {
  const SheetMark({
    required this.outcome,
    this.amount,
    this.promisedFor,
    this.mode = 'cash',
    this.paymentAccountId,
    this.note,
  });

  final CollectionOutcome outcome;

  /// Paid in full: left empty, it is what the sheet said they owed.
  final Money? amount;
  final String? promisedFor;
  final String mode;
  final String? paymentAccountId;
  final String? note;

  /// What came in for [line], once the full amount is filled in.
  Money? amountFor(SheetLine line) => switch (outcome) {
    CollectionOutcome.paid => amount ?? line.due,
    _ => amount,
  };

  /// Why this cannot be recorded against [line] on [today], in words, or
  /// null when it can.
  String? problemFor(SheetLine line, String today) {
    switch (outcome) {
      case CollectionOutcome.paid || CollectionOutcome.partial:
        final money = amountFor(line);
        if (money == null || !money.isPositive) {
          return '${line.partyName}: write what came in.';
        }
        if (paymentAccountId == null) {
          return '${line.partyName}: pick how the money came.';
        }
        // A cheque has a number, a bank and a day it can be banked, and is
        // taken on the khata's own Receive, where those are written; a
        // round's line has room for none of them.
        if (mode == 'cheque') {
          return '${line.partyName}: take a cheque on their khata, where '
              'its number and bank are written.';
        }
      case CollectionOutcome.promise:
        final day = BusinessDate.tryParse(promisedFor ?? '');
        if (day == null) {
          return '${line.partyName}: pick the day they said they would pay.';
        }
        if (promisedFor!.compareTo(today) < 0) {
          return '${line.partyName}: a promise is for today or a day to come.';
        }
        final money = amount;
        if (money != null && !money.isPositive) {
          return '${line.partyName}: an amount promised has to be more than '
              'nothing.';
        }
      case CollectionOutcome.shopClosed || CollectionOutcome.refused:
        break;
    }
    return null;
  }

  /// The result this mark writes, before its receipt or promise is known.
  SheetResult resultFor(SheetLine line) => SheetResult(
    outcome: outcome,
    amount: amountFor(line),
    promisedFor: outcome == CollectionOutcome.promise ? promisedFor : null,
    mode: outcome.tookMoney ? mode : null,
    paymentAccountId: outcome.tookMoney ? paymentAccountId : null,
    note: note,
  );
}
