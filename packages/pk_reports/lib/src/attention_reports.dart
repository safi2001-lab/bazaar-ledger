/// Dhyan dein, the shop's exception report (M67): one list of everything
/// odd today.
///
/// Tally keeps a set of exception reports behind Ctrl+J — negative stock,
/// negative cash, overdue bills, cancelled vouchers, post-dated cheques —
/// and an accountant opens them before anything else, because each is a
/// mistake or a loss that grows while nobody looks. A shopkeeper has no
/// Ctrl+J and no time for six reports, so here they are one list, the
/// worst kind first, each row a tap from the screen that puts it right:
///
/// * an item with less than nothing on the shelf, and apart from it an item
///   set to refuse a sale past its shelf (M53) that still went below: two
///   counters apart sold the last one each, and nobody has counted since;
/// * the drawer, a bank or a wallet below nothing, which no real drawer
///   ever is: a payment entered from the wrong account, or a sale not
///   entered at all;
/// * udhaar past its due date (M38) by more than the days the shop chose,
///   thirty unless it chose;
/// * a cheque in hand that can be banked today and is not, and one so old
///   the bank will refuse it: a cheque in Pakistan goes stale six months
///   after its date (M6);
/// * a bill cancelled today, with who did it and why (M31);
/// * a line sold today for less than it cost, for a role that may see
///   costs, a free line under a scheme (M43) aside;
/// * a batch past its expiry with stock still on the shelf (M11);
/// * a bill made offline still not with FBR a day after the connection
///   came back (Rule 150XC, M59).
///
/// Every row is read by the database as of today; nothing here is a figure
/// of its own, and each amount is the one the screen it opens shows.
library;

import 'package:pk_domain/pk_domain.dart';

import 'period.dart';
import 'report_table.dart';

/// One item below nothing on the shelf.
final class ShortItem {
  const ShortItem({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.qty,
    this.blocked = false,
  });

  final String itemId;
  final String itemName;
  final String unitCode;

  /// Less than nothing.
  final Qty qty;

  /// Set to refuse a sale past its shelf (M53), by its own rule or the
  /// shop's: it went below by the counters' merge, not by a cashier's yes.
  final bool blocked;
}

/// One money account below nothing.
final class OverdrawnAccount {
  const OverdrawnAccount({
    required this.accountId,
    required this.name,
    required this.balance,
  });

  final String accountId;
  final String name;
  final Money balance;
}

/// One customer whose udhaar is past due by the days chosen or more.
final class LateUdhaar {
  const LateUdhaar({
    required this.partyId,
    required this.name,
    required this.owed,
    required this.daysLate,
    this.phone,
  });

  final String partyId;
  final String name;
  final String? phone;

  /// What of their udhaar is that late.
  final Money owed;

  /// How late the oldest of it is.
  final int daysLate;
}

/// One bill cancelled today.
final class CancelledBill {
  const CancelledBill({
    required this.documentId,
    required this.docNo,
    required this.total,
    this.party,
    this.reason,
    this.by,
    this.docType = 'sale_invoice',
  });

  final String documentId;
  final String docNo;
  final String docType;
  final Money total;
  final String? party;
  final String? reason;

  /// Who cancelled it.
  final String? by;
}

/// One line sold today for less than it cost.
final class BelowCostLine {
  const BelowCostLine({
    required this.documentId,
    required this.docNo,
    required this.itemName,
    required this.sold,
    required this.cost,
  });

  final String documentId;
  final String docNo;
  final String itemName;

  /// What the line sold for, before tax, after every discount.
  final Money sold;

  /// What the goods cost when they left the shelf.
  final Money cost;
}

/// One bill made offline and still not with FBR a day after FBR could be
/// reached again.
final class LateFbrBill {
  const LateFbrBill({
    required this.documentId,
    required this.docNo,
    required this.madeOn,
  });

  final String documentId;
  final String docNo;
  final BusinessDate madeOn;
}

/// Everything odd in the shop, as of one day, as the database read it.
final class ShopExceptions {
  const ShopExceptions({
    this.shortItems = const [],
    this.overdrawn = const [],
    this.lateUdhaar = const [],
    this.cheques = const [],
    this.cancelled = const [],
    this.belowCost = const [],
    this.expired = const [],
    this.lateFbr = const [],
  });

