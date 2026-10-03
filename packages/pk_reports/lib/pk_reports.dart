/// The reports engine for Bazaar Ledger.
///
/// Each report is a pure builder over rows a [ReportSource] reads, and every
/// figure on it is computed before the screen or an export sees it.
library;

import 'src/report_source.dart';

export 'src/builders.dart';
export 'src/business_builders.dart';
export 'src/business_reports.dart';
export 'src/business_source.dart';
export 'src/expense_builders.dart';
export 'src/expense_source.dart';
export 'src/filters.dart';
export 'src/item_stock_builders.dart';
export 'src/item_stock_source.dart';
export 'src/loan_reports.dart';
export 'src/money_owed_reports.dart';
export 'src/order_builders.dart';
export 'src/order_reports.dart';
export 'src/order_source.dart';
export 'src/party_builders.dart';
export 'src/party_source.dart';
export 'src/period.dart';
export 'src/pharmacy_reports.dart';
export 'src/report_chart.dart';
export 'src/report_engine.dart';
export 'src/report_source.dart';
export 'src/report_table.dart';
export 'src/saved_view.dart';
export 'src/staff_builders.dart';
export 'src/staff_source.dart';
export 'src/tax_builders.dart';
export 'src/tax_source.dart';
export 'src/transaction_builders.dart';
export 'src/transaction_source.dart';
export 'src/udhaar_reports.dart';
