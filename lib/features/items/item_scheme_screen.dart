import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'pack_choice.dart';

/// One item's scheme (M43): its bonus ("10+1") and its prices by quantity
/// ("12 and up, Rs 46"), as the owner sets them. Opened from the item's own
/// editor and from Settings → Schemes.
///
/// Saved on its own, not with the item: a scheme is the owner's to change
/// and an item's price may be a manager's, and the two are kept apart in
/// the books too (a settings row against the item's own row). Everybody may
/// read it; only whoever may change the shop's settings may change it, as
/// with the rule for selling below nothing (M53).
///
/// Quantities and rates here are in the item's own unit — pieces, not
/// cartons — except the bonus, which may be counted in one of the item's
/// packs: "10+1 cartons" is how a distributor says it.
class ItemSchemeScreen extends ConsumerStatefulWidget {
  const ItemSchemeScreen({super.key, required this.item});

  final ItemSummary item;

  @override
  ConsumerState<ItemSchemeScreen> createState() => _ItemSchemeScreenState();
}

class _SlabRow {
  _SlabRow({String from = '', String rate = ''})
    : from = TextEditingController(text: from),
      rate = TextEditingController(text: rate);

  final TextEditingController from;
  final TextEditingController rate;

  bool get isBlank => from.text.trim().isEmpty && rate.text.trim().isEmpty;

  void dispose() {
    from.dispose();
    rate.dispose();
  }
}

class _ItemSchemeScreenState extends ConsumerState<ItemSchemeScreen> {
  final _buy = TextEditingController();
  final _free = TextEditingController();
  final _slabs = <_SlabRow>[];

  /// The pack the bonus is counted in, or null for the item's own unit.
  String? _bonusUnitId;

  /// Another item given free, or null for more of the same.
  ItemSummary? _freeItem;

