import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/quick_party_sheet.dart' show refusalWords;
import 'reminder_queue.dart';
import 'send_reminder.dart';

/// One customer's reminder, ready: their message in their language.
final _readyProvider = FutureProvider.autoDispose
    .family<ReminderReady?, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).udhaar.reminderFor(partyId);
    });

/// Forty reminders in an evening, one at a time (M39).
///
/// Each customer in the round comes up with their message already written
/// in the language the khata keeps for them. One tap opens their WhatsApp
/// chat (or the phone's messages) with it typed; the shopkeeper presses Send
/// there and comes back to say so — "Sent", which goes in the khata's log
/// with who sent it and how — or to skip them, or to come back to them at
/// the end. The round is saved after every step, so a phone that kills the
/// app while WhatsApp is open picks up at the next name.
class ReminderRoundScreen extends ConsumerStatefulWidget {
  const ReminderRoundScreen({super.key, required this.round});

  final ReminderRound round;

  @override
  ConsumerState<ReminderRoundScreen> createState() =>
      _ReminderRoundScreenState();
}

class _ReminderRoundScreenState extends ConsumerState<ReminderRoundScreen> {
  late final ReminderRound _round = widget.round;

  /// How the current customer's message last left the phone, if it did.
  ReminderChannel? _opened;
  bool _busy = false;
  String? _failure;

  DraftStore get _drafts => ref.read(appServicesProvider).drafts;

  Future<void> _open(ReminderReady ready) async {
    final s = AppStrings.of(context);
    final outcome = await sendReminder(
      message: ready.message,
      party: ready.party,
      channel: _round.channel,
    );
    if (!mounted) return;
    setState(() => _opened = channelOf(outcome) ?? ReminderChannel.share);
    if (outcome == ReminderOutcome.noNumber) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.khataRemindNoPhone)));
    }
  }

  /// Marks the current customer [status] and moves on, saving the round.
  Future<void> _mark(RoundStatus status, ReminderReady? ready) async {
    if (_busy) return;
    final index = _round.current;
    if (index == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      if (status == RoundStatus.sent && ready != null) {
        // Into the khata's log the moment the shopkeeper says it went:
        // who, when, how, and in which language.
        await services.udhaar.recordReminderSent(
          ready.party.id,
          channel: _opened ?? _round.channel,
          language: ready.prefs.language,
          amount: ready.party.balance,
        );
        container.bumpRefresh();
      }
      _round.items[index].status = status;
      await _round.save(_drafts);
      if (!mounted) return;
      setState(() {
        _opened = null;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = refusalWords(error);
      });
    }
  }

  /// Sends the current customer to the end of the round, still waiting.
  Future<void> _later() async {
    final index = _round.current;
    if (index == null || _round.left < 2) return;
    final item = _round.items.removeAt(index);
    _round.items.add(item);
    await _round.save(_drafts);
    if (mounted) setState(() => _opened = null);
  }

  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    await ReminderRound.clear(_drafts);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final index = _round.current;
    final total = _round.items.length;
    final done = total - _round.left;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.roundTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: total == 0 ? 1 : done / total,
                  ),
                ),
                const SizedBox(width: BlTokens.space3),
                Text(
                  '$done / $total',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            SegmentedButton<ReminderChannel>(
              segments: [
                ButtonSegment(
                  value: ReminderChannel.whatsapp,
                  label: Text(s.sendWhatsAppShort),
                  icon: const Icon(Icons.chat_outlined),
                ),
                ButtonSegment(
                  value: ReminderChannel.sms,
                  label: Text(s.roundChannelSms),
                  icon: const Icon(Icons.sms_outlined),
                ),
              ],
              selected: {_round.channel},
              onSelectionChanged: (v) {
                setState(() => _round.channel = v.first);
                unawaited(_round.save(_drafts));
              },
            ),
            const SizedBox(height: BlTokens.space4),
            if (index == null)
              _Done(round: _round, onFinish: () => unawaited(_finish()))
            else
              _Current(
                key: ValueKey(_round.items[index].partyId),
                item: _round.items[index],
                channel: _round.channel,
                opened: _opened,
                busy: _busy,
                failure: _failure,
                canLater: _round.left > 1,
                onOpen: (ready) => unawaited(_open(ready)),
                onSent: (ready) => unawaited(_mark(RoundStatus.sent, ready)),
                onSkip: () => unawaited(_mark(RoundStatus.skipped, null)),
                onLater: () => unawaited(_later()),
              ),
            const SizedBox(height: BlTokens.space5),
            for (final (i, item) in _round.items.indexed)
              _ItemLine(item: item, current: i == index),
          ],
        ),
      ),
    );
  }
}

