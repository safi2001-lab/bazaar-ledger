/// Goods given rate-later, and the recovery man's round: the persistence
/// boundary of M55.
library;

import 'package:pk_money/pk_money.dart';

import '../collections/collection_sheet.dart';
import '../collections/goods_given.dart';
import '../identity/actor_context.dart';
import '../receivables/promise.dart';
import '../sales/sale_posting_builder.dart';
import 'payment_writer.dart';

/// A customer as a sheet line needs them, read inside the transaction.
final class SheetParty {
  const SheetParty({
    required this.id,
    required this.name,
    required this.balance,
    this.phone,
    this.group,
  });

  final String id;
  final String name;
  final String? phone;
  final String? group;

  /// The khata's own figure: opening balance and open bills, less what the
  /// shop holds for them.
  final Money balance;
}

/// One transaction in which a sheet is made, or a round's receipts, its
/// promises and the sheet closing are all written — or nothing is.
abstract interface class CollectionWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(CollectionWriteContext write) body,
  );
}

/// What the collection use case reads and writes inside its transaction.
abstract interface class CollectionWriteContext {
  ActorContext get actor;

  /// The payment handle on this same transaction: a round's money is taken
  /// by exactly the code that takes every receipt.
  PaymentWriteContext get payments;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The name of whoever is writing.
  Future<String> actorName();

  /// A customer as the khata has them now; null when not in this khata.
  Future<SheetParty?> party(String partyId);

  /// Lines of goods given [partyId] still waiting for a rate.
  Future<int> unpricedLines(String partyId);

  /// A sheet as it stands inside this transaction; null when there is none.
  Future<CollectionSheet?> sheet(String sheetId);

  /// Keeps a new sheet, audited, and returns its id.
  Future<String> addSheet(CollectionSheet sheet);

  /// Keeps [sheet] over what was kept, audited as [action].
  Future<void> putSheet(
    CollectionSheet sheet, {
    required String action,
    required String summary,
    Money? amount,
  });

  /// Writes a promise on [partyName]'s khata exactly as M38 keeps one, and
  /// returns its id.
  Future<String> addPromise(PromiseDraft draft, {required String partyName});
}

/// What the khata, the chase list and the sheets screen read.
abstract interface class CollectionQueries {
  /// Every challan to [partyId] not yet billed, oldest first, with its lines.
  Future<List<GoodsGiven>> goodsGivenTo(String firmId, String partyId);

  /// Every customer with goods given and no rate on them yet, oldest first.
  Future<List<UnpricedParty>> unpricedParties(String firmId);

  /// The shop's sheets, newest first.
  Future<List<CollectionSheet>> sheets(String firmId, {int limit = 100});

  /// One sheet; null when it is not this shop's.
  Future<CollectionSheet?> sheet(String firmId, String sheetId);
}
