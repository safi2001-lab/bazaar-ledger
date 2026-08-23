import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'party_editor.dart';

/// Reset when the screen goes. See [itemsQueryProvider].
final partiesQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// The khata: who owes what.
class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(partiesQueryProvider.notifier).state = value.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final query = ref.watch(partiesQueryProvider);
    final parties = ref.watch(partySearchProvider(query));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.partiesTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BlTokens.space4,
                BlTokens.space3,
                BlTokens.space4,
                BlTokens.space2,
              ),
              child: BlField(
                controller: _search,
                label: s.actionSearch,
                hint: s.partyName,
                onChanged: _onChanged,
                prefix: const Icon(Icons.search, size: 20),
              ),
            ),
            Expanded(
              child: parties.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(BlTokens.space4),
                  child: BlSkeletonList(),
                ),
                error: (error, _) => Center(
                  child: BlError(
                    title: s.commonSomethingWentWrong,
                    message: '$error',
                    retryLabel: s.actionRetry,
                    onRetry: () => ref.invalidate(partySearchProvider(query)),
                  ),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Center(
                      child: BlEmpty(
                        title: query.isEmpty
                            ? s.partiesEmpty
                            : s.emptyNoResults,
                        message: query.isEmpty
                            ? s.partiesEmptyHint
                            : s.emptyNoResultsHint,
                        icon: Icons.people_alt_outlined,
                        action: BlButton(
                          label: s.partiesAdd,
                          icon: Icons.person_add_alt,
                          onPressed: () => _open(context),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      BlTokens.space4,
                      0,
                      BlTokens.space4,
                      BlTokens.space10 * 2,
                    ),
                    itemCount: rows.length,
                    itemExtent: blRowExtent(context, 68),
                    itemBuilder: (context, i) => PartyRowTile(
                      key: ValueKey(rows[i].id),
                      party: rows[i],
                      onTap: () => _open(context, rows[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.person_add_alt),
        label: Text(s.partiesAdd),
      ),
    );
  }

  static void _open(BuildContext context, [PartySummary? party]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PartyEditorScreen(party: party)),
    );
  }
}

/// One customer in a list, with what they owe.
class PartyRowTile extends StatelessWidget {
  const PartyRowTile({
    super.key,
    required this.party,
    required this.onTap,
    this.trailingChevron = true,
  });

  final PartySummary party;
  final VoidCallback onTap;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final owes = party.balance.isPositive;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BlTokens.space2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    if (party.phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        party.phone!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.inkMuted,
                          fontFeatures: BlTokens.tabular,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              // Flexible and scaled, not a fixed lump.
              //
              // A non-flex child of a Row claims its full natural width
              // first, so at 200% the balance chip took 204dp of a 360dp
              // screen and left the customer's name 70dp — about two glyphs
              // and an ellipsis. Every debtor in the khata rendered as the
              // same unreadable stub, and only for the users who turned the
              // font up because they could not read the small one.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: owes
                      ? BlChip(
                          s.partyOwes(party.balance.amountOnly),
                          tone: party.isOverCreditLimit
                              ? BlChipTone.bad
                              : BlChipTone.warn,
                        )
                      : BlChip(s.partySettled, tone: BlChipTone.good),
                ),
              ),
              if (trailingChevron) Icon(Icons.chevron_right, color: t.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
