/// Entities, ports and pure posting rules for Bazaar Ledger.
///
/// Nothing in this package knows about SQL, Flutter, files or the network.
/// Everything is deterministic given a [Clock] and an [IdGenerator], which is
/// why the posting rules can be tested exhaustively without a database.
library;

export 'package:pk_money/pk_money.dart';

export 'src/accounting/chart_of_accounts.dart';
export 'src/accounting/chart_view.dart';
export 'src/accounting/day_close.dart';
export 'src/accounting/journal_voucher.dart';
export 'src/barcode/gs1.dart';
export 'src/barcode/scale.dart';
export 'src/catalogue/barcode_key.dart';
export 'src/catalogue/unit_converter.dart';
export 'src/catalogue/units.dart';
export 'src/cheques/cheque_dates.dart';
export 'src/cheques/cheque_lifecycle.dart';
export 'src/cheques/demand_notice.dart';
export 'src/corrections/purchase_return_builder.dart';
export 'src/corrections/return_builder.dart';
export 'src/corrections/reversal.dart';
export 'src/costing/moving_average.dart';
export 'src/costing/purchase_builder.dart';
export 'src/costing/purchase_posting.dart';
export 'src/documents/debit_note.dart';
export 'src/documents/delivery_challan.dart';
export 'src/documents/quotation.dart';
export 'src/entitlement/activity.dart';
export 'src/entitlement/roles.dart';
export 'src/entitlement/staff.dart';
export 'src/identity/actor_context.dart';
export 'src/identity/ulid.dart';
export 'src/manufacturing/assembly.dart';
export 'src/ports/app_queries.dart';
export 'src/ports/attachments.dart';
export 'src/ports/catalogue_writer.dart';
export 'src/ports/challan_writer.dart';
export 'src/ports/cheque_writer.dart';
export 'src/ports/day_close_writer.dart';
export 'src/ports/debit_note_writer.dart';
export 'src/ports/draft_store.dart';
export 'src/ports/expense_writer.dart';
export 'src/ports/health.dart';
export 'src/ports/journal_writer.dart';
export 'src/ports/manufacturing.dart';
export 'src/ports/payment_writer.dart';
export 'src/ports/printer.dart';
export 'src/ports/printer_settings.dart';
export 'src/ports/purchase_return_writer.dart';
export 'src/ports/purchase_writer.dart';
export 'src/ports/quotation_writer.dart';
export 'src/ports/receipt.dart';
export 'src/ports/return_writer.dart';
export 'src/ports/sale_writer.dart';
export 'src/ports/vans.dart';
export 'src/ports/void_writer.dart';
export 'src/pricing/price_tier.dart';
export 'src/receivables/aging.dart';
export 'src/receivables/expense_builder.dart';
export 'src/receivables/fifo_allocator.dart';
export 'src/receivables/receipt_builder.dart';
export 'src/receivables/receipt_posting.dart';
export 'src/receivables/reminder.dart';
export 'src/receivables/supplier_payment_builder.dart';
export 'src/sales/sale_calculator.dart';
export 'src/sales/sale_draft.dart';
export 'src/sales/sale_posting.dart';
export 'src/sales/sale_posting_builder.dart';
export 'src/stock/lots.dart';
export 'src/tax/fbr/fbr_invoice.dart';
export 'src/tax/pack/pakistan_2026.dart';
export 'src/tax/tax_charge.dart';
export 'src/time/clock.dart';
export 'src/time/hlc.dart';
export 'src/vans/van_settlement.dart';
