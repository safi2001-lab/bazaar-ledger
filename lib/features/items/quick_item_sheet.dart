import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/quick_party_sheet.dart' show refusalWords;

/// A new item, made from the bill or the delivery it first turned up on
/// (M32).
///
/// "In Vyapar, when we make a bill and the product is new, it gets added
/// automatically." Here a search that finds nothing, or a packet whose
/// barcode nobody has, or a scale label for a PLU the shop never coded, all
/// end in this sheet: the name or the code already filled in, a price, a
/// unit, and — for whoever may see what goods cost — the cost and what is
/// on the shelf. The item it makes goes straight back to whoever opened it,
/// to be put on the bill or on the delivery.
///
/// It writes through `catalogue.addItem`, the full editor's own path, with the
/// draft built the way the full editor builds it: opening stock is a ledger
/// row and an opening-stock entry in the books, valued at the cost typed, and
/// the item's average cost starts there. Nothing about a quick add is a
/// second way of making an item, so nothing about it can drift from the
/// first.
Future<ItemSummary?> showQuickItemSheet(
  BuildContext context, {
  String name = '',
  String? barcode,
  String? code,
  bool weighed = false,
  bool forPurchase = false,
}) => showModalBottomSheet<ItemSummary>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => QuickItemSheet(
    initialName: name,
    barcode: barcode,
    code: code,
    weighed: weighed,
    forPurchase: forPurchase,
  ),
);

/// What a search that found nothing would be as an item's barcode, or null
/// when it reads as a name.
///
/// A wedge scanner types into the same field a cashier types names into, so
/// the only way to tell them apart is what arrived. Eight to fourteen digits
/// is an EAN-8, a UPC-A, an EAN-13 or a GTIN-14, and a GS1 pack code carries
/// its GTIN inside, kept the way the counter looks it up. Anything else —
/// "Surf Excel 1kg", an IMEI's fifteen digits, a shop's own `CHAWAL-5KG` — is
/// offered as the name, which the shopkeeper can still correct.
String? scannedBarcode(String text) {
  final code = text.trim();
  if (parseGs1(code) case final gs1?) return gs1.ean13 ?? gs1.gtin;
  if (RegExp(r'^\d{8,14}$').hasMatch(code)) return code;
  return null;
}

/// Items already in the shop under this name, once capitals, spaces and
/// punctuation are set aside — the normalisation the item's own search key
/// is stored under. Read with the counter's own search.
Future<List<ItemSummary>> itemTwins(
  AppQueries queries,
  String firmId,
  String name,
) async {
  String key(String n) =>
      ItemDraft(name: n, baseUnitId: '', saleRate: Rate.zero).searchKey;
  final wanted = key(name);
  if (wanted.isEmpty) return const [];
  return [
    for (final item in await queries.searchItems(
      firmId,
      query: name,
      limit: 20,
    ))
      if (key(item.name) == wanted) item,
  ];
}

