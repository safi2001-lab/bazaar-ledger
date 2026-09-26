/// Schema, migrations and the single transactional write path for
/// Bazaar Ledger.
///
/// The schema itself lives in `lib/src/db/tables/*.drift`. Those SQL files are
/// the source of truth; the Dart in this package is generated from them or
/// written against them, never the other way round.
library;

export 'package:drift/drift.dart' show QueryExecutor, QueryRow, Value, Variable;

export 'src/db/app_database.dart';
export 'src/read/drift_app_queries.dart';
export 'src/write/document_series.dart';
export 'src/write/drift_attachments.dart';
export 'src/write/drift_catalogue_writer.dart';
export 'src/write/drift_expense_writer.dart';
export 'src/write/drift_payment_writer.dart';
export 'src/write/drift_printer_settings.dart';
export 'src/write/drift_purchase_return_writer.dart'
    show DriftPurchaseReturnWriter;
export 'src/write/drift_purchase_writer.dart';
export 'src/write/drift_return_writer.dart';
export 'src/write/drift_sale_writer.dart';
export 'src/write/drift_void_writer.dart';
export 'src/write/first_run.dart';
export 'src/write/sequence_allocator.dart';
export 'src/write/tx_runner.dart';
