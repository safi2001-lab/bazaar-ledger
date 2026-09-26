/// The reports engine for Bazaar Ledger.
///
/// Each report is a pure builder over rows a [ReportSource] reads, and every
/// figure on it is computed before the screen or an export sees it.
library;

import 'src/report_source.dart';

export 'src/builders.dart';
export 'src/period.dart';
export 'src/report_engine.dart';
export 'src/report_source.dart';
export 'src/report_table.dart';
