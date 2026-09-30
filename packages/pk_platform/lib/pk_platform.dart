/// Device-facing adapters for Bazaar Ledger.
///
/// Implements ports declared in `pk_domain`. Nothing here is Flutter — the
/// receipt renderer produces bytes and PDFs in pure Dart, so a receipt can be
/// asserted command by command in a headless test.
library;

export 'package:pdf/pdf.dart' show PdfPageFormat;
export 'src/backup/backup_archive.dart';
export 'src/backup/cloud_store.dart';
export 'src/cheques/demand_notice_pdf.dart';

export 'src/fbr/fbr_client.dart';
export 'src/media/image_shrinker.dart';
export 'src/printing/print_queue.dart';
export 'src/printing/tcp_printer.dart';
export 'src/receipt/escpos.dart';
export 'src/receipt/fbr_qr.dart';
export 'src/receipt/label_renderer.dart';
export 'src/receipt/printable.dart';
export 'src/receipt/receipt_layout.dart';
export 'src/receipt/thermal_receipt_renderer.dart';
export 'src/security/pin_hasher.dart';
export 'src/storage/file_draft_store.dart';
