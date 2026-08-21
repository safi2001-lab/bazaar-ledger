import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../data/database/app_database.dart';
import '../../../services/tajir_dost_engine.dart';
import '../../../shared/providers/database_provider.dart';

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

class TajirDostNotifier extends StateNotifier<TajirDostSummaryState> {
  final Ref ref;

  TajirDostNotifier(this.ref)
      : super(TajirDostSummaryState(
          monthlyTurnover: 500000.0,
          monthlyElectricityWht: 2500.0,
          taxResult: TajirDostEngine.calculateMonthlyTax(
            monthlyTurnover: 500000.0,
            monthlyElectricityWht: 2500.0,
          ),
        ));

  Future<void> logElectricityBill({
    required double billAmount,
    required double whtAmount,
    String? consumerNumber,
  }) async {
    final db = ref.read(appDatabaseProvider);
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

final tajirDostControllerProvider =
    StateNotifierProvider<TajirDostNotifier, TajirDostSummaryState>((ref) {
  return TajirDostNotifier(ref);
});
