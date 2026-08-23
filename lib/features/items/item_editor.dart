import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Add an item, or change one.
///
/// The previous build shipped an "AddEdit" screen that could only add — the
/// edit path resolved to the same insert. Here the two are the same form and
/// the same validation, and the only difference is which writer method the
/// save button calls.
class ItemEditorScreen extends ConsumerStatefulWidget {
  const ItemEditorScreen({super.key, this.item, this.initialName});

  final ItemSummary? item;

  /// Prefilled when the counter searched for something that did not exist and
  /// tapped "add" — the shopkeeper should never type the name twice.
  final String? initialName;

  @override
  ConsumerState<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends ConsumerState<ItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.item?.name ?? widget.initialName ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.item?.code ?? '');
  late final TextEditingController _barcode =
      TextEditingController(text: widget.item?.barcode ?? '');
  late final TextEditingController _category =
      TextEditingController(text: widget.item?.category ?? '');
  late final TextEditingController _saleRate = TextEditingController(
    text: widget.item == null ? '' : widget.item!.saleRate.amountOnly,
  );
  final _purchaseRate = TextEditingController();
  late final TextEditingController _openingStock = TextEditingController(
    text: widget.item == null ? '' : widget.item!.stockOnHand.display,
  );
  late final TextEditingController _minStock = TextEditingController(
    text: widget.item == null || widget.item!.minStock.isZero
        ? ''
        : widget.item!.minStock.display,
  );

  String? _unitId;
  bool _busy = false;
  String? _failure;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _unitId = widget.item?.unitId;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _barcode.dispose();
    _category.dispose();
    _saleRate.dispose();
    _purchaseRate.dispose();
    _openingStock.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final unitId = _unitId;
    if (unitId == null) {
      setState(() => _failure = s.commonRequired);
      return;
    }

    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final services = ref.read(appServicesProvider);
      final draft = ItemDraft(
        name: _name.text.trim(),
        baseUnitId: unitId,
        saleRate: Rate.tryParse(_saleRate.text) ?? Rate.zero,
        code: _blank(_code.text),
        barcode: _blank(_barcode.text),
        category: _blank(_category.text),
        purchaseRate: Rate.tryParse(_purchaseRate.text),
        // Opening stock is an opening balance, not an edit. Changing an
        // existing item's stock happens through a stock adjustment with a
        // reason, which lands in M1 — the ledger is append-only and must
        // never be silently overwritten from a form.
        openingStock:
            _isEdit ? Qty.zero : Qty.tryParse(_openingStock.text) ?? Qty.zero,
        openingRate: Rate.tryParse(_purchaseRate.text) ?? Rate.zero,
        minStock: Qty.tryParse(_minStock.text) ?? Qty.zero,
      );

      final actor = services.actorNow();
      if (_isEdit) {
        await services.catalogue.updateItem(actor, widget.item!.id, draft);
      } else {
        await services.catalogue.addItem(actor, draft);
      }

      ref.bumpRefresh();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(s.itemSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _archive() async {
    final s = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.itemArchive),
        content: Text(s.settingsAboutBody),
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
    if (!(yes ?? false) || !mounted) return;

    final services = ref.read(appServicesProvider);
    await services.catalogue.archiveItem(services.actorNow(), widget.item!.id);
    ref.bumpRefresh();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(s.itemArchived)));
  }

  static String? _blank(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final units = ref.watch(unitsProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(_isEdit ? s.itemsEdit : s.itemsAdd),
        actions: [
          if (_isEdit)
            BlIconButton(
              icon: Icons.archive_outlined,
              label: s.itemArchive,
              colour: t.danger,
              onPressed: _archive,
            ),
        ],
      ),
      body: SafeArea(
        child: units.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 5),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(unitsProvider),
            ),
          ),
          data: (unitList) {
            if (unitList.isEmpty) {
              return Center(child: BlEmpty(title: s.commonSomethingWentWrong));
            }
            _unitId ??= unitList.first.id;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(BlTokens.space4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BlField(
                          controller: _name,
                          label: s.itemName,
                          hint: s.itemNameHint,
                          autofocus: !_isEdit,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? s.commonRequired
                              : null,
                        ),
                        const SizedBox(height: BlTokens.space4),
                        Row(
                          children: [
                            Expanded(
                              child: BlField(
                                controller: _saleRate,
                                label: s.itemSalePrice,
                                numeric: true,
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    Rate.tryParse(v ?? '') == null
                                        ? s.commonRequired
                                        : null,
                              ),
                            ),
                            const SizedBox(width: BlTokens.space3),
                            Expanded(
                              child: BlField(
                                controller: _purchaseRate,
                                label: s.itemPurchasePrice,
                                numeric: true,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: BlTokens.space4),
                        DropdownButtonFormField<String>(
                          initialValue: _unitId,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: s.itemUnit),
                          items: [
                            for (final u in unitList)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text('${u.name} (${u.code})'),
                              ),
                          ],
                          onChanged: _isEdit
                              ? null
                              : (v) => setState(() => _unitId = v),
                        ),
                        const SizedBox(height: BlTokens.space4),
                        Row(
                          children: [
                            Expanded(
                              child: BlField(
                                controller: _openingStock,
                                label: s.itemOpeningStock,
                                numeric: true,
                                decimals: 3,
                                enabled: !_isEdit,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: BlTokens.space3),
                            Expanded(
                              child: BlField(
                                controller: _minStock,
                                label: s.itemMinStock,
                                numeric: true,
                                decimals: 3,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: BlTokens.space4),
                        BlField(
                          controller: _barcode,
                          label: s.itemBarcode,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: BlTokens.space4),
                        Row(
                          children: [
                            Expanded(
                              child: BlField(
                                controller: _code,
                                label: s.itemCode,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: BlTokens.space3),
                            Expanded(
                              child: BlField(
                                controller: _category,
                                label: s.itemCategory,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _save(),
                              ),
                            ),
                          ],
                        ),
                        if (_failure != null) ...[
                          const SizedBox(height: BlTokens.space4),
                          Text(
                            _failure!,
                            style: TextStyle(fontSize: 13, color: t.danger),
                          ),
                        ],
                        const SizedBox(height: BlTokens.space6),
                        BlButton(
                          label: s.actionSave,
                          icon: Icons.check,
                          big: true,
                          busy: _busy,
                          onPressed: _busy ? null : _save,
                        ),
                        const SizedBox(height: BlTokens.space6),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
