import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../tax/tax_charge.dart';

/// What a posted sale left behind.
final class PostedSale {
  const PostedSale({
    required this.documentId,
    required this.docNo,
    required this.total,
    required this.paid,
    required this.balance,
    required this.change,
    required this.journalEntryId,
    required this.paymentIds,
  });

  final String documentId;
  final String docNo;
  final Money total;
  final Money paid;
  final Money balance;
  final Money change;
  final String journalEntryId;
  final List<String> paymentIds;
}

/// The persistence boundary for selling.
///
/// Defined here, in the domain, and implemented in `pk_data` against drift.
/// The use case above it never sees SQL, a companion, or a transaction object,
/// which is what lets it be tested against a fake in a few lines — and what
/// lets `lib/` depend on the application layer without ever being able to
/// reach the database.
abstract interface class SaleWriter {
  /// Runs [body] atomically. Everything it wrote is committed together or not
  /// at all.
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  );
}

/// The handle a sale is written through.
abstract interface class SaleWriteContext {
  ActorContext get actor;

  /// The seller's registration status and the buyer's ATL standing, which
  /// together decide what tax applies.
  Future<TaxContext> taxContextFor(String? partyId);

  /// Allocates the next number in a series for this device and fiscal year.
  ///
  /// Inside the transaction, so a sale that rolls back does not burn an
  /// invoice number. A gap in an invoice series is the first thing an auditor
  /// asks about.
  Future<AllocatedNumber> nextNumber(String docType);

  /// Weighted-average cost per base unit for each item, as it stands now.
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds);

  /// Maps each payment account to the account in the chart it posts to.
  Future<Map<String, String>> ledgerAccountsFor(
    Iterable<String> paymentAccountIds,
  );

  /// Writes the whole posting: document, lines, line taxes, payments,
  /// allocations, stock movements, journal entry and lines, audit and outbox.
  Future<PostedSale> apply(SalePosting posting);
}
