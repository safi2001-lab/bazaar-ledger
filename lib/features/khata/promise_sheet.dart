import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/quick_party_sheet.dart' show refusalWords;
import 'due_chip.dart';
import 'udhaar_providers.dart';

/// A customer's promise to pay, on their khata (M38).
///
/// "Friday ko de dunga" used to go on the inside cover of the register, or
/// nowhere. Here it is the line under what they owe: the day they said, how
/// much, whether it was kept — worked out from what came in, never ticked —
/// and the promises before it, broken ones included, because a customer who
/// has broken three is worth knowing about before the fourth.
class PromiseCard extends ConsumerWidget {
  const PromiseCard({super.key, required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final promises = ref.watch(promisesProvider(party.id)).valueOrNull;
    if (promises == null) return const SizedBox.shrink();
    final today = services.udhaar.today;
    final latest = promises.where((p) => !p.isWithdrawn).firstOrNull;
    final earlier = [
      for (final p in promises)
        if (p.id != latest?.id) p,
    ];
    // Nothing owed and nothing ever promised: nothing to say.
    if (latest == null && earlier.isEmpty && !party.balance.isPositive) {
      return const SizedBox.shrink();
    }
    final mayWrite = services.can(Permission.takePayments);
    final standing = latest?.standingOn(today);

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.handshake_outlined, size: 18, color: t.inkMuted),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(
                  s.promiseTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.inkMuted,
                  ),
                ),
              ),
              if (standing != null)
                BlChip(
                  promiseStandingText(s, standing),
                  tone: promiseTone(standing),
                ),
            ],
          ),
          const SizedBox(height: BlTokens.space2),
          if (latest == null)
            Text(
              s.promiseNone,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            )
          else ...[
            Text(
              promiseText(s, latest),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
            if (latest.note case final note? when note.isNotEmpty)
              Text('"$note"', style: TextStyle(fontSize: 13, color: t.ink)),
            Text(
              s.promiseBy(latest.madeBy, shortDate(latest.madeOn)),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
            if (latest.paidSince.isPositive && standing != PromiseStanding.kept)
              Text(
                s.promisePaidSince(latest.paidSince.amountOnly),
                style: TextStyle(fontSize: 12, color: t.money),
              ),
          ],
          if (mayWrite && party.balance.isPositive) ...[
            const SizedBox(height: BlTokens.space3),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                BlButton(
                  label: latest == null ? s.promiseRecord : s.promiseNew,
                  icon: Icons.event_available_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () =>
                      unawaited(showPromiseSheet(context, party: party)),
                ),
                if (latest != null && (standing?.isLive ?? false))
                  BlButton(
                    label: s.promiseWithdraw,
                    kind: BlButtonKind.ghost,
                    onPressed: () => unawaited(_withdraw(context, latest)),
                  ),
              ],
            ),
          ],
          if (earlier.isNotEmpty) ...[
            const Divider(height: BlTokens.space5),
            Text(
              s.promiseHistory,
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
            for (final p in earlier.take(5))
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        promiseText(s, p),
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                    BlChip(
                      promiseStandingText(s, p.standingOn(today)),
                      tone: promiseTone(p.standingOn(today)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, PaymentPromise promise) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container
          .read(appServicesProvider)
          .udhaar
          .withdrawPromise(promise.id);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.promiseWithdrawn)));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(refusalWords(error))));
    }
  }
}

/// Writes down what a customer said they would pay, and when.
Future<bool> showPromiseSheet(
  BuildContext context, {
  required PartySummary party,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PromiseSheet(party: party),
  );
  return saved ?? false;
}

class _PromiseSheet extends ConsumerStatefulWidget {
  const _PromiseSheet({required this.party});

  final PartySummary party;

  @override
  ConsumerState<_PromiseSheet> createState() => _PromiseSheetState();
}

class _PromiseSheetState extends ConsumerState<_PromiseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _day;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(String today) async {
    final from = BusinessDate(today);
    final first = DateTime(from.year, from.month, from.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: first.add(const Duration(days: 1)),
      firstDate: first,
      lastDate: first.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = BusinessDate.fromUtc(
        DateTime.utc(picked.year, picked.month, picked.day),
        Duration.zero,
      ).value;
      _failure = null;
    });
  }

  Future<void> _save() async {
    // Before any await: two taps in one frame both reach here.
    if (_busy) return;
    final s = AppStrings.of(context);
    final day = _day;
    if (day == null) {
      setState(() => _failure = s.promiseWhen);
      return;
    }
    final typed = _amount.text.trim().replaceAll(',', '');
    final amount = typed.isEmpty ? null : Money.tryParse(typed);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await services.udhaar.recordPromise(
        PromiseDraft(
          partyId: widget.party.id,
          promisedFor: day,
          amount: typed.isEmpty ? null : (amount ?? Money.zero),
          note: _note.text,
        ),
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.promiseSaved(shortDate(day)))),
      );
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = refusalWords(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = ref.watch(appServicesProvider).udhaar.today;
    final days = promiseDays(today);
    final offered = [
      // "Aaj shaam tak" is a promise too, and the one most often kept.
      (today, s.promiseToday),
      (days.tomorrow, s.promiseTomorrow),
      (days.friday, s.promiseFriday),
      (days.nextWeek, s.promiseNextWeek),
      (days.salaryDay, s.promiseSalaryDay),
    ];
    final chosen = _day;
    final picked = chosen != null && !offered.any((o) => o.$1 == chosen);

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.promiseTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              widget.party.name,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            Text(
              s.promiseWhen,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                for (final (day, label) in offered)
                  ChoiceChip(
                    selected: _day == day,
                    label: Text('$label · ${shortDate(day)}'),
                    onSelected: (_) => setState(() {
                      _day = day;
                      _failure = null;
                    }),
                  ),
                ChoiceChip(
                  selected: picked,
                  avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(picked ? shortDate(chosen) : s.promisePickDay),
                  onSelected: (_) => unawaited(_pick(today)),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space4),
            BlField(
              controller: _amount,
              label: s.promiseAmount,
              numeric: true,
              onChanged: (_) => setState(() => _failure = null),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _note, label: s.promiseNote),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.promiseSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