  bool _loaded = false;
  bool _had = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final services = ref.read(appServicesProvider);
    final scheme = await services.itemScheme(widget.item.id);
    ItemSummary? freeItem;
    final freeId = scheme.bonus?.freeItemId;
    final firmId = services.identity?.firmId;
    if (freeId != null && firmId != null) {
      freeItem = await services.queries.itemById(firmId, freeId);
    }
    if (!mounted) return;
    setState(() {
      _had = !scheme.isEmpty;
      if (scheme.bonus case final b?) {
        _buy.text = b.buy.display;
        _free.text = b.free.display;
        _bonusUnitId = b.unitId;
      }
      _freeItem = freeItem;
      for (final slab in scheme.slabs) {
        _slabs.add(
          _SlabRow(from: slab.from.display, rate: slab.rate.amountOnly),
        );
      }
      if (_slabs.isEmpty) _slabs.add(_SlabRow());
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _buy.dispose();
    _free.dispose();
    for (final r in _slabs) {
      r.dispose();
    }
    super.dispose();
  }

  /// What the screen holds, as a scheme; null when a figure will not read.
  ItemScheme? _scheme() {
    BonusRule? bonus;
    if (_buy.text.trim().isNotEmpty || _free.text.trim().isNotEmpty) {
      final buy = Qty.tryParse(_buy.text.trim());
      final free = Qty.tryParse(_free.text.trim());
      if (buy == null || free == null) return null;
      bonus = BonusRule(
        buy: buy,
        free: free,
        // A different item is given in its own unit; the pack is this
        // item's.
        unitId: _freeItem == null ? _bonusUnitId : null,
        freeItemId: _freeItem?.id,
      );
    }
    final slabs = <QtySlab>[];
    for (final r in _slabs) {
      if (r.isBlank) continue;
      final from = Qty.tryParse(r.from.text.trim());
      final rate = Rate.tryParse(r.rate.text.trim());
      if (from == null || rate == null) return null;
      slabs.add(QtySlab(from: from, rate: rate));
    }
    return ItemScheme(itemId: widget.item.id, bonus: bonus, slabs: slabs);
  }

  Future<void> _save({bool takeOff = false}) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final scheme = takeOff ? ItemScheme(itemId: widget.item.id) : _scheme();
    if (scheme == null) {
      setState(() => _failure = s.schemeProblemFigures);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appServicesProvider).saveItemScheme(scheme);
      if (!mounted) return;
      ref.bumpRefresh();
      navigator.pop();
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

  Future<void> _pickFreeItem() async {
    final picked = await showSchemeItemPicker(context);
    if (picked != null && mounted) {
      setState(() {
        _freeItem = picked.id == widget.item.id ? null : picked;
        _failure = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final item = widget.item;
    final mayEdit = ref.watch(appServicesProvider).canSetSchemes;
    final packs = PackChoice.packsFor(ref, item);
    final bonusUnit = _freeItem != null
        ? null
        : packs.where((p) => p.unitId == _bonusUnitId).firstOrNull;
    final buyUnit = bonusUnit?.unitCode ?? item.unitCode;
    final freeUnit = _freeItem?.unitCode ?? buyUnit;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.itemSchemeTitle(item.name))),
      body: SafeArea(
        child: !_loaded
            ? const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
                ),
                children: [
                  if (!mayEdit) ...[
                    BlOfflineNote(message: s.schemesOwnerOnly),
                    const SizedBox(height: BlTokens.space3),
                  ],
                  BlSectionHeader(s.bonusHeader),
                  const SizedBox(height: BlTokens.space2),
                  Row(
                    children: [
                      Expanded(
                        child: BlField(
                          controller: _buy,
                          label: s.bonusBuy(buyUnit),
                          numeric: true,
                          decimals: 3,
                          enabled: mayEdit,
                          onChanged: (_) => setState(() => _failure = null),
                        ),
                      ),
                      const SizedBox(width: BlTokens.space3),
                      Expanded(
                        child: BlField(
                          controller: _free,
                          label: s.bonusFree(freeUnit),
                          numeric: true,
                          decimals: 3,
                          enabled: mayEdit,
                          onChanged: (_) => setState(() => _failure = null),
                        ),
                      ),
                    ],
                  ),
                  if (packs.isNotEmpty && _freeItem == null) ...[
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      s.bonusCountedIn,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                    const SizedBox(height: BlTokens.space1),
                    Wrap(
                      spacing: BlTokens.space2,
                      runSpacing: BlTokens.space2,
                      children: [
                        ChoiceChip(
                          label: Text(item.unitCode),
                          selected: bonusUnit == null,
                          onSelected: mayEdit
                              ? (_) => setState(() => _bonusUnitId = null)
                              : null,
                        ),
                        for (final pack in packs)
                          ChoiceChip(
                            label: Text(
                              '${pack.unitCode} · ${pack.size.display} '
                              '${item.unitCode}',
                            ),
                            selected: bonusUnit?.unitId == pack.unitId,
                            onSelected: mayEdit
                                ? (_) =>
                                      setState(() => _bonusUnitId = pack.unitId)
                                : null,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: BlTokens.space2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.bonusFreeGoods(_freeItem?.name ?? s.bonusSameItem),
                          style: TextStyle(fontSize: 14, color: t.ink),
                        ),
                      ),
                      if (mayEdit && _freeItem != null)
                        BlIconButton(
                          icon: Icons.close,
                          label: s.bonusSameItem,
                          onPressed: () => setState(() => _freeItem = null),
                        ),
                      if (mayEdit)
                        TextButton(
                          onPressed: () => unawaited(_pickFreeItem()),
                          child: Text(s.bonusOtherItem),
                        ),
                    ],
                  ),
                  if (Qty.tryParse(_buy.text.trim()) case final buy?
                      when buy.isPositive)
                    if (Qty.tryParse(_free.text.trim()) case final free?
                        when free.isPositive)
                      Text(
                        s.bonusExplain(
                          '${buy.display} $buyUnit',
                          '${free.display} $freeUnit '
                              '${_freeItem?.name ?? item.name}',
                        ),
                        style: TextStyle(fontSize: 13, color: t.accent),
                      ),
                  const SizedBox(height: BlTokens.space5),
                  BlSectionHeader(s.slabsHeader),
                  const SizedBox(height: BlTokens.space1),
                  Text(
                    s.slabHint,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  for (var i = 0; i < _slabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: Row(
                        children: [
                          Expanded(
                            child: BlField(
                              controller: _slabs[i].from,
                              label: s.slabFrom(item.unitCode),
                              numeric: true,
                              decimals: 3,
                              enabled: mayEdit,
                            ),
                          ),
                          const SizedBox(width: BlTokens.space2),
                          Expanded(
                            child: BlField(
                              controller: _slabs[i].rate,
                              label: s.slabRate(item.unitCode),
                              numeric: true,
                              enabled: mayEdit,
                            ),
                          ),
                          if (mayEdit)
                            BlIconButton(
                              icon: Icons.delete_outline,
                              label: s.actionDelete,
                              onPressed: () => setState(() {
                                _slabs.removeAt(i).dispose();
                                if (_slabs.isEmpty) _slabs.add(_SlabRow());
                              }),
                            ),
                        ],
                      ),
                    ),
                  if (mayEdit)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _slabs.add(_SlabRow())),
                        icon: const Icon(Icons.add),
                        label: Text(s.schemeAddSlab),
                      ),
                    ),
                  if (_failure != null) ...[
                    const SizedBox(height: BlTokens.space3),
                    Text(
                      _failure!,
                      style: TextStyle(fontSize: 13, color: t.danger),
                    ),
                  ],
                  if (mayEdit) ...[
                    const SizedBox(height: BlTokens.space5),
                    BlButton(
                      label: s.actionSave,
                      icon: Icons.check,
                      big: true,
                      busy: _busy,
                      onPressed: _busy ? null : () => unawaited(_save()),
                    ),
                    if (_had) ...[
                      const SizedBox(height: BlTokens.space2),
                      BlButton(
                        label: s.schemeTakeOff,
                        icon: Icons.delete_outline,
                        kind: BlButtonKind.secondary,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_save(takeOff: true)),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

/// A scheme refusal in the owner's words.
String schemeProblemText(AppStrings s, SchemeProblem problem) =>
    switch (problem) {
      SchemeProblem.bonusEmpty => s.schemeProblemBonusEmpty,
      SchemeProblem.slabEmpty => s.schemeProblemSlabEmpty,
      SchemeProblem.slabTwice => s.schemeProblemSlabTwice,
      SchemeProblem.slabOutOfOrder => s.schemeProblemOutOfOrder,
      SchemeProblem.billSlabPercent => s.schemeProblemPercent,
    };

/// Picks an item from the catalogue for a scheme: the item to give one, or
/// the item a bonus gives free.
Future<ItemSummary?> showSchemeItemPicker(BuildContext context) =>
    showModalBottomSheet<ItemSummary>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SchemeItemPicker(),
    );

class _SchemeItemPicker extends ConsumerStatefulWidget {
  const _SchemeItemPicker();

  @override
  ConsumerState<_SchemeItemPicker> createState() => _SchemeItemPickerState();
}

class _SchemeItemPickerState extends ConsumerState<_SchemeItemPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final results = ref.watch(itemSearchProvider(_query));
    return Padding(
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
          BlField(
            controller: _search,
            label: s.actionSearch,
            autofocus: true,
            prefix: const Icon(Icons.search, size: 20),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () {
                if (mounted) setState(() => _query = value.trim());
              });
            },
          ),
          const SizedBox(height: BlTokens.space2),
          SizedBox(
            height: 300,
            child: results.when(
              loading: () => const BlSkeletonList(),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) => rows.isEmpty
                  ? BlEmpty(icon: Icons.search_off, title: s.emptyNoResults)
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(rows[i].name),
                        subtitle: Text(rows[i].unitCode),
                        onTap: () => Navigator.of(context).pop(rows[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
