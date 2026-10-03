import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/item_scheme_screen.dart';

/// Every item that has a scheme, with it.
final _itemsWithSchemesProvider =
    FutureProvider.autoDispose<List<({ItemSummary item, ItemScheme scheme})>>((
      ref,
    ) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).itemsWithSchemes();
    });

/// Settings → Schemes (M43): every item's bonus and quantity slabs in one
/// list, and the shop's discount on a big bill.
///
/// The item's own editor opens the same item screen; this is where an owner
/// comes to see what the shop is giving away all at once — the list a
/// distributor's new scheme sheet is checked against at the start of the
/// month.
class SchemesScreen extends ConsumerStatefulWidget {
  const SchemesScreen({super.key});

  @override
  ConsumerState<SchemesScreen> createState() => _SchemesScreenState();
}

class _BillRow {
  _BillRow({String from = '', String percent = ''})
    : from = TextEditingController(text: from),
      percent = TextEditingController(text: percent);

  final TextEditingController from;
  final TextEditingController percent;

  bool get isBlank => from.text.trim().isEmpty && percent.text.trim().isEmpty;

  void dispose() {
    from.dispose();
    percent.dispose();
  }
}

class _SchemesScreenState extends ConsumerState<SchemesScreen> {
  final _rows = <_BillRow>[];
  bool _loaded = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final slabs = await ref.read(appServicesProvider).billSlabs();
    if (!mounted) return;
    setState(() {
      for (final b in slabs) {
        _rows.add(
          _BillRow(
            from: b.from.amountOnly.replaceAll(',', ''),
            // Basis points read as a figure with two decimals: 250 is 2.50.
            percent: Money.paisa(b.percentBp).amountOnly,
          ),
        );
      }
      if (_rows.isEmpty) _rows.add(_BillRow());
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _saveSlabs() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final slabs = <BillSlab>[];
    for (final r in _rows) {
      if (r.isBlank) continue;
      final from = Money.tryParse(r.from.text.trim());
      // A percentage to two places is basis points the way a rupee figure
      // to two places is paisa, so the money parser reads it exactly.
      final bp = Money.tryParse(r.percent.text.trim())?.inPaisa;
      if (from == null || bp == null) {
        setState(() => _failure = s.schemeProblemFigures);
        return;
      }
      slabs.add(BillSlab(from: from, percentBp: bp));
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appServicesProvider).saveBillSlabs(slabs);
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.schemeSaved)));
    } on SchemeRefused catch (refused) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = schemeProblemText(s, refused.problem);
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  Future<void> _open(ItemSummary item) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => ItemSchemeScreen(item: item)));

  Future<void> _addItem() async {
    final item = await showSchemeItemPicker(context);
    if (item != null && mounted) await _open(item);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayEdit = ref.watch(appServicesProvider).canSetSchemes;
    final items = ref.watch(_itemsWithSchemesProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.schemesTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
          ),
          children: [
            Text(
              s.schemesIntro,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (!mayEdit) ...[
              const SizedBox(height: BlTokens.space3),
              BlOfflineNote(message: s.schemesOwnerOnly),
            ],
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.schemesItemsHeader),
            const SizedBox(height: BlTokens.space2),
            items.when(
              loading: () => const BlSkeletonList(rows: 2),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) => rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: BlTokens.space2,
                      ),
                      child: Text(
                        s.schemesNoItems,
                        style: TextStyle(fontSize: 14, color: t.inkMuted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: BlCard(
                              onTap: () => unawaited(_open(r.item)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.item.name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: t.ink,
                                          ),
                                        ),
                                        Text(
                                          [
                                            if (r.scheme.bonus case final b?)
                                              s.schemeBonusLabel(b.label),
                                            if (r.scheme.slabs.isNotEmpty)
                                              s.schemeSlabsLabel(
                                                r.scheme.slabs.length,
                                              ),
                                          ].join(' · '),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: t.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: t.inkFaint,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (mayEdit)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => unawaited(_addItem()),
                  icon: const Icon(Icons.add),
                  label: Text(s.schemesAddItem),
                ),
              ),
            const SizedBox(height: BlTokens.space5),
            BlSectionHeader(s.billSlabsHeader),
            const SizedBox(height: BlTokens.space2),
            if (!_loaded)
              const BlSkeletonList(rows: 1)
            else ...[
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space2),
                  child: Row(
                    children: [
                      Expanded(
                        child: BlField(
                          controller: _rows[i].from,
                          label: s.billSlabFrom,
                          numeric: true,
                          enabled: mayEdit,
                        ),
                      ),
                      const SizedBox(width: BlTokens.space2),
                      Expanded(
                        child: BlField(
                          controller: _rows[i].percent,
                          label: s.billSlabPercent,
                          numeric: true,
                          enabled: mayEdit,
                        ),
                      ),
                      if (mayEdit)
                        BlIconButton(
                          icon: Icons.delete_outline,
                          label: s.actionDelete,
                          onPressed: () => setState(() {
                            _rows.removeAt(i).dispose();
                            if (_rows.isEmpty) _rows.add(_BillRow());
                          }),
                        ),
                    ],
                  ),
                ),
              if (mayEdit) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _rows.add(_BillRow())),
                    icon: const Icon(Icons.add),
                    label: Text(s.schemeAddSlab),
                  ),
                ),
                if (_failure != null) ...[
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    _failure!,
                    style: TextStyle(fontSize: 13, color: t.danger),
                  ),
                ],
                const SizedBox(height: BlTokens.space3),
                BlButton(
                  label: s.actionSave,
                  icon: Icons.check,
                  busy: _busy,
                  onPressed: _busy ? null : () => unawaited(_saveSlabs()),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
