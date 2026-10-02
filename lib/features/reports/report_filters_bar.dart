import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_picker.dart';

/// The filters a report accepts, as chips under its period (M33).
///
/// A filter that is set reads as what it is set to, "Party: Rashid
/// Traders", with a cross to clear it, so a narrowed report can never be
/// mistaken on screen for the whole shop; one that is not set is a quiet
/// chip that opens its picker.
class ReportFiltersBar extends StatelessWidget {
  const ReportFiltersBar({
    required this.accepted,
    required this.filters,
    required this.onChanged,
    super.key,
  });

  final Set<ReportFilter> accepted;
  final ReportFilters filters;
  final ValueChanged<ReportFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space1,
      children: [
        for (final f in ReportFilter.values)
          if (accepted.contains(f)) _chip(context, s, f),
      ],
    );
  }

  Widget _chip(BuildContext context, AppStrings s, ReportFilter f) {
    if (f == ReportFilter.withBalance) {
      return FilterChip(
        selected: filters.withBalanceOnly,
        label: Text(s.reportFilterWithBalance),
        onSelected: (on) => onChanged(
          on
              ? filters.copyWith(withBalanceOnly: true)
              : filters.without(ReportFilter.withBalance),
        ),
      );
    }
    final value = filterValueLabel(s, f, filters);
    final name = reportFilterName(s, f);
    if (value == null) {
      return ActionChip(
        avatar: const Icon(Icons.filter_list, size: 16),
        label: Text(name),
        onPressed: () => unawaited(_pick(context, f)),
      );
    }
    return InputChip(
      label: Text('$name: $value'),
      selected: true,
      showCheckmark: false,
      onPressed: () => unawaited(_pick(context, f)),
      onDeleted: () => onChanged(filters.without(f)),
      deleteButtonTooltipMessage: s.reportFilterClear,
    );
  }

  Future<void> _pick(BuildContext context, ReportFilter f) async {
    final s = AppStrings.of(context);
    switch (f) {
      case ReportFilter.party:
        final party = await showModalBottomSheet<PartySummary>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const PartyPicker(),
        );
        if (party != null) {
          onChanged(filters.copyWith(partyId: party.id, partyName: party.name));
        }
      case ReportFilter.transactionType:
        final type = await _pickFixed(context, reportFilterName(s, f), [
          for (final t in TransactionType.all) (t, transactionTypeLabel(s, t)),
        ]);
        if (type != null) onChanged(filters.copyWith(transactionType: type));
      case ReportFilter.paymentMode:
        final mode = await _pickFixed(context, reportFilterName(s, f), [
          for (final m in PaymentMode.all) (m, paymentModeLabel(s, m)),
        ]);
        if (mode != null) onChanged(filters.copyWith(paymentMode: mode));
      case ReportFilter.paymentStatus:
        final status = await _pickFixed(context, reportFilterName(s, f), [
          for (final p in PaymentStatus.values) (p, paymentStatusName(s, p)),
        ]);
        if (status != null) onChanged(filters.copyWith(paymentStatus: status));
      case ReportFilter.item ||
          ReportFilter.itemCategory ||
          ReportFilter.partyGroup ||
          ReportFilter.user:
        final choice = await showModalBottomSheet<ReportChoice>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _ChoiceSheet(filter: f),
        );
        if (choice == null) return;
        onChanged(switch (f) {
          ReportFilter.item => filters.copyWith(
            itemId: choice.id,
            itemName: choice.label,
          ),
          ReportFilter.itemCategory => filters.copyWith(category: choice.id),
          ReportFilter.partyGroup => filters.copyWith(partyGroup: choice.id),
          _ => filters.copyWith(userId: choice.id, userName: choice.label),
        });
      case ReportFilter.withBalance:
        break;
    }
  }

  static Future<T?> _pickFixed<T>(
    BuildContext context,
    String title,
    List<(T, String)> options,
  ) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            BlSectionHeader(title),
            for (final (value, label) in options)
              ListTile(
                title: Text(label),
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Picks an item, a category, a party group or a member of staff from what
/// the shop has, searched as it is typed.
class _ChoiceSheet extends ConsumerStatefulWidget {
  const _ChoiceSheet({required this.filter});

  final ReportFilter filter;

  @override
  ConsumerState<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends ConsumerState<_ChoiceSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  late Future<List<ReportChoice>> _choices = _load('');

  Future<List<ReportChoice>> _load(String query) async {
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    if (firm == null) return const [];
    return services.reports.choices(firm.id, widget.filter, query: query);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _choices = _load(value.trim()));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BlSectionHeader(reportFilterName(s, widget.filter)),
          BlField(
            controller: _search,
            label: s.actionSearch,
            onChanged: _onChanged,
            prefix: const Icon(Icons.search, size: 20),
          ),
          const SizedBox(height: BlTokens.space3),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: FutureBuilder<List<ReportChoice>>(
              future: _choices,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return BlError(
                    title: s.commonSomethingWentWrong,
                    message: '${snapshot.error}',
                  );
                }
                final rows = snapshot.data;
                if (rows == null) return const BlSkeletonList(rows: 3);
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(BlTokens.space4),
                    child: Text(
                      s.reportFilterNothing,
                      style: TextStyle(color: t.inkMuted),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final c = rows[i];
                    return ListTile(
                      title: Text(
                        c.id == ReportFilters.ungrouped
                            ? s.reportFilterUngrouped
                            : c.label,
                      ),
                      subtitle: c.detail == null ? null : Text(c.detail!),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: BlTokens.space4),
        ],
      ),
    );
  }
}

