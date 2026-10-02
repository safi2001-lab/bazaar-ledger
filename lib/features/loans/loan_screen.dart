import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/pdf_font.dart';
import 'repay_loan_screen.dart';

/// How far back a loan's statement goes.
enum LoanSpan { all, thisMonth, lastMonth, thisYear }

final _loanProvider = FutureProvider.autoDispose.family<LoanView?, String>((
  ref,
  loanId,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  return services.loans.loan(loanId);
});

final _statementProvider = FutureProvider.autoDispose
    .family<LoanStatement, (String, LoanSpan)>((ref, key) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      return services.loans.statement(
        key.$1,
        period: periodFor(key.$2, BusinessDate.now(services.clock)),
      );
    });

/// The days [span] covers on [today]; null is from the day the loan was
/// taken.
ReportPeriod? periodFor(LoanSpan span, BusinessDate today) => switch (span) {
  LoanSpan.all => null,
  LoanSpan.thisMonth => ReportPeriod.monthOf(today),
  LoanSpan.lastMonth => ReportPeriod.monthBefore(today),
  LoanSpan.thisYear => ReportPeriod.fiscalYearOf(today),
};

/// One loan: what is still owed, every receipt and repayment with what came
/// off the loan and what was interest apart, and what was owed after each
/// (M48). Shared as a PDF or a CSV for the bank or the accountant; a line
/// entered wrong is cancelled from here, with a reason.
class LoanScreen extends ConsumerStatefulWidget {
  const LoanScreen({required this.loanId, super.key});

  final String loanId;

