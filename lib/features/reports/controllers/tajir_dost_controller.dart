import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/database/app_database.dart';
import '../../../services/tajir_dost_engine.dart';
import '../../../shared/providers/database_provider.dart';

part 'tajir_dost_controller.g.dart';

class TajirDostSummaryState {
  final double monthlyTurnover;
  final double monthlyElectricityWht;
  final TajirDostTaxResult taxResult;
  final bool isLoading;

  TajirDostSummaryState({
    required this.monthlyTurnover,
    required this.monthlyElectricityWht,
    required this.taxResult,
    this.isLoading = false,
  });

  TajirDostSummaryState copyWith({
    double? monthlyTurnover,
    double? monthlyElectricityWht,
    TajirDostTaxResult? taxResult,
    bool? isLoading,
  }) {
    return TajirDostSummaryState(
      monthlyTurnover: monthlyTurnover ?? this.monthlyTurnover,
      monthlyElectricityWht: monthlyElectricityWht ?? this.monthlyElectricityWht,
      taxResult: taxResult ?? this.taxResult,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

@riverpod
class TajirDostController extends _$TajirDostController {
  @override
  TajirDostSummaryState build() {
    final initialTurnover = 500000.0; // Rs 5 Lakh sample initial turnover
    final initialWht = 2500.0; // Rs 2,500 electricity bill advance tax
    final result = TajirDostEngine.calculateMonthlyTax(
      monthlyTurnover: initialTurnover,
      monthlyElectricityWht: initialWht,
    );

    return TajirDostSummaryState(
      monthlyTurnover: initialTurnover,
      monthlyElectricityWht: initialWht,
      taxResult: result,
    );
  }

  /// Log an electricity bill with advance withholding tax (Section 235)
  Future<void> logElectricityBill({
    required double billAmount,
    required double whtAmount,
    String? consumerNumber,
  }) async {
    final db = ref.watch(appDatabaseProvider);
    await db.into(db.expenses).insert(
      ExpensesCompanion.insert(
        companyId: 1,
        category: 'Electricity Bill',
        amount: billAmount,
        paymentMode: 'Bank',
        whtAdvanceTax: Value(whtAmount),
        notes: Value(consumerNumber != null ? 'Consumer #$consumerNumber' : null),
      ),
    );

    final updatedWht = state.monthlyElectricityWht + whtAmount;
    final updatedResult = TajirDostEngine.calculateMonthlyTax(
      monthlyTurnover: state.monthlyTurnover,
      monthlyElectricityWht: updatedWht,
    );

    state = state.copyWith(
      monthlyElectricityWht: updatedWht,
      taxResult: updatedResult,
    );
  }

  void updateTurnover(double turnover) {
    final result = TajirDostEngine.calculateMonthlyTax(
      monthlyTurnover: turnover,
      monthlyElectricityWht: state.monthlyElectricityWht,
    );
    state = state.copyWith(
      monthlyTurnover: turnover,
      taxResult: result,
    );
  }
}
