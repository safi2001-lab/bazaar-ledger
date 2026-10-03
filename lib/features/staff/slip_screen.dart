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
import '../orders/send_order.dart' show sendOrderText;
import '../printing/pdf_font.dart';
import 'employee_screen.dart' show askReason;
import 'salary_screen.dart';
import 'staff_providers.dart';

/// A month's slip (M65): how the wages were worked out and what was put in
/// the man's hand, to send him as a PDF or on WhatsApp, and to cancel or
/// put right.
///
/// The PDF is the report export's (M30), so a name written in Urdu script
/// comes out in the Urdu face the export carries, right to left, rather than
/// as empty boxes on his phone.
class SlipScreen extends ConsumerStatefulWidget {
  const SlipScreen({super.key, required this.slipId});

  final String slipId;

  @override
  ConsumerState<SlipScreen> createState() => _SlipScreenState();
}

class _SlipScreenState extends ConsumerState<SlipScreen> {
  bool _busy = false;

  Future<void> _sharePdf(SalarySlip slip) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final firm = await ref.read(firmProvider.future);
      final table = salarySlipTable(slip);
      final bytes = await reportToPdf(
        table,
        shopName: firm?.name ?? '',
        unicodeFont: await PdfUnicodeFont.bytes(),
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}${slip.slipNo}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: '${table.title}, ${slip.employeeName}',
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(staffError(s, error))));
    }
  }

  Future<void> _whatsApp(SalarySlip slip) async {
    final s = AppStrings.of(context);
    final firm = await ref.read(firmProvider.future);
    final text = s.staffSlipMessage(
      firm?.name ?? '',
      slip.employeeName,
      monthLabel(slip.month),
      slip.paidDaysText,
      slip.figures.gross.amountOnly,
      (slip.figures.deductions + slip.figures.recovered).amountOnly,
      slip.figures.net.amountOnly,
      slip.slipNo,
    );
    await sendOrderText(text, number: whatsappNumber(slip.employeePhone));
  }

  Future<void> _cancel(SalarySlip slip) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reason = await askReason(context, s.staffSlipCancelTitle);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final no = await ref
          .read(appServicesProvider)
          .staffBook
          .cancelSalary(slip.id, reason: reason);
      ref.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.staffSlipCancelDone(no))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(staffError(s, error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correct(SalarySlip slip) async {
    final navigator = Navigator.of(context);
    final man = await ref
        .read(appServicesProvider)
        .staffBook
        .employee(slip.employeeId);
    if (man == null) return;
    await navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            SalaryScreen(employee: man, month: slip.month, replacing: slip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final slip = ref.watch(slipProvider(widget.slipId)).valueOrNull;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(slip?.slipNo ?? s.staffSlips),
        actions: [
          if (slip != null)
            BlIconButton(
              icon: Icons.picture_as_pdf_outlined,
              label: s.staffSlipPdf,
              onPressed: () => unawaited(_sharePdf(slip)),
            ),
        ],
      ),
      body: SafeArea(
        child: slip == null
            ? const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              )
            : ListView(
                padding: const EdgeInsets.all(BlTokens.space4),
                children: [
                  if (slip.cancelled) ...[
                    BlChip(
                      s.staffSlipCancelledWhy(slip.voidReason ?? ''),
                      tone: BlChipTone.bad,
                    ),
                    if (slip.replacedBySlipNo case final no?)
                      Text(
                        s.staffSlipReplacedBy(no),
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                    const SizedBox(height: BlTokens.space3),
                  ],
                  BlCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${slip.employeeName} · ${monthLabel(slip.month)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                        Text(
                          payText(s, slip.basis, slip.rate),
                          style: TextStyle(fontSize: 13, color: t.inkMuted),
                        ),
                        Text(
                          s.staffSlipDays(
                            slip.paidDaysText,
                            slip.tally.employedDays,
                          ),
                          style: TextStyle(fontSize: 13, color: t.inkMuted),
                        ),
                        const Divider(),
                        _Line(
                          label: s.staffBasePay(slip.paidDaysText),
                          amount: slip.figures.basePay,
                        ),
                        for (final l in slip.lines)
                          _Line(
                            label: l.label,
                            amount: l.kind.adds ? l.amount : -l.amount,
                          ),
                        if (slip.figures.recovered.isPositive)
                          _Line(
                            label: s.staffRecoveredShort,
                            amount: -slip.figures.recovered,
                          ),
                        const Divider(),
                        _Line(
                          label: s.staffInHand,
                          amount: slip.figures.net,
                          strong: true,
                        ),
                        const SizedBox(height: BlTokens.space2),
                        Text(
                          s.staffSlipPaidOn(
                            slip.paidOn.value,
                            slip.paymentAccountName ?? '-',
                            slip.paidBy ?? '',
                          ),
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  BlButton(
                    label: s.staffSlipWhatsApp,
                    icon: Icons.chat_outlined,
                    kind: BlButtonKind.secondary,
                    expand: true,
                    onPressed: () => unawaited(_whatsApp(slip)),
                  ),
                  if (!slip.cancelled) ...[
                    const SizedBox(height: BlTokens.space3),
                    BlButton(
                      label: s.staffSlipCorrect,
                      icon: Icons.edit_note,
                      kind: BlButtonKind.secondary,
                      expand: true,
                      onPressed: () => unawaited(_correct(slip)),
                    ),
                    const SizedBox(height: BlTokens.space3),
                    BlButton(
                      label: s.staffSlipCancelTitle,
                      icon: Icons.undo,
                      kind: BlButtonKind.danger,
                      expand: true,
                      busy: _busy,
                      onPressed: () => unawaited(_cancel(slip)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.amount, this.strong = false});

  final String label;
  final Money amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 16 : 14,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: t.ink,
              ),
            ),
          ),
          BlMoney(amount, size: strong ? 18 : 14),
        ],
      ),
    );
  }
}
