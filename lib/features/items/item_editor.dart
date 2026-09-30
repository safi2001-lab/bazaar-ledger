import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../batches/stock_places_screen.dart';
import '../scan/scan_screen.dart';
import 'item_history_screen.dart';
import 'item_picture.dart';
import 'label_print_sheet.dart';
import 'stock_adjust_sheet.dart';

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
  late final TextEditingController _name = TextEditingController(
    text: widget.item?.name ?? widget.initialName ?? '',
  );
  late final TextEditingController _code = TextEditingController(
    text: widget.item?.code ?? '',
  );
  late final TextEditingController _barcode = TextEditingController(
    text: widget.item?.barcode ?? '',
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.item?.category ?? '',
  );
  late final TextEditingController _saleRate = TextEditingController(
    text: widget.item == null ? '' : widget.item!.saleRate.amountOnly,
  );
  final _purchaseRate = TextEditingController();
  late final TextEditingController _vipRate = TextEditingController(
    text: widget.item?.vipRate?.amountOnly ?? '',
  );
  late final TextEditingController _wholesaleRate = TextEditingController(
    text: widget.item?.wholesaleRate?.amountOnly ?? '',
  );
  late final TextEditingController _mrp = TextEditingController(
    text: widget.item?.mrp?.amountOnly ?? '',
  );
  late final TextEditingController _hsCode = TextEditingController(
    text: widget.item?.hsCode ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.item?.description ?? '',
  );

  /// Whether the shelf is counted for this at all.
  ///
  /// Off for a service or a charge — home delivery, a repair, a bag. Those
  /// belong on a bill and do not belong on a stock ledger, and an item that
  /// carries stock it can never have is an item permanently at minus
  /// something.
  late bool _tracksStock = widget.item?.tracksStock ?? true;
  late bool _tracksBatch = widget.item?.tracksBatch ?? false;
  late bool _tracksSerial = widget.item?.tracksSerial ?? false;
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
    _wholesaleRate.dispose();
    _vipRate.dispose();
    _mrp.dispose();
    _hsCode.dispose();
    _description.dispose();
    _openingStock.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // The very first thing, before the validate and before any await.
    // `onPressed: _busy ? null : _save` only takes effect once a frame has
    // been built, so two taps inside one frame both reach here — and this
    // writes a row. The tender sheet documents and guards the same hazard;
    // that guard was never copied to the editors.
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final units = ref.read(unitsProvider).valueOrNull ?? const [];
    final unitId = _unitId ?? _defaultUnitId(units);
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
        // A wholesaler quotes two prices and a pharmacy has a third printed
        // on the box. Neither is the retail price, and neither can be
        // derived from it.
        wholesaleRate: Rate.tryParse(_wholesaleRate.text),
        vipRate: Rate.tryParse(_vipRate.text),
        mrp: Money.tryParse(_mrp.text),
        // The FBR invoice needs it, and it is per item rather than per bill,
        // so it is captured where the item is.
        hsCode: _blank(_hsCode.text),
        description: _blank(_description.text),
        tracksStock: _tracksStock,
        tracksBatch: _tracksStock && _tracksBatch,
        tracksSerial: _tracksStock && _tracksSerial,
        // Opening stock is an opening balance, not an edit. Changing an
        // existing item's stock happens through a stock adjustment with a
        // reason, which lands in M1 — the ledger is append-only and must
        // never be silently overwritten from a form.
        openingStock: _isEdit || !_tracksStock
            ? Qty.zero
            : Qty.tryParse(_openingStock.text) ?? Qty.zero,
        openingRate: Rate.tryParse(_purchaseRate.text) ?? Rate.zero,
        minStock: Qty.tryParse(_minStock.text) ?? Qty.zero,
      );

      final actor = services.actorNow();
      if (_isEdit) {
        await services.catalogue.updateItem(actor, widget.item!.id, draft);
      } else {
        await services.catalogue.addItem(actor, draft);
      }

      if (!mounted) return;
      ref.bumpRefresh();
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
        content: Text(s.itemArchiveConfirm),
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

    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final services = ref.read(appServicesProvider);
      await services.catalogue.archiveItem(
        services.actorNow(),
        widget.item!.id,
      );
      if (!mounted) return;
      ref.bumpRefresh();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.itemArchived)));
    } on Object catch (error) {
      // Archiving is a write like any other, and a write that fails has to
      // say so. The form stays open with the item intact.
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  static String? _blank(String value) =>
      value.trim().isEmpty ? null : value.trim();

  /// Pieces, when the shop has them.
  ///
  /// Not "whatever the units table returns first". That was centimetres, so a
  /// kiryana owner adding a five-litre tin of oil got a unit of length and no
  /// indication anything was wrong until the bill printed "2 cm".
  static String? _defaultUnitId(
    List<({String id, String code, String name, int decimals})> units,
  ) {
    if (units.isEmpty) return null;
    for (final u in units) {
      if (u.code == 'pcs') return u.id;
    }
    return units.first.id;
  }

  /// Reads a barcode off the packet into the field.
  ///
  /// Whatever the camera reports goes in exactly as read. The
  /// UPC-A/EAN-13 widening happens at LOOKUP, never at storage: normalising on
  /// the way in would rewrite what a shopkeeper can see printed on the packet,
  /// and then the number on screen would not match the number in their hand.
  Future<void> _scanBarcode() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code == null || !mounted) return;
    setState(() => _barcode.text = code);
  }

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
          // Reachable from the item, because that is where a shopkeeper is
          // standing when they notice the shelf and the screen disagree.
          if (_isEdit && widget.item!.tracksStock)
            BlIconButton(
              icon: Icons.fact_check_outlined,
              label: s.stockAdjustTitle,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => StockAdjustSheet(
                  itemId: widget.item!.id,
                  itemName: widget.item!.name,
                  onHand: widget.item!.stockOnHand,
                  unitCode: widget.item!.unitCode,
                ),
              ),
            ),
          // Where it is: the shop floor, the godown, and which batches.
          if (_isEdit && widget.item!.tracksStock)
            BlIconButton(
              icon: Icons.warehouse_outlined,
              label: s.placesTitle,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => StockPlacesScreen(item: widget.item!),
                ),
              ),
            ),
          // "There should be forty and there are thirty-one" is a question
          // the shelf cannot answer and the append-only ledger can.
          if (_isEdit && widget.item!.tracksStock)
            BlIconButton(
              icon: Icons.history,
              label: s.historyTitle,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ItemHistoryScreen(
                    itemId: widget.item!.id,
                    itemName: widget.item!.name,
                    unitCode: widget.item!.unitCode,
                  ),
                ),
              ),
            ),
          // The other half of a barcode workflow. Without it a shopkeeper can
          // scan what a manufacturer printed and nothing they packed
          // themselves.
          if (_isEdit)
            BlIconButton(
              icon: Icons.qr_code_2_outlined,
              label: s.labelTitle,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => LabelPrintSheet(
                  name: widget.item!.name,
                  code: widget.item!.barcode ?? widget.item!.code,
                  priceLabel: widget.item!.saleRate.amountOnly,
                ),
              ),
            ),
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
            // Chosen for display only; the write resolves the same default,
            // so build stays free of state mutation.
            final unitId = _unitId ?? _defaultUnitId(unitList);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(BlTokens.space4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    // Re-validated as the shopkeeper types, once they have
                    // touched the form. Without this a field validated on Save
                    // keeps its red border and its error message after the text
                    // is corrected — the message only refreshes on the next
                    // `validate()` call. Found by hand on the handset: "Aap ka
                    // naam" read "Yeh khana zaroori hai" in red while holding
                    // "Malik Sahib". For an audience where 60% national and 52%
                    // rural literacy is the design constraint, an error that
                    // will not go away is a dead end.
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Above the name, because for a cashier who does not
                        // read fluently the picture IS the name. Only offered
                        // once the item exists: a photograph needs a row to
                        // hang off, and accepting one and losing it would be
                        // worse than not offering.
                        if (_isEdit) ...[
                          ItemPictureField(itemId: widget.item!.id),
                          const SizedBox(height: BlTokens.space4),
                        ],
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
                                validator: (v) => Rate.tryParse(v ?? '') == null
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
                          initialValue: unitId,
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

                        // Whether the shelf is counted for this at all. Off
                        // for a service or a charge — home delivery, a
                        // repair, a carrier bag. Those belong on a bill and
                        // do not belong on a stock ledger, and an item
                        // carrying stock it can never have is an item
                        // permanently at minus something.
                        SwitchListTile.adaptive(
                          value: _tracksStock,
                          onChanged: (value) =>
                              setState(() => _tracksStock = value),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            s.itemTracksStock,
                            style: TextStyle(fontSize: 15, color: t.ink),
                          ),
                          subtitle: _tracksStock
                              ? null
                              : Text(
                                  s.itemTracksStockOff,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.inkMuted,
                                  ),
                                ),
                        ),
                        // A pharmacy's strips by batch and expiry, a mobile
                        // shop's phones by IMEI. One or the other, never
                        // both: a piece with a serial is its own lot.
                        if (_tracksStock) ...[
                          SwitchListTile.adaptive(
                            value: _tracksBatch,
                            onChanged: (value) => setState(() {
                              _tracksBatch = value;
                              if (value) _tracksSerial = false;
                            }),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              s.itemTracksBatch,
                              style: TextStyle(fontSize: 15, color: t.ink),
                            ),
                          ),
                          SwitchListTile.adaptive(
                            value: _tracksSerial,
                            onChanged: (value) => setState(() {
                              _tracksSerial = value;
                              if (value) _tracksBatch = false;
                            }),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              s.itemTracksSerial,
                              style: TextStyle(fontSize: 15, color: t.ink),
                            ),
                          ),
                        ],
                        const SizedBox(height: BlTokens.space4),
                        BlField(
                          controller: _barcode,
                          label: s.itemBarcode,
                          textInputAction: TextInputAction.next,
                          // Thirteen digits typed by hand off a packet, at a
                          // counter, is where a catalogue gets its wrong
                          // barcodes — and a wrong barcode is worse than none,
                          // because it silently matches the wrong packet at
                          // the till.
                          suffix: BlIconButton(
                            icon: Icons.qr_code_scanner,
                            label: s.scanTitle,
                            onPressed: _scanBarcode,
                          ),
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
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                          ],
                        ),

                        // Folded away, because most of a kiryana catalogue
                        // needs none of it. A wholesaler needs the trade
                        // price, a pharmacy needs the printed one, and a
                        // sales-tax-registered shop needs the HS code on
                        // every line of its invoice — but making all three
                        // of them the first thing everyone else scrolls past
                        // would slow down the common case to serve the rare.
                        const SizedBox(height: BlTokens.space3),
                        ExpansionTile(
                          title: Text(
                            s.itemMoreFields,
                            style: TextStyle(fontSize: 14, color: t.inkMuted),
                          ),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(
                            bottom: BlTokens.space3,
                          ),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: BlField(
                                    controller: _wholesaleRate,
                                    label: s.itemWholesalePrice,
                                    numeric: true,
                                    textInputAction: TextInputAction.next,
                                  ),
                                ),
                                const SizedBox(width: BlTokens.space3),
                                Expanded(
                                  child: BlField(
                                    controller: _vipRate,
                                    label: s.itemVipPrice,
                                    numeric: true,
                                    textInputAction: TextInputAction.next,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: BlTokens.space3),
                            Row(
                              children: [
                                Expanded(
                                  child: BlField(
                                    controller: _mrp,
                                    label: s.itemMrp,
                                    numeric: true,
                                    textInputAction: TextInputAction.next,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: BlTokens.space4),
                            BlField(
                              controller: _hsCode,
                              label: s.itemHsCode,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: BlTokens.space4),
                            BlField(
                              controller: _description,
                              label: s.itemDescription,
                              textInputAction: TextInputAction.done,
                              // The button is disabled while busy; Enter has
                              // to check the same flag or a double tap on the
                              // keyboard writes twice.
                              onSubmitted: (_) {
                                if (!_busy) _save();
                              },
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