/// The customer whose turn it is.
class _Current extends ConsumerWidget {
  const _Current({
    super.key,
    required this.item,
    required this.channel,
    required this.opened,
    required this.busy,
    required this.failure,
    required this.canLater,
    required this.onOpen,
    required this.onSent,
    required this.onSkip,
    required this.onLater,
  });

  final RoundItem item;
  final ReminderChannel channel;
  final ReminderChannel? opened;
  final bool busy;
  final String? failure;
  final bool canLater;
  final ValueChanged<ReminderReady> onOpen;
  final ValueChanged<ReminderReady> onSent;
  final VoidCallback onSkip;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final ready = ref.watch(_readyProvider(item.partyId));

    return BlCard(
      child: ready.when(
        loading: () => const BlSkeletonList(rows: 3),
        error: (error, _) =>
            BlError(title: s.commonSomethingWentWrong, message: '$error'),
        data: (r) {
          if (r == null) {
            // Gone from the khata, or nothing owed any more: nothing to send.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: BlTokens.space2),
                Text(
                  s.khataRemindNothingOwed,
                  style: TextStyle(fontSize: 14, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space3),
                BlButton(
                  label: s.roundSkip,
                  kind: BlButtonKind.secondary,
                  onPressed: busy ? null : onSkip,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                r.party.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BlMoney(r.party.balance, size: 16, withSymbol: true),
                  BlChip(reminderLanguageName(s, r.prefs.language)),
                  if (r.whatsappNumber == null) BlChip(s.roundNoNumber),
                ],
              ),
              const SizedBox(height: BlTokens.space3),
              Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  color: t.paper,
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                  border: Border.all(color: t.line),
                ),
                child: Text(
                  r.message,
                  textDirection: r.prefs.language == ReminderLanguage.urdu
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  style: TextStyle(fontSize: 14, color: t.ink),
                ),
              ),
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: channel == ReminderChannel.sms
                    ? s.roundOpenSms
                    : s.roundOpenWhatsApp,
                icon: channel == ReminderChannel.sms
                    ? Icons.sms_outlined
                    : Icons.chat_outlined,
                big: true,
                onPressed: busy ? null : () => onOpen(r),
              ),
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.roundSent,
                icon: Icons.check,
                kind: opened == null
                    ? BlButtonKind.secondary
                    : BlButtonKind.primary,
                busy: busy,
                onPressed: busy ? null : () => onSent(r),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  BlButton(
                    label: s.roundSkip,
                    kind: BlButtonKind.ghost,
                    onPressed: busy ? null : onSkip,
                  ),
                  if (canLater)
                    BlButton(
                      label: s.roundLater,
                      kind: BlButtonKind.ghost,
                      onPressed: busy ? null : onLater,
                    ),
                ],
              ),
              if (failure != null) ...[
                const SizedBox(height: BlTokens.space2),
                Text(failure!, style: TextStyle(color: t.danger, fontSize: 13)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.round, required this.onFinish});

  final ReminderRound round;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.task_alt, size: 36, color: t.money),
          const SizedBox(height: BlTokens.space2),
          Text(
            s.roundDone(round.sent, round.skipped),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          BlButton(label: s.roundFinish, big: true, onPressed: onFinish),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item, required this.current});

  final RoundItem item;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            switch (item.status) {
              RoundStatus.sent => Icons.check_circle,
              RoundStatus.skipped => Icons.remove_circle_outline,
              RoundStatus.waiting =>
                current ? Icons.arrow_right : Icons.radio_button_unchecked,
            },
            size: 18,
            color: switch (item.status) {
              RoundStatus.sent => t.money,
              RoundStatus.skipped => t.inkFaint,
              RoundStatus.waiting => current ? t.accent : t.inkMuted,
            },
          ),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                color: t.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A reminder language by its own name.
String reminderLanguageName(AppStrings s, ReminderLanguage language) =>
    switch (language) {
      ReminderLanguage.urdu => s.reminderLangUrdu,
      ReminderLanguage.romanUrdu => s.reminderLangRoman,
      ReminderLanguage.english => s.reminderLangEnglish,
    };