/// The unit a new item starts in: the shop's usual.
///
/// What most of the shop's items are kept in — read from the first page of
/// its catalogue, which is the forty it entered first and so the shape of
/// what it sells — and pieces in a shop with nothing yet, as the full editor
/// does. Something weighed off a scale label starts in kilos. A kiryana
/// counter adding its two-hundredth item does not want to pick "pcs" again,
/// and a butcher does not want to be offered pieces of mutton.
final _usualUnitProvider = FutureProvider.autoDispose.family<String?, bool>((
  ref,
  weighed,
) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  final units = await services.queries.units(firm.id);
  if (units.isEmpty) return null;
  String? byCode(String code) =>
      units.where((u) => u.code == code).firstOrNull?.id;
  if (weighed) {
    return byCode('kg') ?? byCode('g') ?? byCode('pcs') ?? units.first.id;
  }

  final known = {for (final u in units) u.id};
  final counts = <String, int>{};
  for (final item in await services.queries.searchItems(firm.id, limit: 40)) {
    if (known.contains(item.unitId)) {
      counts.update(item.unitId, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  String? usual;
  var most = 0;
  // A tie goes to the unit seen first, which is the older item's.
  for (final MapEntry(:key, :value) in counts.entries) {
    if (value > most) {
      usual = key;
      most = value;
    }
  }
  return usual ?? byCode('pcs') ?? units.first.id;
});

class QuickItemSheet extends ConsumerStatefulWidget {
  const QuickItemSheet({
    super.key,
    this.initialName = '',
    this.barcode,
    this.code,
    this.weighed = false,
    this.forPurchase = false,
  });

  /// What was typed in the search, so it is never typed twice.
  final String initialName;

  /// What a scanner read that matched nothing. Its field is shown only when
  /// there is one: a cashier typing a name has no barcode to give.
  final String? barcode;

  /// A scale label's PLU, which is how the next label finds the item (M16).
  /// Its field, likewise, only when there is one.
  final String? code;

  /// Opened from a scale label, so the unit starts in kilos.
  final bool weighed;

  /// Opened from a delivery: the cost is the price being bought at, and is
  /// required, and there is no opening stock — the delivery is the stock.
  final bool forPurchase;

  @override
  ConsumerState<QuickItemSheet> createState() => _QuickItemSheetState();
}

class _QuickItemSheetState extends ConsumerState<QuickItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName.trim(),
  );
  late final TextEditingController _barcode = TextEditingController(
    text: widget.barcode ?? '',
  );
  late final TextEditingController _code = TextEditingController(
    text: widget.code ?? '',
  );
  final _sale = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController();
  String? _unitId;

  bool _busy = false;
  String? _failure;

  /// Items already in the shop under this name, once Save has looked.
  List<ItemSummary> _twins = const [];

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _code.dispose();
    _sale.dispose();
    _cost.dispose();
    _stock.dispose();
    super.dispose();
  }

  /// Whether this role is asked what the goods cost, and so what is on the
  /// shelf. See the build method for why.
  bool _asksCost(AppServices services) =>
      widget.forPurchase || services.can(Permission.seeCosts);

  bool _asksStock(AppServices services) =>
      !widget.forPurchase && services.can(Permission.seeCosts);

  void _edited() {
    if (_twins.isEmpty && _failure == null) return;
    setState(() {
      _twins = const [];
      _failure = null;
    });
  }

  static String? _blank(String value) =>
      value.trim().isEmpty ? null : value.trim();

  Future<void> _save({bool anyway = false}) async {
    // Before the validate and before any await: two taps inside one frame
    // both reach this line, and it writes a row.
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final unitId =
        _unitId ?? ref.read(_usualUnitProvider(widget.weighed)).valueOrNull;
    if (unitId == null) {
      setState(() => _failure = s.commonRequired);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final firm = await ref.read(firmProvider.future);
      if (firm == null) throw StateError('This phone has no shop yet.');
      final cost = _asksCost(services) ? Rate.tryParse(_cost.text) : null;

      // Built field for field as the full editor builds it. The opening rate
      // is the cost typed, or nothing, exactly as there; the writer turns a
      // quantity at that rate into a stock-ledger row, an opening-stock
      // entry in the books and the item's first average cost.
      final draft = ItemDraft(
        name: _name.text.trim(),
        baseUnitId: unitId,
        saleRate: Rate.tryParse(_sale.text) ?? Rate.zero,
        code: _blank(_code.text),
        barcode: _blank(_barcode.text),
        purchaseRate: cost,
        openingStock: _asksStock(services)
            ? Qty.tryParse(_stock.text) ?? Qty.zero
            : Qty.zero,
        openingRate: cost ?? Rate.zero,
      );

      if (!anyway) {
        final twins = await itemTwins(services.queries, firm.id, draft.name);
        if (twins.isNotEmpty) {
          if (mounted) {
            setState(() {
              _twins = twins;
              _busy = false;
            });
          }
          return;
        }
      }

      final id = await services.catalogue.addItem(services.actorNow(), draft);
      final item = await services.queries.itemById(firm.id, id);
      container.bumpRefresh();
      navigator.pop(item);
    } on Object catch (error) {
      // A barcode or code another item already carries is refused by the
      // writer, in words naming that item. Said here as it is.
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
    final services = ref.watch(appServicesProvider);
    final units = ref.watch(unitsProvider).valueOrNull;
    final usual = ref.watch(_usualUnitProvider(widget.weighed));

    // What the goods cost is asked of whoever may see it (M9's `seeCosts`:
    // the owner, a manager, the munshi), and on a delivery, where the cost is
    // the whole point. A cashier is not asked for a number his role is not
    // allowed to read — and so not for the opening stock either, because the
    // books value stock at its cost, and a quantity typed without one would
    // put goods on the balance sheet at nothing. His new item goes on the
    // bill with no stock; the sale takes the shelf below zero, which the
    // stock summary shows the owner, who records the delivery that should
    // have been there.
    final asksCost = _asksCost(services);
    final asksStock = _asksStock(services);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.itemsAdd,
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
            if (units == null || usual.isLoading)
              const BlSkeletonList(rows: 3)
            else ...[
              BlField(
                controller: _name,
                label: s.itemName,
                hint: s.itemNameHint,
                autofocus: _name.text.isEmpty,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _edited(),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? s.commonRequired : null,
              ),
              if (widget.barcode != null) ...[
                const SizedBox(height: BlTokens.space3),
                BlField(
                  controller: _barcode,
                  label: s.itemBarcode,
                  onChanged: (_) => _edited(),
                ),
              ],
              if (widget.code != null) ...[
                const SizedBox(height: BlTokens.space3),
                BlField(
                  controller: _code,
                  label: s.itemCode,
                  onChanged: (_) => _edited(),
                ),
              ],
              const SizedBox(height: BlTokens.space3),
              BlField(
                controller: _sale,
                label: s.itemSalePrice,
                numeric: true,
                // The name came with the search, so the price is the next
                // thing to type.
                autofocus: _name.text.isNotEmpty,
                textInputAction: TextInputAction.next,
                // Required, as in the full editor. An item without a price
                // rings up at nothing, and nobody notices until the day's
                // takings are short.
                validator: (v) =>
                    Rate.tryParse(v ?? '') == null ? s.commonRequired : null,
              ),
              const SizedBox(height: BlTokens.space3),
              DropdownButtonFormField<String>(
                initialValue: _unitId ?? usual.valueOrNull,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.itemUnit),
                items: [
                  for (final u in units)
                    DropdownMenuItem(
                      value: u.id,
                      child: Text(
                        '${u.name} (${u.code})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _unitId = v),
              ),
              if (asksCost) ...[
                const SizedBox(height: BlTokens.space3),
                BlField(
                  controller: _cost,
                  label: widget.forPurchase
                      ? s.quickItemBuyingAt
                      : s.itemPurchasePrice,
                  numeric: true,
                  textInputAction: asksStock
                      ? TextInputAction.next
                      : TextInputAction.done,
                  validator: widget.forPurchase
                      ? (v) {
                          final rate = Rate.tryParse(v ?? '');
                          return rate == null || rate.inMilliPaisa <= 0
                              ? s.commonRequired
                              : null;
                        }
                      : null,
                ),
              ],
              if (asksStock) ...[
                const SizedBox(height: BlTokens.space3),
                BlField(
                  controller: _stock,
                  label: s.itemOpeningStock,
                  numeric: true,
                  decimals: 3,
                  textInputAction: TextInputAction.done,
                ),
              ],
              if (!asksCost) ...[
                const SizedBox(height: BlTokens.space3),
                Text(
                  s.quickItemNoCost,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
              ],
              if (_twins.isNotEmpty) ...[
                const SizedBox(height: BlTokens.space4),
                _Twins(
                  twins: _twins,
                  busy: _busy,
                  onUse: (item) => Navigator.of(context).pop(item),
                  onAddAnyway: () => unawaited(_save(anyway: true)),
                ),
              ],
              if (_failure != null) ...[
                const SizedBox(height: BlTokens.space3),
                Text(
                  _failure!,
                  style: TextStyle(fontSize: 13, color: t.danger),
                ),
              ],
              const SizedBox(height: BlTokens.space5),
              BlButton(
                label: s.actionSave,
                icon: Icons.check,
                big: true,
                busy: _busy,
                onPressed: _busy ? null : () => unawaited(_save()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The items this might already be, each a tap from being used instead.
class _Twins extends StatelessWidget {
  const _Twins({
    required this.twins,
    required this.busy,
    required this.onUse,
    required this.onAddAnyway,
  });

  final List<ItemSummary> twins;
  final bool busy;
  final ValueChanged<ItemSummary> onUse;
  final VoidCallback onAddAnyway;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Container(
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.quickItemTwins,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.warning,
            ),
          ),
          const SizedBox(height: BlTokens.space1),
          Text(
            s.quickItemTwinsHint,
            style: TextStyle(fontSize: 13, color: t.warning),
          ),
          const SizedBox(height: BlTokens.space2),
          for (final item in twins)
            InkWell(
              onTap: () => onUse(item),
              borderRadius: BorderRadius.circular(BlTokens.radiusSm),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: BlTokens.touchMin,
                ),
                padding: const EdgeInsets.symmetric(vertical: BlTokens.space2),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 20, color: t.ink),
                    const SizedBox(width: BlTokens.space2),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: BlTokens.space2),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          item.saleRate.amountOnly,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                            fontFeatures: BlTokens.tabular,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.quickAddAnyway,
            kind: BlButtonKind.secondary,
            onPressed: busy ? null : onAddAnyway,
          ),
        ],
      ),
    );
  }
}
