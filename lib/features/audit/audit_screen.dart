import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'history_screen.dart';
import 'when.dart';

final _activityProvider = FutureProvider.autoDispose
    .family<List<ActivityEntry>, String?>((ref, userId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.activity(firm.id, userId: userId);
    });

final _peopleProvider = FutureProvider.autoDispose<List<StaffMember>>((
  ref,
) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.staffStore.staff(firm.id);
});

/// Who did what, and when, newest first.
///
/// Every write since M0 has left a line in the audit log; this is the first
/// place anybody can read it. The owner asks it the questions a shop with
/// staff asks: who cancelled that bill, who signed in on Sunday, why the
/// drawer was short.
///
/// Since M42 a line about a bill, a payment, a customer or an item opens
/// that record's whole history: the log answers "who", the history "and
/// what else happened to it".
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String? _userId;

  static bool _opens(ActivityEntry e) =>
      e.entityTable != null &&
      e.entityId != null &&
      RecordRef.supports(e.entityTable!);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final people = ref.watch(_peopleProvider).valueOrNull ?? const [];
    final entries = ref.watch(_activityProvider(_userId));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.auditTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                ChoiceChip(
                  selected: _userId == null,
                  label: Text(s.auditEveryone),
                  onSelected: (_) => setState(() => _userId = null),
                ),
                for (final p in people)
                  ChoiceChip(
                    selected: _userId == p.id,
                    label: Text(p.name),
                    onSelected: (_) => setState(() => _userId = p.id),
                  ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            entries.when(
              loading: () => const BlSkeletonList(rows: 6),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) => rows.isEmpty
                  ? BlEmpty(icon: Icons.history, title: s.auditEmpty)
                  : Column(
                      children: [
                        for (final e in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: BlCard(
                              onTap: _opens(e)
                                  ? () => unawaited(
                                      openHistory(
                                        context,
                                        record: RecordRef(
                                          e.entityTable!,
                                          e.entityId!,
                                        ),
                                        label: e.summary ?? e.actionCode,
                                      ),
                                    )
                                  : null,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.summary ?? e.actionCode,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: t.ink,
                                          ),
                                        ),
                                        Text(
                                          '${e.userName} · '
                                          '${shopTime(e.atUtcMillis)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: t.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (e.amount case final amount?)
                                    BlMoney(amount, size: 14),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
