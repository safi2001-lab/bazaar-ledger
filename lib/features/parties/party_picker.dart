import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'parties_screen.dart';
import 'party_editor.dart';

/// Choose who the bill is for, from the tender sheet.
///
/// Returns the chosen party, or null if the sheet was dismissed. A walk-in
/// stays a walk-in: this is never forced open on the billing path.
class PartyPicker extends ConsumerStatefulWidget {
  const PartyPicker({super.key});

  @override
  ConsumerState<PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends ConsumerState<PartyPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final parties = ref.watch(partySearchProvider(_query));

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: BlSectionHeader(s.posChooseCustomer)),
              BlIconButton(
                icon: Icons.person_add_alt,
                label: s.partiesAdd,
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PartyEditorScreen(
                        initialName: _query.isEmpty ? null : _query,
                      ),
                    ),
                  );
                  if (mounted) ref.invalidate(partySearchProvider(_query));
                },
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _search,
            label: s.actionSearch,
            hint: s.partyName,
            autofocus: true,
            onChanged: _onChanged,
            prefix: const Icon(Icons.search, size: 20),
          ),
          const SizedBox(height: BlTokens.space3),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: parties.when(
              loading: () => const BlSkeletonList(rows: 3),
              error: (error, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$error',
                retryLabel: s.actionRetry,
                onRetry: () => ref.invalidate(partySearchProvider(_query)),
              ),
              data: (rows) => rows.isEmpty
                  ? BlEmpty(
                      title: s.partiesEmpty,
                      message: s.partiesEmptyHint,
                      icon: Icons.people_alt_outlined,
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemExtent: 68,
                      itemBuilder: (context, i) => PartyRowTile(
                        key: ValueKey(rows[i].id),
                        party: rows[i],
                        trailingChevron: false,
                        onTap: () =>
                            Navigator.of(context).pop<PartySummary>(rows[i]),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: BlTokens.space4),
        ],
      ),
    );
  }
}