/// A filter's name, as its chip reads.
String reportFilterName(AppStrings s, ReportFilter f) => switch (f) {
  ReportFilter.party => s.reportFilterParty,
  ReportFilter.item => s.reportFilterItem,
  ReportFilter.itemCategory => s.reportFilterCategory,
  ReportFilter.partyGroup => s.reportFilterGroup,
  ReportFilter.transactionType => s.reportFilterType,
  ReportFilter.paymentMode => s.reportFilterMode,
  ReportFilter.user => s.reportFilterUser,
  ReportFilter.paymentStatus => s.reportFilterStatus,
  ReportFilter.withBalance => s.reportFilterWithBalance,
};

/// What [f] is set to in [filters], in words, or null when it is not set.
String? filterValueLabel(AppStrings s, ReportFilter f, ReportFilters filters) =>
    switch (f) {
      ReportFilter.party =>
        filters.partyId == null ? null : filters.partyName ?? filters.partyId,
      ReportFilter.item =>
        filters.itemId == null ? null : filters.itemName ?? filters.itemId,
      ReportFilter.itemCategory => filters.category,
      ReportFilter.partyGroup =>
        filters.partyGroup == ReportFilters.ungrouped
            ? s.reportFilterUngrouped
            : filters.partyGroup,
      ReportFilter.transactionType =>
        filters.transactionType == null
            ? null
            : transactionTypeLabel(s, filters.transactionType!),
      ReportFilter.paymentMode =>
        filters.paymentMode == null
            ? null
            : paymentModeLabel(s, filters.paymentMode!),
      ReportFilter.user =>
        filters.userId == null ? null : filters.userName ?? filters.userId,
      ReportFilter.paymentStatus =>
        filters.paymentStatus == null
            ? null
            : paymentStatusName(s, filters.paymentStatus!),
      ReportFilter.withBalance => null,
    };

String transactionTypeLabel(AppStrings s, String type) => switch (type) {
  TransactionType.sale => s.reportTypeSale,
  TransactionType.saleReturn => s.reportTypeSaleReturn,
  TransactionType.purchase => s.reportTypePurchase,
  TransactionType.purchaseReturn => s.reportTypePurchaseReturn,
  TransactionType.expense => s.reportTypeExpense,
  TransactionType.charge => s.reportTypeCharge,
  TransactionType.quotation => s.reportTypeQuotation,
  TransactionType.challan => s.reportTypeChallan,
  TransactionType.saleOrder => s.reportTypeSaleOrder,
  TransactionType.purchaseOrder => s.reportTypePurchaseOrder,
  TransactionType.proforma => s.reportTypeProforma,
  TransactionType.paymentIn => s.reportTypePaymentIn,
  TransactionType.paymentOut => s.reportTypePaymentOut,
  _ => type,
};

String paymentModeLabel(AppStrings s, String mode) => switch (mode) {
  'cash' => s.tenderModeCash,
  'bank_transfer' => s.tenderModeBank,
  'jazzcash' => s.tenderModeJazzCash,
  'easypaisa' => s.tenderModeEasypaisa,
  'raast' => s.tenderModeRaast,
  'card' => s.tenderModeCard,
  'cheque' => s.tenderModeCheque,
  _ => mode,
};

String paymentStatusName(AppStrings s, PaymentStatus status) =>
    switch (status) {
      PaymentStatus.paid => s.reportStatusPaid,
      PaymentStatus.partial => s.reportStatusPartial,
      PaymentStatus.unpaid => s.reportStatusUnpaid,
    };
