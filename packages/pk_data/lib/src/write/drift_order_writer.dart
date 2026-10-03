import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// Purchase orders, sale orders and the shortage list (M41), each through
/// the one write path with its audit row.
///
/// An order writes a document and its lines and nothing else: no stock
/// ledger, no journal, no payment. Its balance is zero, so no receivable or
/// payable query can mistake it for money owed, and every report that sums
/// sales or purchases already filters to the doc types that are those.
///
/// The shortage list is not the books either. Each line on it is a row in
/// the firm's `settings` (`shortage.<id>`, JSON), one row per line so two
/// counters writing on the same busy evening each keep theirs when the LAN
/// sync merges, the way M38 keeps promises. No table was added: the schema
/// was not this milestone's to change, and a line on a shortage list is a
/// small note about the shelf, which is what settings rows already are.
final class DriftOrderWriter {
  const DriftOrderWriter({
    required this.runner,
    required this.ids,
    this.sequences = const SequenceAllocator(),
    this.builder = const OrderBuilder(),
  });

  final TxRunner runner;
  final IdGenerator ids;
  final SequenceAllocator sequences;
  final OrderBuilder builder;

  /// Writes [draft]. Returns its id and number.
  Future<({String id, String docNo})> save(
    ActorContext actor,
    OrderDraft draft,
  ) => runner.run(actor, (tx) => _save(tx, draft));

  /// Writes every one of [drafts] in one commit: the purchase orders the
  /// reorder screen makes, one per supplier, all or none.
  Future<List<({String id, String docNo})>> saveAll(
    ActorContext actor,
    List<OrderDraft> drafts,
  ) => runner.run(actor, (tx) async {
    if (drafts.isEmpty) {
      throw const OrderRefused('There is nothing to order.');
    }
    return [for (final d in drafts) await _save(tx, d)];
  });

