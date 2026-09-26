import 'package:pk_money/pk_money.dart';

import '../accounting/day_close.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';

/// The persistence boundary for closing the day.
abstract interface class DayCloseWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(DayCloseWriteContext write) body,
  );
}

/// The handle a day close is written through.
abstract interface class DayCloseWriteContext {
  ActorContext get actor;

  /// The cash the books say is in the drawer now.
  Future<Money> cashInBooks();

  Future<AllocatedNumber> nextNumber(String docType);

  /// Writes the adjustment, if there is one, and the audit row.
  Future<void> apply(DayClosePosting posting);
}
