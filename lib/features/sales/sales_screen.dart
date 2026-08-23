import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'receipt_screen.dart';

/// Every bill that was made, newest first.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final sales = ref.watch(recentSalesProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.salesTitle)),
      body: SafeArea(
        child: sales.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(recentSalesProvider),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: BlEmpty(
                  title: s.salesEmpty,
                  message: s.salesEmptyHint,
                  icon: Icons.receipt_long_outlined,
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.bumpRefresh(),
              child: ListView.builder(
                padding: const EdgeInsets.all(BlTokens.space4),
                itemCount: rows.length,
                itemBuilder: (context, i) => SaleRowTile(row: rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One bill in a list. Shared by the sales list and the home screen so the two
/// can never drift apart.
class SaleRowTile extends StatelessWidget {
  const SaleRowTile({super.key, required this.row});

  final SaleListRow row;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space4,
          vertical: BlTokens.space3,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReceiptScreen(documentId: row.id, docNo: row.docNo),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.docNo,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: row.isVoid ? t.inkFaint : t.ink,
                            decoration: row.isVoid
                                ? TextDecoration.lineThrough
                                : null,
                            fontFeatures: BlTokens.tabular,
                          ),
                        ),
                      ),
                      if (row.isVoid) ...[
                        const SizedBox(width: BlTokens.space2),
                        BlChip(s.salesVoided, tone: BlChipTone.bad),
                      ],
                    ],
                  ),
                  const SizedBox(height: BlTokens.space1),
                  Text(
                    '${row.partyName ?? s.posWalkInCustomer} · '
                    '${row.timeLabel} · ${s.posItemsInCart(row.lineCount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BlMoney(row.total, size: 17, semanticPrefix: row.docNo),
                const SizedBox(height: BlTokens.space1),
                if (row.isPaid)
                  BlChip(s.salesPaid, tone: BlChipTone.good)
                else
                  BlChip(
                    s.salesUdhaar(row.balance.amountOnly),
                    tone: BlChipTone.warn,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
