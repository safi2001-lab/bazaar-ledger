import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/add_offer.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'parties_screen.dart';
import 'party_editor.dart';
import 'quick_party_sheet.dart';

/// Choose who the bill is for, from the tender sheet.
///
/// Returns the chosen party, or null if the sheet was dismissed. A walk-in
/// stays a walk-in: this is never forced open on the billing path.
class PartyPicker extends ConsumerStatefulWidget {
  const PartyPicker({super.key, this.newPartyType});

  /// What a name typed here that matches nobody is offered as (M32):
  /// `customer` from the counter, `supplier` from a delivery.
  ///
  /// Null offers nothing, and is the default on purpose. A screen that has
  /// not said which it wants would otherwise open a customer's khata for
  /// whoever its payee turned out to be.
  final String? newPartyType;

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

  /// Opens the short form with what was typed, and hands whoever it made —
  /// or whoever the shopkeeper said it already was — straight back to the
  /// bill. The customer is chosen, not just added: that is the whole point.
  Future<void> _addNew(String type) async {
    final navigator = Navigator.of(context);
    final party = await showQuickPartySheet(
      context,
      name: _query,
      partyType: type,
    );
    if (party != null && mounted) navigator.pop<PartySummary>(party);
  }

  /// The offer, when a name was typed and nobody in the list is exactly it.
  ///
  /// Exactly, not "nothing at all came back": a shop with "Ali Traders" in
  /// its khata still has to be able to add a customer called "Ali", and the
  /// search for one always finds the other.
  Widget? _offer(AppStrings s, List<PartySummary> rows) {
    final type = widget.newPartyType;
    if (type == null || _query.isEmpty) return null;
    final key = PartyDraft(name: _query).searchKey;
    if (key.isEmpty) return null;
    if (rows.any((p) => PartyDraft(name: p.name).searchKey == key)) {
      return null;
    }
    return BlAddOffer(
      icon: Icons.person_add_alt_1_outlined,
      label: type == 'supplier'
          ? s.quickAddSupplier(_query)
          : s.quickAddCustomer(_query),
      onTap: () => unawaited(_addNew(type)),
    );
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
              data: (rows) {
                final offer = _offer(s, rows);
                if (rows.isEmpty) {
                  // A name nobody has is a new customer, not an empty khata:
                  // the offer stands where "add your first customer" was.
                  return offer ??
                      BlEmpty(
                        title: s.partiesEmpty,
                        message: s.partiesEmptyHint,
                        icon: Icons.people_alt_outlined,
                      );
                }
                final list = ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemExtent: blRowExtent(context, 68),
                  itemBuilder: (context, i) => PartyRowTile(
                    key: ValueKey(rows[i].id),
                    party: rows[i],
                    trailingChevron: false,
                    onTap: () =>
                        Navigator.of(context).pop<PartySummary>(rows[i]),
                  ),
                );
                if (offer == null) return list;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    offer,
                    const SizedBox(height: BlTokens.space2),
                    Flexible(child: list),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: BlTokens.space4),
        ],
      ),
    );
  }
}
