import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// Loyalty points as the books stand (M66): every sale bill of a named
/// customer with the money that came in against it, what came back off it
/// and the points it spent.
///
/// Nothing about points is stored but the points a bill spent (one
/// `settings` row per such bill, written in the bill's own commit) and the
/// shop's rule. What a customer earned is read off the books every time —
/// the payments against their bills, the returns linked to them, which of
/// them are cancelled — so it cannot fall out of step with the khata: a
/// cheque that bounces stops earning the day it bounces, a payment taken
/// back (M31) takes its points with it, a cancelled bill gives back what it
/// spent, and two counters that meet over the wi-fi agree without either
/// having to tell the other anything about points.
///
/// The money that earns is cleared money in: a cheque in hand earns when it
/// clears, and an `adjustment` (a settlement discount or a write-off, M44)
/// is not money at all. [narrow] is SQL over `d`, the bill, with `?1` the
/// firm's id; it is trusted, and only ever this file's own or the report
/// filters' bound parameters.
String loyaltyBillsSql([String narrow = '']) =>
    '''
  SELECT d.id, d.doc_no, d.doc_date_local, d.party_id, d.status,
         d.total_paisa, d.subtotal_paisa, COALESCE(d.posted_at_utc, 0) AS posted,
         COALESCE((
           SELECT SUM(a.amount_paisa) FROM payment_allocations a
           JOIN payments p ON p.id = a.payment_id
           WHERE a.document_id = d.id AND a.deleted_at_utc IS NULL
             AND p.deleted_at_utc IS NULL AND p.direction = 'in'
             AND p.status = 'cleared' AND p.mode <> 'adjustment'
         ), 0) AS paid,
         COALESCE((
           SELECT SUM(r.total_paisa) FROM doc_links l
           JOIN documents r ON r.id = l.to_document_id
           WHERE l.from_document_id = d.id AND l.link_type = 'returns'
             AND l.deleted_at_utc IS NULL AND r.doc_type = 'sale_return'
             AND r.status = 'posted' AND r.deleted_at_utc IS NULL
         ), 0) AS returned,
         COALESCE((
           SELECT SUM(r.subtotal_paisa) FROM doc_links l
           JOIN documents r ON r.id = l.to_document_id
           WHERE l.from_document_id = d.id AND l.link_type = 'returns'
             AND l.deleted_at_utc IS NULL AND r.doc_type = 'sale_return'
             AND r.status = 'posted' AND r.deleted_at_utc IS NULL
         ), 0) AS returned_goods,
         (SELECT s.setting_value FROM settings s
           WHERE s.firm_id = d.firm_id
             AND s.setting_key = '$loyaltyRedeemedKeyPrefix' || d.id
             AND s.deleted_at_utc IS NULL) AS redeemed
  FROM documents d
  WHERE d.firm_id = ?1 AND d.doc_type = 'sale_invoice'
    AND d.status IN ('posted', 'void') AND d.deleted_at_utc IS NULL
    AND d.party_id IS NOT NULL $narrow
  ORDER BY d.party_id, d.doc_date_local, posted, d.doc_no
''';

/// One row of [loyaltyBillsSql].
LoyaltyBill loyaltyBillFrom(QueryRow r) {
  final spent = LoyaltyRedemption.fromJson(r.readNullable<String>('redeemed'));
  return LoyaltyBill(
    documentId: r.read<String>('id'),
    docNo: r.read<String>('doc_no'),
    date: r.read<String>('doc_date_local'),
    total: Money.paisa(r.read<int>('total_paisa')),
    goods: Money.paisa(r.read<int>('subtotal_paisa')),
    paid: Money.paisa(r.read<int>('paid')),
    returned: Money.paisa(r.read<int>('returned')),
    returnedGoods: Money.paisa(r.read<int>('returned_goods')),
    redeemedPoints: spent?.points ?? 0,
    redeemedValue: spent?.value ?? Money.zero,
    isVoid: r.read<String>('status') == 'void',
    postedAtUtc: r.read<int>('posted'),
  );
}

/// The shop's rule, every version of it.
Future<LoyaltyRules> loyaltyRulesOf(AppDatabase db, String firmId) async {
  final row = await db
      .customSelect(
        'SELECT setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        variables: [
          Variable<String>(firmId),
          const Variable<String>(loyaltyRulesKey),
        ],
      )
      .getSingleOrNull();
  return LoyaltyRules.fromJson(row?.read<String>('setting_value'));
}

/// Every sale bill of [partyId], as loyalty counts them.
Future<List<LoyaltyBill>> loyaltyBillsOf(
  AppDatabase db,
  String firmId,
  String partyId,
) async {
  final rows = await db
      .customSelect(
        loyaltyBillsSql('AND d.party_id = ?2'),
        variables: [Variable<String>(firmId), Variable<String>(partyId)],
      )
      .get();
  return [for (final r in rows) loyaltyBillFrom(r)];
}

/// [paper] with what a customer's points say at its foot (M66), when the
/// shop gives points: what this bill earned ("Is bill par 25 points mile"),
/// what it will earn once its udhaar is paid, what it spent, and what the
/// customer held once it was made ("Kul 340 points").
///
/// Read by the receipt read itself, as M50's phone details are, so the till
/// roll, the PDF, the picture and a reprint all say the same. The total is
/// as it stood when the bill was made — the bills up to it, on its day —
/// so a copy printed next month does not say what the customer holds then.
/// In Roman Urdu, as the paper's own thanks is, and in plain ASCII: a till
/// roll's Latin code page prints a middle dot as a question mark.
Future<ReceiptData> loyaltyOnPaper(
  AppDatabase db,
  String firmId,
  String documentId,
  ReceiptData paper,
) async {
  final doc = await db
      .customSelect(
        'SELECT party_id FROM documents WHERE id = ? AND firm_id = ? '
        "AND doc_type = 'sale_invoice' AND deleted_at_utc IS NULL",
        variables: [Variable<String>(documentId), Variable<String>(firmId)],
      )
      .getSingleOrNull();
  final partyId = doc?.readNullable<String>('party_id');
  if (partyId == null) return paper;
  final rules = await loyaltyRulesOf(db, firmId);
  if (rules.isEmpty) return paper;
  final bills = await loyaltyBillsOf(db, firmId, partyId);
  final bill = bills.where((b) => b.documentId == documentId).firstOrNull;
  if (bill == null || bill.isVoid) return paper;
  final rule = rules.ruleFor(bill);
  final spent = bill.redeemedPoints;
  if ((rule == null || !rule.isOn) && spent == 0) return paper;

  final earned = bill.earnedBy(rules);
  final later = bill.earnsWhenPaid(rules) - earned;
  final total = loyaltyStandingAt(rules, bills, bill).outstanding;
  final earning = later > 0
      ? 'Is bill par $earned points mile, $later aur ada hone par'
      : 'Is bill par $earned points mile';
  return paper.copyWith(
    footerLines: [
      if (spent > 0)
        '$spent points istemal hue (Rs ${bill.redeemedValue.amountOnly})',
      '$earning - Kul $total points',
      ...paper.footerLines,
    ],
  );
}
