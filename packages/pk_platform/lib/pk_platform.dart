/// Device-facing adapters for Bazaar Ledger.
///
/// Implements ports declared in `pk_domain`. Nothing here is Flutter — the
/// receipt renderer produces bytes and PDFs in pure Dart, so a receipt can be
/// asserted command by command in a headless test.
library;

export 'package:pdf/pdf.dart' show PdfPageFormat;

export 'src/receipt/escpos.dart';
export 'src/receipt/receipt_layout.dart';
export 'src/receipt/thermal_receipt_renderer.dart';
export 'src/storage/file_draft_store.dart';
