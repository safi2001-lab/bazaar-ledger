import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../users/pin_field.dart';

/// Puts the PIN prompt up whenever the books ask for one (M42).
///
/// The locks are kept by the write path, which refuses in words and has no
/// screen of its own. This is the one place the app answers it: while the
/// counter is open, the write path's question comes here, a prompt goes up
/// over whatever screen asked — the cancel sheet, the receipt, the khata —
/// and the write is tried again once a PIN is given. No screen that cancels
/// or posts anything has to know a lock exists, which is the point: a
/// screen written next year is guarded the day it is written.
class ApprovalKeeper extends ConsumerStatefulWidget {
  const ApprovalKeeper({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ApprovalKeeper> createState() => _ApprovalKeeperState();
}

class _ApprovalKeeperState extends ConsumerState<ApprovalKeeper> {
  late final AuditServices _audit = ref.read(appServicesProvider).audit;

  @override
  void initState() {
    super.initState();
    _audit.prompt = _ask;
  }

  @override
  void dispose() {
    if (_audit.prompt == _ask) _audit.prompt = null;
    super.dispose();
  }

  Future<ApprovalAnswer?> _ask(ApprovalAsk ask) async {
    if (!mounted) return null;
    return showApprovalPrompt(context, ask);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks for a PIN, and a reason when closed books are being opened for one
/// entry. Returns what was typed, or null when the person backed out.
Future<ApprovalAnswer?> showApprovalPrompt(
  BuildContext context,
  ApprovalAsk ask,
) => showDialog<ApprovalAnswer>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ApprovalDialog(ask: ask),
);

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.ask});

  final ApprovalAsk ask;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  final _pin = TextEditingController();
  final _reason = TextEditingController();
  late String _who = _firstChoice();

  /// The person doing it, when their own PIN will do; otherwise the owner.
  String _firstChoice() {
    final ask = widget.ask;
    final own = ask.people
        .where((m) => m.id == ask.needed.actorUserId)
        .firstOrNull;
    return (own ?? ask.people.first).id;
  }

  @override
  void dispose() {
    _pin.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _allow() => Navigator.of(
    context,
  ).pop(ApprovalAnswer(userId: _who, pin: _pin.text, reason: _reason.text));

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final ask = widget.ask;
    final needed = ask.needed;
    final closed = needed.kind == ApprovalKind.closedBooks;
    final chosen = ask.people.where((m) => m.id == _who).firstOrNull;
    final problem = switch (ask.problem) {
      ApprovalProblem.wrongPin => s.approvalWrongPin,
      ApprovalProblem.tooManyTries => s.approvalTooMany,
      ApprovalProblem.reasonNeeded => s.approvalReasonNeeded,
      ApprovalProblem.noPin => s.approvalNoPin,
      null => null,
    };

    return AlertDialog(
      backgroundColor: t.surface,
      title: Row(
        children: [
          Icon(Icons.lock_outline, color: t.warning),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Text(closed ? s.approvalClosedTitle : s.approvalLockTitle),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              closed
                  ? s.approvalClosedBody(
                      needed.closedThrough ?? '',
                      needed.dateLocal ?? '',
                    )
                  : s.approvalLockBody,
              style: TextStyle(fontSize: 14, color: t.ink),
            ),
            const SizedBox(height: BlTokens.space2),
            // What exactly, as the books put it.
            Text(
              needed.what,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (ask.people.length > 1) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.approvalWho,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space1),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final m in ask.people)
                    ChoiceChip(
                      selected: m.id == _who,
                      label: Text('${m.name} · ${roleName(s, m.role)}'),
                      onSelected: (_) => setState(() {
                        _who = m.id;
                        _pin.clear();
                      }),
                    ),
                ],
              ),
            ] else if (chosen != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                '${chosen.name} · ${roleName(s, chosen.role)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ],
            if (chosen?.hasPin ?? true) ...[
              const SizedBox(height: BlTokens.space2),
              PinField(
                controller: _pin,
                label: s.signInPin,
                autofocus: true,
                onSubmitted: (_) {
                  if (!closed) _allow();
                },
              ),
            ],
            if (closed) ...[
              const SizedBox(height: BlTokens.space2),
              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: s.approvalReason),
              ),
            ],
            if (problem != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(problem, style: TextStyle(fontSize: 13, color: t.danger)),
            ],
          ],
        ),
      ),
      actions: [
        BlButton(
          label: s.actionCancel,
          kind: BlButtonKind.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        BlButton(
          label: s.approvalAllow,
          icon: Icons.lock_open_outlined,
          onPressed: _allow,
        ),
      ],
    );
  }
}
