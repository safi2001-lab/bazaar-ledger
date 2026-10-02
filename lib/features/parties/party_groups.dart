import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'quick_party_sheet.dart' show refusalWords;

/// Customers in groups by area, route or kind, and a note about each that
/// the counter sees (M40): the reads and the small pieces the customer
/// screens, the picker and the payment sheet share.
///
/// Kept out of `providers.dart` so the khata's own list, which every screen
/// leans on, is not rebuilt around a feature that only some shops use.

/// Every group the shop uses, A to Z, with its members and its money.
final partyGroupsProvider = FutureProvider.autoDispose<List<PartyGroupSummary>>(
  (ref) async {
    ref.watch(refreshTickProvider);
    final services = ref.watch(appServicesProvider);
    final firm = await ref.watch(firmProvider.future);
    if (firm == null) return const [];
    return services.queries.partyGroups(firm.id);
  },
);

/// The khata list, narrowed and ordered. Keyed by the whole filter, which
/// is a value, so a search, a group and a sort are one read.
final partyListProvider = FutureProvider.autoDispose
    .family<List<PartySummary>, PartyListFilter>((ref, filter) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.partyList(
        firm.id,
        filter: filter,
        limit: partyListLimit,
      );
    });

/// How many names the list reads before it asks for a search instead.
///
/// The list used to stop at forty without saying so, and a wholesaler's
/// khata has hundreds. Sorted by balance or by age, the first few hundred are
/// the ones that matter, and the screen says when there are more.
const partyListLimit = 300;

/// What the counter is told about one customer, or null.
///
/// Read through `partyById`, the one place a customer's figures are read
/// from, so the note can never belong to a different row than the balance
/// the payment sheet checks the credit limit against.
final partyRemarksProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, partyId) async {
    ref.watch(refreshTickProvider);
    final services = ref.watch(appServicesProvider);
    final firm = await ref.watch(firmProvider.future);
    if (firm == null) return null;
    return (await services.queries.partyById(firm.id, partyId))?.remarks;
  },
);

/// A group field: typed freely, or picked from the groups the shop already
/// uses, which sit under it as chips narrowed by what has been typed.
///
/// Chips rather than a drop-down. A drop-down hides the choices until a
/// field is focused and its list scrolls inside the keyboard; a shopkeeper
/// who files forty customers under five routes wants the five routes in
/// front of him, one tap each, and typing only for the sixth.
class PartyGroupField extends ConsumerStatefulWidget {
  const PartyGroupField({
    super.key,
    required this.controller,
    this.textInputAction = TextInputAction.next,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final TextInputAction textInputAction;
  final bool autofocus;

  @override
  ConsumerState<PartyGroupField> createState() => _PartyGroupFieldState();
}

class _PartyGroupFieldState extends ConsumerState<PartyGroupField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_typed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_typed);
    super.dispose();
  }

  void _typed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final typed = (partyGroupName(widget.controller.text) ?? '').toLowerCase();
    final groups = ref.watch(partyGroupsProvider).valueOrNull ?? const [];
    // Everything when nothing is typed; otherwise what contains it, so
    // "gul" offers "Mohalla Gulberg" and "3" offers every route with a 3.
    final offered = [
      for (final g in groups)
        if (typed.isEmpty || g.name.toLowerCase().contains(typed)) g.name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlField(
          controller: widget.controller,
          label: s.partyGroup,
          hint: s.partyGroupHint,
          autofocus: widget.autofocus,
          textInputAction: widget.textInputAction,
          prefix: const Icon(Icons.workspaces_outline, size: 20),
        ),
        if (offered.isNotEmpty) ...[
          const SizedBox(height: BlTokens.space2),
          GroupChipRow(
            children: [
              for (final name in offered)
                ChoiceChip(
                  selected: name.toLowerCase() == typed,
                  label: Text(name),
                  onSelected: (_) {
                    widget.controller
                      ..text = name
                      ..selection = TextSelection.collapsed(
                        offset: name.length,
                      );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A row of chips that scrolls sideways rather than wrapping, the sales
/// list's way: at 200% text a wrapped row of route names would take the
/// screen the list needs.
class GroupChipRow extends StatelessWidget {
  const GroupChipRow({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final chip in children)
            Padding(
              padding: const EdgeInsets.only(right: BlTokens.space2),
              child: chip,
            ),
        ],
      ),
    );
  }
}

/// A party's group, as a small label beside their phone number.
class GroupTag extends StatelessWidget {
  const GroupTag(this.group, {super.key});

  final String group;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BlTokens.space1 + 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BlTokens.radiusSm),
        border: Border.all(color: t.lineStrong),
      ),
      child: Text(
        group,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: t.inkMuted,
        ),
      ),
    );
  }
}

