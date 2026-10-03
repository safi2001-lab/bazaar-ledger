import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'drift_purchase_writer.dart';
import 'tx_runner.dart';

/// The mobile-shop pack's writes (M50): what PTA said of a phone, its second
/// IMEI, a warranty claim against it, a qist plan closed early, and a used
/// phone bought over the counter with its seller's register row.
///
/// Everything goes through [TxRunner], so each is audited, carried to the
/// other counters, and held to the owner's closed books.
final class DriftMobileWriter implements MobileStore {
  const DriftMobileWriter(this._runner);

  final TxRunner _runner;

  /// The group a seller the shop first meets over a used phone is kept in,
  /// so the supplier list can be narrowed to the shop's real suppliers.
  static const sellerGroup = 'Used phone sellers';

  @override
  Future<void> setPta(ActorContext actor, String lotId, PtaStatus status) =>
      _runner.run(actor, (tx) async {
        final phone = await _phone(tx, lotId);
        final was = phone.readNullable<String>('pta_status');
        final today = actor.businessDate.value;
        if (was == status.code &&
            phone.readNullable<String>('pta_checked_on_local') == today) {
          return;
        }
        await tx.update('stock_lots', lotId, {
          'pta_status': status.code,
          'pta_checked_on_local': today,
        });
        tx.audit(
          action: 'PHONE_PTA_SET',
          entityTable: 'stock_lots',
          entityId: lotId,
          summary:
              '${phone.read<String>('item_name')} '
              '${phone.read<String>('serial')}: ${status.printed}',
          before: {'pta_status': was},
          after: {'pta_status': status.code},
        );
      });

  @override
  Future<void> setImei2(ActorContext actor, String lotId, String imei2) async {
    final problem = imeiProblem(imei2);
    if (problem != null) throw ImeiRefused(problem);
    final digits = imeiDigits(imei2);
    await _runner.run(actor, (tx) async {
      final phone = await _phone(tx, lotId);
      if (phone.read<String>('serial') == digits) {
        throw ImeiRefused(ImeiProblem(ImeiProblemKind.sameAsFirst, digits));
      }
      await refuseImeiHeldElsewhere(tx, [digits], exceptLotId: lotId);
      final was = phone.readNullable<String>('serial_2');
      if (was == digits) return;
      await tx.update('stock_lots', lotId, {'serial_2': digits});
      tx.audit(
        action: 'PHONE_IMEI2_SET',
        entityTable: 'stock_lots',
        entityId: lotId,
        summary:
            '${phone.read<String>('item_name')} '
            '${phone.read<String>('serial')}: IMEI 2 $digits',
        before: {'serial_2': was},
        after: {'serial_2': digits},
      );
    });
  }

  @override
  Future<String> recordWarrantyClaim(
    ActorContext actor,
    String lotId,
    String note,
  ) async {
    final said = note.trim();
    if (said.isEmpty) {
      throw const MobileRefused('Write what the claim is about.');
    }
    return _runner.run(actor, (tx) async {
      final phone = await _phone(tx, lotId);
      final id = await tx.insert('warranty_claims', {
        'lot_id': lotId,
        'claimed_on_local': actor.businessDate.value,
        'note': said,
      });
      tx.audit(
        action: 'WARRANTY_CLAIM_RECORDED',
        entityTable: 'stock_lots',
        entityId: lotId,
        summary:
            'Warranty claim on ${phone.read<String>('item_name')} '
            '${phone.read<String>('serial')}: $said',
      );
      return id;
    });
  }

  @override
  Future<void> closeQistEarly(
    ActorContext actor,
    String planId, {
    String? note,
  }) => _runner.run(actor, (tx) async {
    final plan = await tx.selectOne(
      'SELECT q.closed_on_local, d.doc_no, d.status, p.name '
      'FROM qist_plans q JOIN documents d ON d.id = q.document_id '
      'JOIN parties p ON p.id = q.party_id '
      'WHERE q.id = ? AND q.firm_id = ? AND q.deleted_at_utc IS NULL',
      [planId, actor.firmId],
    );
    if (plan == null) throw StateError('No qist plan $planId in this shop.');
    if (plan.readNullable<String>('closed_on_local') != null) {
      throw const MobileRefused('This qist plan is already closed.');
    }
    if (plan.read<String>('status') == 'void') {
      throw const MobileRefused(
        'The bill this plan was sold on is cancelled; there is nothing left '
        'to close.',
      );
    }
    final why = note?.trim();
    await tx.update('qist_plans', planId, {
      'closed_on_local': actor.businessDate.value,
      'close_note': why == null || why.isEmpty ? null : why,
    });
    tx.audit(
      action: 'QIST_CLOSED_EARLY',
      entityTable: 'qist_plans',
      entityId: planId,
      summary:
          'Qist on ${plan.read<String>('doc_no')} '
          '(${plan.read<String>('name')}) closed early: what is left is due '
          'now',
      after: {'closed_on_local': actor.businessDate.value, 'close_note': why},
    );
  });

