import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// One bill, exactly as it will print.
///
/// The preview is the same 48-column layout the thermal printer receives, so
/// what a shopkeeper checks on screen is what comes out of the machine. No
/// printer is wired up in M0 — the transports land in M2 — so the two things
/// that work today are the ones that need no hardware: look at it, and send
/// the PDF.
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({
    super.key,
    required this.documentId,
    required this.docNo,
    this.autoPrint = false,
  });

  final String documentId;
  final String docNo;

  /// Set when the sale was saved with "Save aur Print". Until a printer
  /// transport exists this only opens the preview — it never claims to have
  /// printed something it did not print.
  final bool autoPrint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final receipt = ref.watch(receiptProvider(documentId));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.receiptTitle(docNo))),
      body: SafeArea(
        child: receipt.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 6),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(receiptProvider(documentId)),
            ),
          ),
          data: (data) {
            if (data == null) {
              return Center(child: BlEmpty(title: s.commonNothingSaved));
            }
            return Column(
              children: [
                Expanded(child: _Paper(data: data)),
                _Actions(data: data),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The 48-column layout, rendered on screen in a monospaced face.
///
/// Deliberately not a prettier "screen version" of the same bill. A separate
/// on-screen layout is a second implementation that drifts, and the first
/// anybody notices is when a customer's printed copy disagrees with what the
/// shopkeeper was shown.
class _Paper extends ConsumerWidget {
  const _Paper({required this.data});

  final ReceiptData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final text = services.receipts
        .toPreview(data, paper: ReceiptPaper.mm80)
        .join('\n');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(BlTokens.space4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BlTokens.space4,
            vertical: BlTokens.space5,
          ),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(BlTokens.radiusSm),
            border: Border.all(color: t.line),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier New', 'Roboto Mono'],
                fontSize: 12,
                height: 1.35,
                color: t.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.data});

  final ReceiptData data;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Future<void> _sharePdf() async {
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      final services = ref.read(appServicesProvider);
      final bytes = await services.receipts.toPdf(widget.data);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${widget.data.docNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: widget.data.docNo,
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.all(BlTokens.space4),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.print_disabled_outlined, size: 15, color: t.inkFaint),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: Text(
                    s.receiptNoPrinter,
                    style: TextStyle(fontSize: 12, color: t.inkFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.receiptSharePdf,
              icon: Icons.picture_as_pdf_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : _sharePdf,
            ),
          ],
        ),
      ),
    );
  }
}