  Future<({String id, String docNo})> _save(Tx tx, OrderDraft draft) async {
    final actor = tx.actor;
    final party = await tx.selectOne(
      'SELECT name FROM parties '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [draft.partyId, actor.firmId],
    );
    if (party == null) {
      throw OrderRefused(
        draft.kind == OrderKind.purchase
            ? 'That supplier is not in this shop\'s list.'
            : 'That customer is not in this khata.',
      );
    }
    for (final l in draft.lines) {
      final item = await tx.selectOne(
        'SELECT id FROM items '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [l.itemId, actor.firmId],
      );
      if (item == null) {
        throw OrderRefused('${l.itemName} is no longer in the items list.');
      }
    }
    final n = await sequences.allocate(
      tx,
      docType: draft.kind.docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    final posting = builder.build(
      actor: actor,
      draft: OrderDraft(
        kind: draft.kind,
        partyId: draft.partyId,
        // The name as the khata has it today, kept on the paper as every
        // document keeps it, so a supplier renamed next year does not
        // rewrite this year's orders.
        partyName: party.read<String>('name'),
        lines: draft.lines,
        dueDate: draft.dueDate,
        notes: draft.notes,
      ),
      number: AllocatedNumber(
        formatted: n.formatted,
        series: n.series,
        sequence: n.sequence,
      ),
    );
    final (id, _) = await insertDocumentRows(
      tx,
      posting.document,
      posting.lines,
    );
    tx.audit(
      action: draft.kind == OrderKind.purchase
          ? 'PURCHASE_ORDER_PLACED'
          : 'SALE_ORDER_TAKEN',
      entityTable: 'documents',
      entityId: id,
      summary: posting.auditSummary,
      amountPaisa: posting.document.total.inPaisa,
    );
    return (id: id, docNo: n.formatted);
  }

  /// Cancels the order [orderId], saying why.
  ///
  /// What already came of it stands — a delivery received, a bill made —
  /// and the order then reads closed rather than cancelled: the rest of it
  /// will not come. An advance taken on a sale order stays on the
  /// customer's khata as money the shop holds for them, to be used or
  /// handed back the way any advance is.
  Future<void> cancel(
    ActorContext actor, {
    required String orderId,
    required String reason,
  }) => runner.run(actor, (tx) async {
    final why = reason.trim();
    if (why.isEmpty) {
      throw const OrderRefused('A cancellation has to say why.');
    }
    final doc = await tx.selectOne(
      'SELECT doc_no, doc_type, status FROM documents '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [orderId, actor.firmId],
    );
    final kind = doc == null
        ? null
        : OrderKind.ofDocType(doc.read<String>('doc_type'));
    if (doc == null || kind == null) {
      throw const OrderRefused('That is not an order of this shop.');
    }
    final no = doc.read<String>('doc_no');
    if (doc.read<String>('status') == 'void') {
      throw OrderRefused('$no is already cancelled.');
    }
    // The only change. The paper the supplier or the customer is holding
    // still matches it; it is simply no longer standing.
    await tx.update('documents', orderId, {
      'status': 'void',
      'void_reason': why,
    });
    tx.audit(
      action: 'ORDER_CANCELLED',
      entityTable: 'documents',
      entityId: orderId,
      summary: '$no cancelled: $why',
    );
  });

  // -------------------------------------------------------------------------
  // The shortage list
  // -------------------------------------------------------------------------

  /// Puts [draft] on the shortage list. Returns the line's id.
  Future<String> addShortage(ActorContext actor, ShortageDraft draft) =>
      runner.run(actor, (tx) async {
        var name = draft.name.trim();
        if (draft.itemId case final itemId?) {
          final item = await tx.selectOne(
            'SELECT name FROM items '
            'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
            [itemId, actor.firmId],
          );
          if (item == null) {
            throw const OrderRefused('That item is not in the list.');
          }
          name = item.read<String>('name');
        }
        if (name.isEmpty) {
          throw const OrderRefused('Write what the customer asked for.');
        }
        if (draft.qty case final q? when !q.isPositive) {
          throw const OrderRefused('How many was asked for?');
        }
        final note = draft.note?.trim();
        final id = ids.next();
        await tx.insert('settings', {
          'setting_key': '$shortageKeyPrefix$id',
          'setting_value': jsonEncode({
            'name': name,
            'item_id': ?draft.itemId,
            'qty': ?draft.qty?.inThousandths,
            'unit': ?draft.unitCode,
            if (note != null && note.isNotEmpty) 'note': note,
            'on': actor.businessDate.value,
          }),
          'value_type': 'json',
        }, id: id);
        tx.audit(
          action: 'SHORTAGE_NOTED',
          entityTable: 'settings',
          entityId: id,
          summary:
              '$name asked for'
              '${draft.qty == null ? '' : ', ${draft.qty!.display}'}',
        );
        return id;
      });

  /// Takes [entryIds] off the shortage list: got in, or no longer wanted.
  /// Struck out rather than destroyed, so the activity log can still say
  /// who wrote it and who took it off.
  Future<void> clearShortage(ActorContext actor, List<String> entryIds) =>
      runner.run(actor, (tx) async {
        for (final id in entryIds) {
          final row = await tx.selectOne(
            'SELECT setting_key, setting_value FROM settings '
            'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
            [id, actor.firmId],
          );
          if (row == null ||
              !row.read<String>('setting_key').startsWith(shortageKeyPrefix)) {
            continue;
          }
          await tx.softDelete('settings', id);
          final value = jsonDecode(row.read<String>('setting_value'));
          tx.audit(
            action: 'SHORTAGE_CLEARED',
            entityTable: 'settings',
            entityId: id,
            summary:
                '${value is Map ? value['name'] ?? 'A line' : 'A line'} '
                'taken off the shortage list',
          );
        }
      });
}

/// The settings key every line of the shortage list starts with.
const shortageKeyPrefix = 'shortage.';

// ---------------------------------------------------------------------------
// Where orders meet the documents that fill them
// ---------------------------------------------------------------------------

/// Links the delivery [deliveryId] to the purchase order [orderId] it
/// arrived against (M41), inside the delivery's own transaction.
///
/// Refused for an order that is not a standing purchase order of the same
/// supplier: goods from Haji Traders cannot fill an order placed with the
/// mill, and an order cancelled is not one anything arrives against.
Future<void> linkDeliveryToOrder(
  Tx tx, {
  required String orderId,
  required String deliveryId,
  required String? supplierId,
  required Money total,
}) async {
  final order = await tx.selectOne(
    'SELECT doc_no, doc_type, status, party_id FROM documents '
    'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
    [orderId, tx.actor.firmId],
  );
  if (order == null || order.read<String>('doc_type') != 'purchase_order') {
    throw const OrderRefused('That is not a purchase order of this shop.');
  }
  final no = order.read<String>('doc_no');
  if (order.read<String>('status') != 'posted') {
    throw OrderRefused('$no is cancelled, so nothing arrives against it.');
  }
  if (order.readNullable<String>('party_id') != supplierId) {
    throw OrderRefused('$no was placed with another supplier.');
  }
  await tx.insert('doc_links', {
    'from_document_id': orderId,
    'to_document_id': deliveryId,
    'link_type': 'converted_from',
    'amount_paisa': total.inPaisa,
  });
}

/// Whether [documentId] is a sale order (M41).
///
/// A sale order is billed a delivery at a time, so unlike a quotation it is
/// never "already billed": what is left of it is read off its bills.
Future<bool> isSaleOrder(Tx tx, String documentId) async {
  final row = await tx.selectOne(
    'SELECT doc_type FROM documents WHERE id = ? AND firm_id = ?',
    [documentId, tx.actor.firmId],
  );
  return row?.read<String>('doc_type') == OrderKind.sale.docType;
}

/// [posting] with the advance its customer paid on the sale order it was
/// made from taken off what they owe on it (M41); [posting] itself when it
/// was made from no sale order, or there is no advance left to take.
///
/// A bill made from a challan that was made from a sale order takes that
/// order's advance too: the challan is how the goods went, and the order is
/// what was paid for.
Future<SalePosting> withHeldAdvances(Tx tx, SalePosting posting) async {
  final partyId = posting.document.partyId;
  if (partyId == null) return posting;
  final sources = [?posting.convertedFromId, ...posting.alsoFromIds];
  var out = posting;
  // Two challans from two of the customer's orders billed together draw on
  // one holding, so what the first takes comes off what the second may.
  var used = Money.zero;
  for (final sourceId in sources) {
    final order = await orderBehind(
      tx.selectOne,
      firmId: tx.actor.firmId,
      sourceId: sourceId,
      partyId: partyId,
    );
    if (order == null) continue;
    final (:left, :holding) = await advanceOn(
      tx,
      orderId: order.id,
      partyId: partyId,
    );
    final room = holding - used;
    final take = left > room ? room : left;
    if (!take.isPositive) continue;
    final before = out.document.paid;
    out = withOrderAdvance(out, take, orderNo: order.docNo);
    used += out.document.paid - before;
  }
  return out;
}

/// M54: one row read, from inside a transaction ([Tx.selectOne]) or from the
/// database as a screen reads it, so the counter asks what a bill will take
/// of an order's advance by the very reads the bill takes it with.
typedef OneRow = Future<QueryRow?> Function(String sql, [List<Object?> args]);

/// The sale order a bill made from [sourceId] draws its advance on: the
/// order itself, or the order the challan [sourceId] was made from (M41).
/// Null when [sourceId] is neither, or the order is no longer [partyId]'s.
Future<({String id, String docNo})?> orderBehind(
  OneRow one, {
  required String firmId,
  required String sourceId,
  required String partyId,
}) async {
  final order = await one(
    '''
    SELECT so.id, so.doc_no FROM documents so
    WHERE so.firm_id = ?1 AND so.doc_type = 'sale_order'
      AND so.status = 'posted' AND so.deleted_at_utc IS NULL
      AND so.party_id = ?3
      AND (so.id = ?2 OR so.id IN (
        SELECT link.from_document_id FROM doc_links link
        WHERE link.to_document_id = ?2
          AND link.link_type = 'converted_from'
          AND link.deleted_at_utc IS NULL))
    LIMIT 1
    ''',
    [firmId, sourceId, partyId],
  );
  if (order == null) return null;
  return (id: order.read<String>('id'), docNo: order.read<String>('doc_no'));
}

/// M54: what a bill to [partyId] made from [sourceIds], leaving [owed] on
/// the khata, will take of the advances held for their orders — the sum
/// [withHeldAdvances] takes, read before the bill is written so the
/// counter's credit limit can count it. Never more than [owed], nor than
/// the shop holds for the customer.
Future<Money> advanceForBill(
  OneRow one, {
  required String firmId,
  required String partyId,
  required List<String> sourceIds,
  required Money owed,
}) async {
  var used = Money.zero;
  for (final sourceId in sourceIds) {
    final room = owed - used;
    if (!room.isPositive) break;
    final order = await orderBehind(
      one,
      firmId: firmId,
      sourceId: sourceId,
      partyId: partyId,
    );
    if (order == null) continue;
    final (:left, :holding) = await advanceHeld(
      one,
      orderId: order.id,
      partyId: partyId,
    );
    var take = left;
    if (holding - used < take) take = holding - used;
    if (room < take) take = room;
    if (take.isPositive) used += take;
  }
  return used;
}

/// What is left of the advance paid on sale order [orderId] — the receipts
/// taken against it, less what bills made from it have already taken — and
/// what the shop holds for the customer in all, which `left` may never be
/// spent past: a refund or a bounced cheque since takes its share back.
Future<({Money left, Money holding})> advanceOn(
  Tx tx, {
  required String orderId,
  required String partyId,
}) => advanceHeld(tx.selectOne, orderId: orderId, partyId: partyId);

/// [advanceOn] through any reader (M54): the transaction's, or a screen's.
Future<({Money left, Money holding})> advanceHeld(
  OneRow one, {
  required String orderId,
  required String partyId,
}) async {
  final row = await one(
    '''
    SELECT
      COALESCE((
        SELECT SUM(p.amount_paisa - COALESCE((
                 SELECT SUM(pa.amount_paisa) FROM payment_allocations pa
                 WHERE pa.payment_id = p.id AND pa.deleted_at_utc IS NULL
               ), 0))
        FROM payments p
        WHERE p.firm_id = so.firm_id AND p.party_id = ?2
          AND p.direction = 'in' AND p.reference = so.doc_no
          AND p.status IN ('cleared', 'pending')
          AND p.deleted_at_utc IS NULL
      ), 0) AS paid,
      COALESCE((
        SELECT SUM(jl.debit_paisa - jl.credit_paisa)
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        JOIN documents bill ON bill.id = je.document_id
        WHERE a.system_key = 'customer_advances'
          AND jl.party_id = ?2 AND jl.deleted_at_utc IS NULL
          AND je.source_type = 'sale' AND je.deleted_at_utc IS NULL
          AND bill.status = 'posted'
          AND bill.id IN (
            SELECT l1.to_document_id FROM doc_links l1
            WHERE l1.from_document_id = so.id
              AND l1.link_type = 'converted_from'
              AND l1.deleted_at_utc IS NULL
            UNION
            SELECT l2.to_document_id FROM doc_links l1
            JOIN doc_links l2 ON l2.from_document_id = l1.to_document_id
            WHERE l1.from_document_id = so.id
              AND l1.link_type = 'converted_from'
              AND l1.deleted_at_utc IS NULL
              AND l2.link_type = 'converted_from'
              AND l2.deleted_at_utc IS NULL)
      ), 0) AS taken,
      COALESCE((
        SELECT SUM(jl.credit_paisa - jl.debit_paisa)
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.system_key = 'customer_advances'
          AND jl.firm_id = so.firm_id AND jl.party_id = ?2
          AND jl.deleted_at_utc IS NULL
      ), 0) AS holding
    FROM documents so
    WHERE so.id = ?1
    ''',
    [orderId, partyId],
  );
  if (row == null) return (left: Money.zero, holding: Money.zero);
  final left = row.read<int>('paid') - row.read<int>('taken');
  final holding = row.read<int>('holding');
  return (
    left: Money.paisa(left > 0 ? left : 0),
    holding: Money.paisa(holding > 0 ? holding : 0),
  );
}