  final List<ShortItem> shortItems;
  final List<OverdrawnAccount> overdrawn;
  final List<LateUdhaar> lateUdhaar;

  /// Every cheque in hand: the builder picks out those due and those
  /// stale.
  final List<ChequeInHand> cheques;
  final List<CancelledBill> cancelled;

  /// Empty for a role that may not see costs: never read for them.
  final List<BelowCostLine> belowCost;

  /// Batches past their date with stock on the shelf.
  final List<LotOnHand> expired;
  final List<LateFbrBill> lateFbr;
}

/// Where the attention list reads from (M67).
abstract interface class AttentionReportSource {
  /// Everything odd on [asOf]: udhaar [lateDays] or more past due; a sale
  /// below cost only [withCosts]; an FBR bill late by [nowUtc].
  Future<ShopExceptions> exceptions(
    String firmId,
    BusinessDate asOf, {
    required int lateDays,
    required DateTime nowUtc,
    required bool withCosts,
  });
}

/// The kinds of thing the list names, worst first.
enum AttentionKind {
  oversoldBlocked,
  stockBelowZero,
  moneyBelowZero,
  fbrLate,
  udhaarLate,
  chequeStale,
  chequeDue,
  billCancelled,
  soldBelowCost,
  batchExpired;

  /// As the What column writes it.
  String get title => switch (this) {
    oversoldBlocked => 'Oversold while set to block',
    stockBelowZero => 'Stock below zero',
    moneyBelowZero => 'Money below zero',
    fbrLate => 'Not with FBR after 24 hours',
    udhaarLate => 'Udhaar overdue',
    chequeStale => 'Cheque gone stale',
    chequeDue => 'Cheque can be banked',
    billCancelled => 'Bill cancelled today',
    soldBelowCost => 'Sold below cost today',
    batchExpired => 'Expired batch on the shelf',
  };
}

/// How long after its date a cheque can still be banked: six months, as
/// the Negotiable Instruments Act and every Pakistani bank have it.
const chequeValidMonths = 6;

/// Whether a cheque dated [due] is stale on [today].
bool chequeIsStale(BusinessDate due, BusinessDate today) {
  final last = DateTime.utc(due.year, due.month + chequeValidMonths, due.day);
  return !DateTime.utc(today.year, today.month, today.day).isBefore(last);
}

String _qty(Qty q, String unit) =>
    unit.isEmpty ? q.display : '${q.display} $unit';

