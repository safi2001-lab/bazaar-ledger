/// Entities, ports and pure posting rules for Bazaar Ledger.
///
/// Nothing in this package knows about SQL, Flutter, files or the network.
/// Everything is deterministic given a [Clock] and an [IdGenerator], which is
/// why the posting rules can be tested exhaustively without a database.
library;

export 'package:pk_money/pk_money.dart';

export 'src/accounting/chart_of_accounts.dart';
export 'src/catalogue/units.dart';
export 'src/identity/actor_context.dart';
export 'src/identity/ulid.dart';
export 'src/ports/app_queries.dart';
export 'src/ports/catalogue_writer.dart';
export 'src/ports/health.dart';
export 'src/ports/receipt.dart';
export 'src/ports/sale_writer.dart';
export 'src/sales/sale_calculator.dart';
export 'src/sales/sale_draft.dart';
export 'src/sales/sale_posting.dart';
export 'src/sales/sale_posting_builder.dart';
export 'src/tax/tax_charge.dart';
export 'src/time/clock.dart';
export 'src/time/hlc.dart';