  /// Buys a used phone over the counter, in one transaction: the seller
  /// found by CNIC or kept as a new supplier, the delivery [purchase] writes
  /// through the writer it is handed (on this same transaction), and the
  /// register row naming the seller as they were on the day.
  ///
  /// [purchase] is the purchase use case, run by the caller, so the phone
  /// goes onto the shelf by exactly the path every delivery takes: the stock
  /// at what was paid, the cash out of the drawer, the IMEI its lot.
  Future<({String documentId, String docNo, String partyId, String lotId})>
  buyUsedPhone(
    ActorContext actor,
    UsedPhoneBuyDraft draft, {
    required Future<PostedPurchase> Function(
      PurchaseWriter sameTransaction,
      String sellerPartyId,
    )
    purchase,
  }) async {
    draft.check();
    return _runner.run(actor, (tx) async {
      final partyId = await _sellerParty(tx, draft);
      final posted = await purchase(
        _OnThisTransaction(purchaseContextOn(tx)),
        partyId,
      );
      await tx.insert('used_phone_buys', {
        'document_id': posted.documentId,
        'party_id': partyId,
        'seller_name': draft.sellerName.trim(),
        'seller_cnic': draft.cnic,
        'seller_phone': _blank(draft.sellerPhone),
        'condition_note': _blank(draft.conditionNote),
      });
      final imei = draft.phone.imeis.first;
      final lot = await tx.selectOne(
        'SELECT id FROM stock_lots WHERE firm_id = ? AND item_id = ? '
        'AND lot_no = ?',
        [actor.firmId, draft.itemId, imei],
      );
      tx.audit(
        action: 'USED_PHONE_BOUGHT',
        entityTable: 'documents',
        entityId: posted.documentId,
        summary:
            'Used ${draft.itemName} $imei bought from '
            '${draft.sellerName.trim()} (CNIC ${cnicDisplay(draft.cnic)}) '
            'for Rs ${draft.price.amountOnly}',
        amountPaisa: draft.price.inPaisa,
      );
      return (
        documentId: posted.documentId,
        docNo: posted.docNo,
        partyId: partyId,
        lotId: lot!.read<String>('id'),
      );
    });
  }

  /// The supplier [draft]'s seller is kept as: the one already holding
  /// their CNIC, or a new one in [sellerGroup].
  Future<String> _sellerParty(Tx tx, UsedPhoneBuyDraft draft) async {
    final held = await tx.selectOne(
      'SELECT id, party_type FROM parties WHERE firm_id = ? '
      "AND replace(replace(cnic, '-', ''), ' ', '') = ? "
      'AND deleted_at_utc IS NULL ORDER BY is_active DESC, created_at_utc '
      'LIMIT 1',
      [tx.actor.firmId, draft.cnic],
    );
    if (held != null) {
      final id = held.read<String>('id');
      // A customer selling the shop their old phone is now a supplier too.
      if (held.read<String>('party_type') == 'customer') {
        await tx.update('parties', id, {'party_type': 'both'});
      }
      return id;
    }
    final name = draft.sellerName.trim();
    final id = await tx.insert('parties', {
      'name': name,
      'name_search': nameSearchColumn(name),
      'party_type': 'supplier',
      'party_group': sellerGroup,
      'phone': _blank(draft.sellerPhone),
      'cnic': cnicDisplay(draft.cnic),
      'opening_balance_as_of_local': tx.actor.businessDate.value,
    });
    tx.audit(
      action: 'PARTY_CREATED',
      entityTable: 'parties',
      entityId: id,
      summary: '$name added to the khata, selling a used phone',
    );
    return id;
  }

  Future<QueryRow> _phone(Tx tx, String lotId) async {
    final row = await tx.selectOne(
      'SELECT l.serial, l.serial_2, l.pta_status, l.pta_checked_on_local, '
      '       i.name AS item_name '
      'FROM stock_lots l JOIN items i ON i.id = l.item_id '
      'WHERE l.id = ? AND l.firm_id = ? AND l.deleted_at_utc IS NULL',
      [lotId, tx.actor.firmId],
    );
    if (row == null) throw StateError('No phone $lotId in this shop.');
    if (row.readNullable<String>('serial') == null) {
      throw const MobileRefused(
        'That is a batch, not a phone kept by its IMEI.',
      );
    }
    return row;
  }

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

/// A [PurchaseWriter] on a transaction already open: its "new" transaction
/// is that one.
final class _OnThisTransaction implements PurchaseWriter {
  _OnThisTransaction(this._context);

  final PurchaseWriteContext _context;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PurchaseWriteContext write) body,
  ) => body(_context);
}

