import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'new_sheet_screen.dart';
import 'sheet_screen.dart';

/// The shop's collection sheets, newest first (M55).
final collectionSheetsProvider =
    FutureProvider.autoDispose<List<CollectionSheet>>((ref) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).collections.sheets();
    });

/// The recovery man's rounds: the sheets out today and the ones he came
/// back with (M55).
///
/// Reached from the chase list, because a sheet is the chase list handed to
/// somebody with a bag: the same customers, by route or by how late, with
/// their bills, numbered so his paper and this screen name the same line.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final sheets = ref.watch(collectionSheetsProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.sheetsTitle)),
      body: SafeArea(
        child: sheets.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) => BlError(
            title: s.commonSomethingWentWrong,
            message: '$error',
            retryLabel: s.actionRetry,
            onRetry: () => ref.invalidate(collectionSheetsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? BlEmpty(
                  icon: Icons.assignment_ind_outlined,
                  title: s.sheetsEmpty,
                  message: s.sheetsEmptyHint,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space4,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  children: [
                    for (final sheet in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: _SheetTile(sheet: sheet),
                      ),
                  ],
                ),
        ),
      ),
      floatingActionButton: services.collections.mayMakeSheets
          ? FloatingActionButton.extended(
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NewSheetScreen(),
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(s.sheetNew),
            )
          : null,
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.sheet});

  final CollectionSheet sheet;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return BlCard(
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SheetScreen(sheetId: sheet.id),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sheet.sheetNo} · ${sheet.collector}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  [
                    shortDate(sheet.dateLocal),
                    s.sheetCustomers(sheet.lines.length),
                    ?sheet.title,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space1),
                BlChip(
                  sheet.isSettled ? s.sheetSettled : s.sheetOut,
                  tone: sheet.isSettled ? BlChipTone.good : BlChipTone.warn,
                ),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BlMoney(sheet.expected, size: 16),
              if (sheet.isSettled)
                BlMoney(sheet.collected, size: 13, colour: t.money),
            ],
          ),
        ],
      ),
    );
  }
}