  @override
  ConsumerState<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends ConsumerState<LoanScreen> {
  LoanSpan _span = LoanSpan.all;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final loan = ref.watch(_loanProvider(widget.loanId)).valueOrNull;
    final statement = ref.watch(_statementProvider((widget.loanId, _span)));
    final mayWrite = services.can(Permission.journal);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(loan?.name ?? s.loansTitle),
        actions: [
          if (statement.valueOrNull case final st?) ...[
            BlIconButton(
              icon: Icons.picture_as_pdf_outlined,
              label: s.loanSharePdf,
              onPressed: () =>
                  unawaited(_share(context, st, loan?.terms, pdf: true)),
            ),
            BlIconButton(
              icon: Icons.table_view_outlined,
              label: s.loanShareCsv,
              onPressed: () =>
                  unawaited(_share(context, st, loan?.terms, pdf: false)),
            ),
          ],
        ],
      ),
      floatingActionButton: mayWrite && loan != null && !loan.cancelled
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RepayLoanScreen(loan: loan),
                ),
              ),
              icon: const Icon(Icons.payments_outlined),
              label: Text(s.loanRepay),
            )
          : null,
      body: SafeArea(
        child: statement.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 5),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (st) => ListView(
            padding: const EdgeInsets.fromLTRB(
              BlTokens.space4,
              BlTokens.space4,
              BlTokens.space4,
              BlTokens.space10 * 2,
            ),
            children: [
              if (loan != null) _Header(loan: loan),
              const SizedBox(height: BlTokens.space3),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final (span, label) in [
                    (LoanSpan.all, s.statementAll),
                    (LoanSpan.thisMonth, s.statementThisMonth),
                    (LoanSpan.lastMonth, s.statementLastMonth),
                    (LoanSpan.thisYear, s.statementThisYear),
                  ])
                    ChoiceChip(
                      selected: _span == span,
                      label: Text(label),
                      onSelected: (_) => setState(() => _span = span),
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space3),
              _Balance(label: s.loanOpening, date: st.from, amount: st.opening),
              const SizedBox(height: BlTokens.space2),
              for (final line in st.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space2),
                  child: _Line(
                    line: line,
                    onCancel:
                        mayWrite &&
                            line.kind != LoanLineKind.cancelled &&
                            !line.reversed
                        ? () => unawaited(_cancel(context, line))
                        : null,
                  ),
                ),
              _Totals(statement: st),
            ],
          ),
        ),
      ),
    );
  }

  /// Asks why, then cancels [line] by the opposite entry.
  Future<void> _cancel(BuildContext context, LoanStatementLine line) async {
    final s = AppStrings.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(entryNo: line.entryNo),
    );
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final no = await ref
          .read(appServicesProvider)
          .loans
          .cancel(loanId: widget.loanId, entryId: line.entryId, reason: reason);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.loanCancelDone(no))));
    } on LoanRefused catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.reason)));
    } on PermissionDenied catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.reason)));
    }
  }

  /// The statement as a PDF or a CSV, through the share sheet.
  Future<void> _share(
    BuildContext context,
    LoanStatement statement,
    LoanTerms? terms, {
    required bool pdf,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final table = loanStatementTable(statement, terms: terms);
      final firm = await ref.read(firmProvider.future);
      final bytes = pdf
          ? await reportToPdf(
              table,
              shopName: firm?.name ?? '',
              unicodeFont: await PdfUnicodeFont.bytes(),
            )
          : reportToCsvBytes(table);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${reportFileName(table, extension: pdf ? 'pdf' : 'csv')}',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: pdf ? 'application/pdf' : 'text/csv'),
          ],
          subject: '${table.title}, ${table.period.label}',
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.loan});

  final LoanView loan;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final terms = loan.terms;
    final rate = terms?.rateBp;
    final instalment = terms?.instalment;
    final notes = terms?.notes;
    return BlCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.loanOwed,
                  style: TextStyle(
                    fontSize: 14,
                    color: t.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loan.cancelled) BlChip(s.loanCancelled, tone: BlChipTone.bad),
            ],
          ),
          const SizedBox(height: BlTokens.space1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: BlMoney(
              loan.owed,
              size: 32,
              weight: FontWeight.w700,
              withSymbol: true,
              semanticPrefix: s.loanOwed,
            ),
          ),
          if (terms != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(
              [
                s.loanOf(terms.amount.amountOnly),
                s.loanTakenOn(terms.takenOn.value),
                if (rate != null) s.loanRateShown(formatBp(rate)),
                if (instalment != null)
                  s.loanInstalmentShown(instalment.amountOnly),
              ].join(' · '),
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (notes != null)
              Text(notes, style: TextStyle(fontSize: 13, color: t.ink)),
          ],
        ],
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.label,
    required this.date,
    required this.amount,
  });

  final String label;
  final BusinessDate date;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return BlCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label · ${date.value}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
          ),
          BlMoney(amount, size: 15),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line, this.onCancel});

  final LoanStatementLine line;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final kind = switch (line.kind) {
      LoanLineKind.received => s.loanKindReceived,
      LoanLineKind.repaid => s.loanKindRepaid,
      LoanLineKind.cancelled => s.loanKindCancelled,
    };
    final parts = [
      if (!line.borrowed.isZero) (s.loanColBorrowed, line.borrowed),
      if (!line.repaid.isZero) (s.loanColPrincipal, line.repaid),
      if (!line.interest.isZero) (s.loanColInterest, line.interest),
      if (!line.charges.isZero) (s.loanColCharges, line.charges),
    ];
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: line.reversed ? t.inkMuted : t.ink,
                      ),
                    ),
                    Text(
                      '${line.date.value} · ${line.entryNo}',
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                    // What was undone and why, as the books recorded it: a
                    // cancellation with no reason on screen is the line an
                    // accountant asks about.
                    if (line.kind == LoanLineKind.cancelled)
                      Text(
                        line.narration,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BlMoney(line.owedAfter, size: 15),
                  Text(
                    s.loanOwed,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                ],
              ),
            ],
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space3,
              runSpacing: BlTokens.space1,
              children: [
                for (final (label, amount) in parts)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$label ',
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                      BlMoney(amount, size: 13, weight: FontWeight.w500),
                    ],
                  ),
              ],
            ),
          ],
          if (line.reversed || onCancel != null) ...[
            const SizedBox(height: BlTokens.space1),
            Row(
              children: [
                if (line.reversed)
                  BlChip(s.loanCancelled, tone: BlChipTone.bad),
                const Spacer(),
                if (onCancel != null)
                  BlIconButton(
                    icon: Icons.undo,
                    label: s.loanCancelEntry,
                    onPressed: onCancel,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.statement});

  final LoanStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final st = statement;
    return BlCard(
      child: Column(
        children: [
          for (final (label, amount) in [
            (s.loanColBorrowed, st.borrowed),
            (s.loanColPrincipal, st.repaid),
            (s.loanColInterest, st.interest),
            (s.loanColCharges, st.charges),
          ])
            BlAmountRow(
              label: label,
              child: BlMoney(amount, size: 14, weight: FontWeight.w500),
            ),
          Divider(color: t.line),
          BlAmountRow(
            label: '${s.loanClosing} · ${st.to.value}',
            labelStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
            child: BlMoney(st.closing, size: 16, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.entryNo});

  final String entryNo;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text('${s.loanCancelEntry} · ${widget.entryNo}'),
      content: BlField(
        controller: _reason,
        label: s.loanCancelReason,
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        TextButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(s.loanCancelEntry),
        ),
      ],
    );
  }
}
