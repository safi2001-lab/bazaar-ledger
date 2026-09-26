/// The one wiring point for Bazaar Ledger.
///
/// Exports the ports the UI is written against, and the service object that
/// implements them. It does not export drift, `pk_data`, or anything that
/// would let a widget reach the database.
library;

export 'package:pk_application/pk_application.dart';
export 'package:pk_domain/pk_domain.dart';
export 'package:pk_platform/pk_platform.dart'
    show
        BackupArchive,
        BackupHeader,
        BackupProblem,
        BackupRefused,
        EscPos,
        EscPosAlign,
        EscPosFont,
        LabelData,
        LabelRenderer,
        LabelSpec,
        PdfPageFormat,
        PrintOutcome,
        PrintResult,
        ReceiptLayout,
        TcpPrinter,
        ThermalReceiptRenderer,
        isPrintableLatin;

export 'src/app_config.dart';
export 'src/app_services.dart';
export 'src/backup_service.dart';
export 'src/printing_services.dart';