/// The attention list for [asOf] (M67).
ReportTable needsAttention(
  BusinessDate asOf,
  ShopExceptions x, {
  required int lateDays,
}) {
  final rows = <(AttentionKind, ReportRow)>[];
  void add(
    AttentionKind kind,
    String who,
    String details,
    Money? amount,
    String? since,
    ReportLink? link,
  ) => rows.add((
    kind,
    ReportRow([kind.title, who, details, amount, since ?? ''], link: link),
  ));

  for (final s in x.shortItems) {
    add(
      s.blocked ? AttentionKind.oversoldBlocked : AttentionKind.stockBelowZero,
      s.itemName,
      s.blocked
          ? 'Shelf reads ${_qty(s.qty, s.unitCode)}: two counters sold the '
                'last ones while apart. Count the shelf.'
          : 'Shelf reads ${_qty(s.qty, s.unitCode)}: more was sold than '
                'was recorded coming in.',
      null,
      null,
      ReportLink.item(s.itemId, label: s.itemName, unitCode: s.unitCode),
    );
  }
  for (final a in x.overdrawn) {
    add(
      AttentionKind.moneyBelowZero,
      a.name,
      'The books show less than nothing in it: a payment from the wrong '
      'account, or money in not entered.',
      a.balance,
      null,
      ReportLink.account(a.accountId, label: a.name),
    );
  }
  for (final b in x.lateFbr) {
    add(
      AttentionKind.fbrLate,
      b.docNo,
      'Made offline and still not sent; Rule 150XC gives 24 hours from '
      'when FBR could be reached.',
      null,
      b.madeOn.value,
      const ReportLink.screen(ReportLink.fbr, label: 'FBR'),
    );
  }
  for (final u in x.lateUdhaar) {
    add(
      AttentionKind.udhaarLate,
      u.name,
      '${u.daysLate} days past due at the oldest'
      '${u.phone == null || u.phone!.isEmpty ? '' : ', ${u.phone}'}.',
      u.owed,
      null,
      ReportLink.party(u.partyId, label: u.name),
    );
  }
  for (final c in x.cheques) {
    final due = c.due;
    final stale = due != null && chequeIsStale(due, asOf);
    if (c.deposited && !stale) continue;
    if (stale) {
      add(
        AttentionKind.chequeStale,
        c.partyName,
        'Cheque ${c.chequeNo}${c.bank == null ? '' : ', ${c.bank}'} is six '
        'months past its date: the bank will not take it. Ask for a new '
        'one.',
        c.amount,
        due.value,
        const ReportLink.screen(ReportLink.cheques, label: 'Cheques'),
      );
    } else if (!c.deposited && c.isDueBy(asOf)) {
      add(
        AttentionKind.chequeDue,
        c.partyName,
        'Cheque ${c.chequeNo}${c.bank == null ? '' : ', ${c.bank}'} can be '
        'banked: it is still in the drawer.',
        c.amount,
        due?.value,
        const ReportLink.screen(ReportLink.cheques, label: 'Cheques'),
      );
    }
  }
  for (final b in x.cancelled) {
    add(
      AttentionKind.billCancelled,
      b.docNo,
      [
        ?b.party,
        if (b.by != null) 'by ${b.by}',
        if (b.reason != null && b.reason!.isNotEmpty) '"${b.reason}"',
      ].join(', '),
      b.total,
      asOf.value,
      ReportLink.document(b.documentId, label: b.docNo, docType: b.docType),
    );
  }
  for (final l in x.belowCost) {
    add(
      AttentionKind.soldBelowCost,
      l.itemName,
      'Sold for Rs ${l.sold.amountOnly} on ${l.docNo}, which cost '
      'Rs ${l.cost.amountOnly}.',
      l.sold - l.cost,
      asOf.value,
      ReportLink.document(
        l.documentId,
        label: l.docNo,
        docType: 'sale_invoice',
      ),
    );
  }
  for (final b in x.expired) {
    add(
      AttentionKind.batchExpired,
      b.itemName,
      'Batch ${b.lotNo}: ${b.qty.display} still on the shelf. The counter '
      'will not sell it; send it back or write it off.',
      b.cost.amountFor(b.qty),
      b.expiry?.value,
      ReportLink.item(b.itemId, label: b.itemName),
    );
  }

  // The worst kind first, and within a kind as each was read: the
  // database's own order, the most owed or the oldest first.
  final ordered = [
    for (final kind in AttentionKind.values)
      for (final r in rows)
        if (r.$1 == kind) r.$2,
  ];
  final counts = {
    for (final kind in AttentionKind.values)
      kind: rows.where((r) => r.$1 == kind).length,
  };
  final n = ordered.length;
  return ReportTable(
    id: 'needs_attention',
    title: 'Needs attention',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('What', CellKind.text),
      ReportColumn('Who or which', CellKind.text),
      ReportColumn('Details', CellKind.text),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Since', CellKind.text),
    ],
    rows: [
      ...ordered,
      ReportRow([
        'Total',
        n == 1 ? '1 thing to look at' : '$n things to look at',
        null,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count(attentionTotalLabel, n),
      for (final kind in AttentionKind.values)
        if (counts[kind]! > 0) ReportFigure.count(kind.title, counts[kind]!),
    ],
    notes: [if (n == 0) 'Nothing odd today.', _fromDays(lateDays), _notASum],
  );
}

String _fromDays(int lateDays) =>
    'Udhaar is listed from $lateDays days past its due date. A cheque goes '
    'stale $chequeValidMonths months after its date.';

const _notASum =
    "Amounts are each row's own and are not added up: a cheque, a shortfall "
    'and a loss are not one sum.';

/// The headline figure of the attention list: how many things it names.
const attentionTotalLabel = 'Things to look at';
