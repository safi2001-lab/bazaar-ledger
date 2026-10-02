import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../sales/receipt_screen.dart';
import '../sales/send_sheet.dart';

/// One document as the books have it now.
///
/// Watches the refresh tick, unlike the receipt's own read: a delivery shown
/// here and then sent back in part has to show what is still owed after the
/// return, not what was owed when the screen opened.
final documentPaperProvider = FutureProvider.autoDispose
    .family<ReceiptData?, String>((ref, documentId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return null;
      final paper = await services.queries.receiptFor(firm.id, documentId);
      final status = await services.queries.documentStatus(firm.id, documentId);
      // A challan cancelled when its goods came back shows it, as it is sent.
      return paper?.copyWith(isCancelled: status == 'void');
    });

/// A delivery, a quotation or a challan, opened from its list to be looked
/// at and sent again (M30).
///
/// Read-only, deliberately. A posted document is corrected by the document
/// that corrects it — a return to the supplier, a cancelled challan — and
/// never by editing it, so this screen shows the paper and the ways to send
/// it, and [actions] carries the correction the list it came from allows.
///
/// A delivery could not be opened at all before this: tapping it went
/// straight to sending goods back, so "what exactly did the mill send on
/// Tuesday" had no answer on the phone short of starting a return.
class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({
    super.key,
    required this.documentId,
    required this.docNo,
    this.actions = const [],
    this.showOwed = false,
  });

  final String documentId;
  final String docNo;

  /// A delivery shows what the shop still owes on it, in the words the
  /// purchases list uses.
  final bool showOwed;

  /// In the app bar, as the receipt screen keeps a bill's return and cancel:
  /// what may be done about this document. Up there rather than under the
  /// send buttons, where the SnackBar that says the document was saved sits
  /// for four seconds over exactly that spot.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final paper = ref.watch(documentPaperProvider(documentId));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(docNo), actions: actions),
      body: SafeArea(
        child: paper.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 6),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(documentPaperProvider(documentId)),
            ),
          ),
          data: (data) {
            if (data == null) {
              return Center(child: BlEmpty(title: s.commonNothingSaved));
            }
            return Column(
              children: [
                if (showOwed && data.balance.isPositive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BlTokens.space4,
                      BlTokens.space3,
                      BlTokens.space4,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BlChip(
                        s.partyWeOwe(data.balance.amountOnly),
                        tone: BlChipTone.warn,
                      ),
                    ),
                  ),
                Expanded(child: PaperPreview(data: data)),
                Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border(top: BorderSide(color: t.line)),
                  ),
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: SafeArea(
                    top: false,
                    child: SendButtons(documentId: documentId),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