/// Refuses [imeis] when a phone still in the shop already answers to any of
/// them, by IMEI 1 or IMEI 2, other than [exceptLotId] (M50).
///
/// A phone is one piece: the same number on two phones on the shelf is a
/// number typed wrong, or a cloned phone. One the shop sold and has back
/// again comes into the lot it always had (see `document_rows.dart`).
Future<void> refuseImeiHeldElsewhere(
  Tx tx,
  List<String> imeis, {
  String? exceptLotId,
}) async {
  if (imeis.isEmpty) return;
  final marks = List.filled(imeis.length, '?').join(', ');
  final held = await tx.selectOne(
    'SELECT l.serial, i.name AS item_name FROM stock_lots l '
    'JOIN items i ON i.id = l.item_id '
    'WHERE l.firm_id = ? AND l.deleted_at_utc IS NULL '
    '  AND (l.serial IN ($marks) OR l.serial_2 IN ($marks)) '
    '  AND (? IS NULL OR l.id <> ?) '
    '  AND COALESCE((SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s '
    '                WHERE s.lot_id = l.id AND s.deleted_at_utc IS NULL), 0) > 0 '
    'LIMIT 1',
    [tx.actor.firmId, ...imeis, ...imeis, exceptLotId, exceptLotId],
  );
  if (held != null) {
    throw StockRefused(
      'A phone with that IMEI is already in the shop: '
      '${held.read<String>('item_name')} ${held.read<String>('serial')}. '
      'One IMEI is one phone.',
    );
  }
}

/// Each of [itemIds]'s warranty in months, for the items that have one
/// (M50). Read inside the bill's own transaction, so the day a line's
/// warranty ends is stamped from the item as it stood when it was sold.
Future<Map<String, int>> warrantyMonthsOf(
  Tx tx,
  Iterable<String> itemIds,
) async {
  final ids = itemIds.toSet().toList();
  if (ids.isEmpty) return const {};
  final rows = await tx.select(
    'SELECT id, warranty_months FROM items '
    'WHERE firm_id = ? AND warranty_months IS NOT NULL '
    'AND id IN (${List.filled(ids.length, '?').join(', ')})',
    [tx.actor.firmId, ...ids],
  );
  return {
    for (final r in rows) r.read<String>('id'): r.read<int>('warranty_months'),
  };
}

/// Writes a bill's qist plan and its instalments, inside the sale's own
/// transaction (M50), so a plan cannot exist for a bill that did not post,
/// nor a qist bill without its plan.
///
/// The schedule is worked out again from what the bill finally owes: a
/// bill made from a sale order takes the order's advance into its paid
/// amount after the builder has run (M41), and the instalments must add up
/// to the balance the khata will carry, to the paisa.
Future<void> keepQistPlan(
  Tx tx, {
  required String documentId,
  required DocumentPosting document,
  required QistPosting plan,
}) async {
  final partyId = document.partyId;
  if (partyId == null) {
    throw const QistRefused('A phone on qist is sold to a named customer.');
  }
  final financed = document.balance;
  if (!financed.isPositive) {
    throw const QistRefused(
      'Nothing is left on the bill to pay in instalments.',
    );
  }
  final instalments = financed == plan.financed
      ? plan.instalments
      : scheduleInstalments(
          financed: financed,
          count: plan.instalments.length,
          firstDue: plan.instalments.first.dueOn,
          dueDay: plan.dueDay,
        );
  final guarantor = plan.guarantor;
  final guarantorCnic = guarantor?.cnic;
  final planId = await tx.insert('qist_plans', {
    'document_id': documentId,
    'party_id': partyId,
    'sold_on_local': document.docDateLocal,
    'down_payment_paisa': document.paid.inPaisa,
    'markup_paisa': plan.markup.inPaisa,
    'financed_paisa': financed.inPaisa,
    'instalment_count': instalments.length,
    'due_day': plan.dueDay,
    'guarantor_name': guarantor?.name.trim(),
    'guarantor_cnic': guarantorCnic == null || guarantorCnic.trim().isEmpty
        ? null
        : cnicDigits(guarantorCnic),
    'guarantor_phone': switch (guarantor?.phone?.trim()) {
      final p? when p.isNotEmpty => p,
      _ => null,
    },
  });
  for (final i in instalments) {
    await tx.insert('qist_instalments', {
      'plan_id': planId,
      'seq': i.seq,
      'due_on_local': i.dueOn.value,
      'amount_paisa': i.amount.inPaisa,
    });
  }
  tx.audit(
    action: 'QIST_PLAN_MADE',
    entityTable: 'qist_plans',
    entityId: planId,
    summary:
        'Qist on ${document.docNo}: Rs ${document.paid.amountOnly} down, '
        '${instalments.length} instalments from '
        '${instalments.first.dueOn.value}, Rs ${financed.amountOnly} in all',
    amountPaisa: financed.inPaisa,
  );
}
