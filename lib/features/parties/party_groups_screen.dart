import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/khata_screen.dart';
import 'parties_screen.dart';
import 'party_groups.dart';
import 'quick_party_sheet.dart' show refusalWords;

/// The shop's groups (M40): each with who is in it and what they owe and
/// are owed, one tap from its members, its new name, or another group to
/// fold it into.
///
/// There is no "new group" button, on purpose. A group is a name on its
/// members and exists exactly as long as somebody is in it; one is made by
/// typing it on a customer, or by picking several in the list and setting
/// theirs. An empty group with nobody in it is a chip that narrows the list
/// to nothing.
class PartyGroupsScreen extends ConsumerWidget {
  const PartyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final groups = ref.watch(partyGroupsProvider);
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.groupsTitle)),
      body: SafeArea(
        child: groups.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(partyGroupsProvider),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Center(
                  child: BlEmpty(
                    title: s.groupsEmpty,
                    message: s.groupsEmptyHint,
                    icon: Icons.workspaces_outline,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: BlTokens.space3),
                  itemBuilder: (context, i) => GroupTotalsCard(
                    key: ValueKey(rows[i].name),
                    group: rows[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PartyGroupScreen(name: rows[i].name),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// One group: its totals, its members, and renaming or merging it.
class PartyGroupScreen extends ConsumerStatefulWidget {
  const PartyGroupScreen({super.key, required this.name});

  final String name;

  @override
  ConsumerState<PartyGroupScreen> createState() => _PartyGroupScreenState();
}

class _PartyGroupScreenState extends ConsumerState<PartyGroupScreen> {
  /// The group's name now. It changes under the screen when the group is
  /// renamed or merged, and the screen follows its members.
  late String _name = widget.name;
  bool _busy = false;

  List<PartyGroupSummary> get _groups =>
      ref.read(partyGroupsProvider).valueOrNull ?? const [];

  /// The spelling [typed] will be kept under: another group's own when it
  /// is one in any case (and so a merge), or as typed, tidied.
  String? _keptAs(String typed) {
    final tidy = partyGroupName(typed);
    if (tidy == null) return null;
    for (final g in _groups) {
      if (g.name != _name && g.name.toLowerCase() == tidy.toLowerCase()) {
        return g.name;
      }
    }
    return tidy;
  }

  Future<void> _move(String to) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppStrings.of(context);
    final services = ref.read(appServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final target = _keptAs(to) ?? to;
    try {
      final moved = await services.catalogue.renamePartyGroup(
        services.actorNow(),
        from: _name,
        to: to,
      );
      container.bumpRefresh();
      if (mounted) setState(() => _name = target);
      messenger.showSnackBar(
        SnackBar(content: Text(s.groupMoved(moved, target))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(refusalWords(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final others = [
      for (final g in _groups)
        if (g.name != _name) g.name,
    ];
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(current: _name, others: others),
    );
    if (to == null || !mounted) return;
    final kept = _keptAs(to);
    if (kept == null || kept == _name) return;
    await _move(to);
  }

  Future<void> _merge() async {
    final s = AppStrings.of(context);
    final others = [
      for (final g in _groups)
        if (g.name != _name) g,
    ];
    if (others.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.groupNoOther)));
      return;
    }
    final into = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MergeSheet(others: others),
    );
    if (into == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.groupMerge),
        content: Text(s.groupMergeConfirm(_name, into)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.commonYes),
          ),
        ],
      ),
    );
    if ((yes ?? false) && mounted) await _move(into);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final groups = ref.watch(partyGroupsProvider).valueOrNull ?? const [];
    PartyGroupSummary? summary;
    for (final g in groups) {
      if (g.name == _name) summary = g;
    }
    final members = ref.watch(partyListProvider(PartyListFilter(group: _name)));
    final rowHeight = blRowExtent(context, 68);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(_name),
        actions: [
          BlIconButton(
            icon: Icons.drive_file_rename_outline,
            label: s.groupRename,
            onPressed: _busy ? null : () => unawaited(_rename()),
          ),
          BlIconButton(
            icon: Icons.call_merge,
            label: s.groupMerge,
            onPressed: _busy ? null : () => unawaited(_merge()),
          ),
        ],
      ),
      body: SafeArea(
        child: members.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(partyListProvider),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: BlEmpty(
                  title: s.groupNobody,
                  icon: Icons.workspaces_outline,
                ),
              );
            }
            // One scrolling list, header included: at 200% a fixed header
            // card would leave the members a sliver of the screen.
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                BlTokens.space4,
                BlTokens.space4,
                BlTokens.space4,
                BlTokens.space10,
              ),
              itemCount: rows.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return summary == null
                      ? const SizedBox.shrink()
                      : GroupTotalsCard(group: summary);
                }
                if (i == 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: BlTokens.space2),
                    child: Text(
                      s.groupMembersTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.inkMuted,
                      ),
                    ),
                  );
                }
                final party = rows[i - 2];
                return SizedBox(
                  height: rowHeight,
                  child: PartyRowTile(
                    key: ValueKey(party.id),
                    party: party,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => KhataScreen(party: party),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// A new name for a group, saying so before Save when the name is another
/// group's and the two will become one.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current, required this.others});

  final String current;
  final List<String> others;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _mergesInto {
    final typed = partyGroupName(_name.text)?.toLowerCase();
    if (typed == null) return null;
    for (final other in widget.others) {
      if (other.toLowerCase() == typed) return other;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final merges = _mergesInto;
    final blank = partyGroupName(_name.text) == null;
    return AlertDialog(
      title: Text(s.groupRename),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlField(
              controller: _name,
              label: s.groupNewName,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (!blank) Navigator.of(context).pop(_name.text);
              },
            ),
            if (merges != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.groupRenameMerges(merges),
                style: TextStyle(fontSize: 13, color: t.warning),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        FilledButton(
          onPressed: blank ? null : () => Navigator.of(context).pop(_name.text),
          child: Text(s.actionSave),
        ),
      ],
    );
  }
}

/// The other groups, to fold this one into.
class _MergeSheet extends StatelessWidget {
  const _MergeSheet({required this.others});

  final List<PartyGroupSummary> others;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BlTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.groupMergeInto,
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          for (final g in others) ...[
            GroupTotalsCard(
              group: g,
              onTap: () => Navigator.of(context).pop(g.name),
            ),
            const SizedBox(height: BlTokens.space2),
          ],
        ],
      ),
    );
  }
}
