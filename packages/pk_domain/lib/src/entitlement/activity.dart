import 'package:pk_money/pk_money.dart';

/// One line of the activity log: who did what, and when.
final class ActivityEntry {
  const ActivityEntry({
    required this.atUtcMillis,
    required this.userId,
    required this.userName,
    required this.actionCode,
    this.summary,
    this.amount,
    this.entityTable,
    this.entityId,
  });

  final int atUtcMillis;
  final String userId;
  final String userName;

  /// `SALE_POSTED`, `DOCUMENT_VOIDED`, `USER_SIGNED_IN`, `DAY_CLOSED`, ...
  final String actionCode;

  /// One line in English, written when it happened.
  final String? summary;
  final Money? amount;

  /// The record it was done to, so a line in the log opens that record's
  /// history (M42). Null on a line read without them.
  final String? entityTable;
  final String? entityId;
}
