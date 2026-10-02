import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../documents/document_screen.dart';
import '../orders/order_list_screen.dart';
import '../sales/send_sheet.dart';
import 'purchase_screen.dart';
import 'send_back_sheet.dart';

/// Deliveries, newest first.
///
/// The Kharidari tile used to open a blank delivery form and nothing else, so
/// a delivery once saved could not be looked at again from anywhere in the
/// app. "Did the mill's Tuesday bill go in?" had no answer short of entering
/// it a second time — and a delivery entered twice is stock that is not on
/// the shelf and a cost average that has moved for nothing. The strings for
/// this list were in the ARB from the start; the list was not.
final recentPurchasesProvider =
    FutureProvider.autoDispose<List<PurchaseListRow>>((ref) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.recentPurchases(firm.id);
    });

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final purchases = ref.watch(recentPurchasesProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.purchasesTitle),
        actions: [
          // What has been asked for and not yet come (M41), one tap from
          // what has.
          BlIconButton(
            icon: Icons.assignment_outlined,
            label: s.ordersPurchase,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OrderListScreen(kind: OrderKind.purchase),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: purchases.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(BlTokens.space4),
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(recentPurchasesProvider),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlEmpty(
                    icon: Icons.local_shipping_outlined,
                    title: s.purchasesEmpty,
                    message: s.purchasesEmptyHint,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space2),
                    child: _PurchaseTile(row: rows[i]),
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PurchaseScreen())),
        icon: const Icon(Icons.add),
        label: Text(s.purchaseTitle),
      ),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.row});

  final PurchaseListRow row;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    // A tap opens the delivery itself, to be read and sent on (M30). It
    // used to open straight onto sending goods back, so a delivery could
    // be looked at only by starting to return it. Sending back is still one
    // tap from there: the only correction a delivery has, since it cannot
    // be voided once its cost has moved the average.
    return BlCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => DocumentScreen(
            documentId: row.id,
            docNo: row.docNo,
            showOwed: true,
            actions: [
              BlIconButton(
                icon: Icons.assignment_return_outlined,
                label: s.purchaseSendBack,
                onPressed: () => unawaited(
                  showSendBackSheet(
                    context,
                    documentId: row.id,
                    docNo: row.docNo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.supplierName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  // The supplier's own number first when there is one: it is
                  // the one printed on the paper in the shopkeeper's drawer.
                  [row.dateLocal, ?row.supplierBillNo, row.docNo].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                if (row.owed.isPositive) ...[
                  const SizedBox(height: BlTokens.space1),
                  BlChip(
                    s.partyWeOwe(row.owed.amountOnly),
                    tone: BlChipTone.warn,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          // Scaled down inside its share of the row, never cut, now that
          // the row also carries a send button.
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: BlMoney(row.total, size: 16),
            ),
          ),
          // Sent on from the list as a bill is (M30): to the supplier on
          // WhatsApp, or as a PDF or a picture for the accountant.
          BlIconButton(
            icon: Icons.share_outlined,
            label: s.sendAction,
            onPressed: () => unawaited(
              showSendSheet(context, documentId: row.id, docNo: row.docNo),
            ),
          ),
        ],
      ),
    );
  }
}