/// What the shop wrote about this customer, under their name on the payment
/// sheet (M40). Read-only here: it is changed from their details, by
/// whoever keeps the khata, never by the cashier it is a warning to.
///
/// "Sirf cash — cheque bounce ho chuka" written on a slip taped to the
/// counter is read by whoever stands there that afternoon. Written into the
/// app, it was read by nobody, because nothing showed it where the decision
/// to give credit is made. Zoho shows the customer's remarks under the
/// customer field while billing; this is that.
///
/// Draws nothing at all when there is no note, so a customer without one
/// leaves the sheet exactly as it was.
class PartyRemarksLine extends ConsumerWidget {
  const PartyRemarksLine({super.key, required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remarks = ref.watch(partyRemarksProvider(partyId)).valueOrNull;
    if (remarks == null || remarks.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: Semantics(
        label: s.partyRemarks,
        container: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BlTokens.space3,
            vertical: BlTokens.space2,
          ),
          decoration: BoxDecoration(
            color: t.warningSurface,
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 18,
                  color: t.warning,
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(
                  remarks.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puts several customers in one group at once, or takes them out of
/// theirs. Returns true when anything moved.
///
/// Through `catalogue.setPartyGroup`: one transaction, each customer its own
/// update in the outbox.
Future<bool> showSetGroupSheet(
  BuildContext context, {
  required List<String> partyIds,
  String? current,
}) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SetGroupSheet(partyIds: partyIds, current: current),
  );
  return moved ?? false;
}

class _SetGroupSheet extends ConsumerStatefulWidget {
  const _SetGroupSheet({required this.partyIds, this.current});

  final List<String> partyIds;
  final String? current;

  @override
  ConsumerState<_SetGroupSheet> createState() => _SetGroupSheetState();
}

class _SetGroupSheetState extends ConsumerState<_SetGroupSheet> {
  late final TextEditingController _group = TextEditingController(
    text: widget.current ?? '',
  );
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  Future<void> _save({required bool clear}) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final group = clear ? null : partyGroupName(_group.text);
    if (!clear && group == null) {
      setState(() => _failure = s.commonRequired);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final moved = await services.catalogue.setPartyGroup(
        services.actorNow(),
        widget.partyIds,
        group,
      );
      container.bumpRefresh();
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            group == null ? s.groupCleared(moved) : s.groupMoved(moved, group),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = refusalWords(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.groupSetFor(widget.partyIds.length),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              BlIconButton(
                icon: Icons.close,
                label: s.actionClose,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          PartyGroupField(
            controller: _group,
            autofocus: true,
            textInputAction: TextInputAction.done,
          ),
          if (_failure != null) ...[
            const SizedBox(height: BlTokens.space3),
            Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: BlTokens.space5),
          BlButton(
            label: s.groupSet,
            icon: Icons.check,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save(clear: false)),
          ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.groupClear,
            kind: BlButtonKind.ghost,
            onPressed: _busy ? null : () => unawaited(_save(clear: true)),
          ),
        ],
      ),
    );
  }
}
