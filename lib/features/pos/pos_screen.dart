import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/add_offer.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/quick_item_sheet.dart';
import '../scan/scan_screen.dart';
import 'cart.dart';
import 'tender_sheet.dart';

/// What the counter typed, after debouncing. Reset when the screen goes.
///
/// Auto-disposed for a reason that is not tidiness. As a plain global it
/// outlived the counter while the search field's own `TextEditingController`
/// came back empty, and `_CartList` is only built when the query is empty —
/// so a shopkeeper who typed a search, pressed back, and came in again found
/// a stale result list and no sign of the bill they were building.
///
/// Debounced rather than raw because a 20,000-SKU catalogue on an Android Go
/// handset cannot afford a query per keystroke, and because the search field
/// owns its own controller — no keystroke rebuilds the results list.
final posQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// The running total, computed by the same pure function that will post the
/// sale.
///
/// Not a second implementation of the arithmetic. A counter whose displayed
/// total disagrees with the posted total by one paisa is the defect class this
/// whole money layer exists to make impossible, so there is exactly one
/// calculator and both callers use it.
/// The tax standing of the shop and of the customer on the bill, as the
/// posting will read it.
final buyerTaxProvider = FutureProvider.autoDispose
    .family<TaxContext?, String?>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return null;
      return ref
          .watch(appServicesProvider)
          .queries
          .taxContextFor(firm.id, partyId);
    });

final cartPreviewProvider = Provider<CalculatedSale?>((ref) {
  final cart = ref.watch(cartProvider);
  final firm = ref.watch(firmProvider).valueOrNull;
  final units = ref.watch(unitConverterProvider).valueOrNull;
  if (firm == null || cart.isEmpty) return null;

  return AppServices.taxCalculator.calculate(
    SaleDraft(
      lines: [for (final l in cart.lines) ...l.toDrafts(units)],
      partyId: cart.partyId,
      partyName: cart.partyName,
      billDiscount: cart.billDiscount,
      roundToRupee: firm.roundInvoiceToRupee,
    ),
    ref.watch(buyerTaxProvider(cart.partyId)).valueOrNull ??
        TaxContext(
          isSellerRegistered: firm.isSalesTaxRegistered,
          buyerIsRegistered: false,
          buyerIsOnAtl: null,
          province: firm.province,
          pricesIncludeTax: false,
          ruleVersion: 'pk-2026-27-v1',
          hasNamedBuyer: cart.partyId != null,
        ),
  );
});

/// The counter.
///
/// One screen, no dialogs on the billing path, running total always visible.
/// Search at the top because that is where a barcode wedge types; the cart in
/// the middle because that is what the customer is watching; the total and the
/// charge button pinned to the bottom because that is where the thumb is.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  /// A scale label whose PLU no item carries, while the counter is offering
  /// to make that item (M32). Null the rest of the time.
  ({String plu, ScaleData label})? _scaleMiss;

  @override
  void initState() {
    super.initState();
    // Clear whatever the last screen was still saying. A snackbar is anchored
    // to the bottom of the window, which is exactly where the charge button
    // is, and "Item save ho gaya" lingering for four seconds over it means a
    // cashier's tap lands on a message instead of on the sale. Nothing on the
    // billing path may be covered by news about something else.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // Typing again means the label is not what the cashier is dealing with.
    if (_scaleMiss != null) setState(() => _scaleMiss = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(posQueryProvider.notifier).state = value.trim();
    });
  }

  /// A hardware scanner is a keyboard that types fast and presses Enter.
  ///
  /// Rather than fight for focus with a global key handler, the search field
  /// simply stays focused and the wedge types into it; Enter arrives here.
  /// An exact barcode match goes straight onto the bill, so a scan is one
  /// event and no taps.
  Future<void> _onSubmitted(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    final services = ref.read(appServicesProvider);
    final firm = ref.read(firmProvider).valueOrNull;
    if (firm == null) return;

    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var scanned = await services.queries.itemByBarcode(firm.id, text);

    // A weighing scale's own label: the item's PLU and the weight or the
    // price, in one EAN-13 in the 20–29 range (M16).
    if (scanned == null && services.plans.has(PlanFeature.scaleLabels)) {
      final label = parseScaleBarcode(text, await services.scaleFormat());
      if (label != null) {
        final item = await services.queries.itemByCode(firm.id, label.plu);
        if (!mounted) return;
        if (item == null) {
          // Said where the bill is, with the way on beside it: a label for a
          // cut the shop never coded becomes that item, with its PLU, and
          // this weight goes on the bill (M32). It used to be a snackbar
          // that said so and vanished, leaving the cashier to go and find
          // the item editor with the meat still on the scale.
          _clearSearch();
          setState(() => _scaleMiss = (plu: label.plu, label: label));
          return;
        }
        final qty = _scaleQty(item, label);
        if (qty == null || !qty.isPositive) {
          messenger.showSnackBar(
            SnackBar(content: Text(s.posScaleNoPrice(item.name))),
          );
          _clearSearch();
          return;
        }
        ref.read(cartProvider.notifier).add(item, qty: qty);
        _clearSearch();
        return;
      }
    }

    // A medicine pack's GS1 code carries its product, batch and expiry in
    // one symbol. The product is found by its GTIN, and a pack past its date
    // is stopped here, at the scan, before it reaches the bill.
    if (scanned == null) {
      if (parseGs1(text) case final gs1?) {
        scanned =
            await services.queries.itemByBarcode(firm.id, gs1.ean13!) ??
            await services.queries.itemByBarcode(firm.id, gs1.gtin!);
        final today = BusinessDate.now(services.clock);
        if (scanned != null &&
            gs1.expiry != null &&
            gs1.expiry!.value.compareTo(today.value) < 0) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                s.posScannedExpired(gs1.batch ?? '-', gs1.expiry!.value),
              ),
            ),
          );
          _clearSearch();
          return;
        }
      }
    }

    // A phone's IMEI, or any piece sold by its serial number.
    if (scanned == null) {
      final piece = await services.queries.serialOnHand(firm.id, text);
      if (piece != null) {
        final item = await services.queries.itemById(firm.id, piece.itemId);
        if (!mounted || item == null) return;
        final added = ref
            .read(cartProvider.notifier)
            .addSerial(item, lotId: piece.lotId, serial: piece.lotNo);
        if (!added) {
          messenger.showSnackBar(
            SnackBar(content: Text(s.posSerialAlreadyOnBill(piece.lotNo))),
          );
        }
        _clearSearch();
        return;
      }
    }

    final item =
        scanned ??
        (await services.queries.searchItems(
          firm.id,
          query: text,
          limit: 2,
        )).let((rows) => rows.length == 1 ? rows.single : null);

    if (!mounted) return;
    if (item == null) {
      // Nothing on the shelf answers to it, or more than one thing does.
      // What was scanned or typed stays in the field, at once rather than
      // after the debounce, so the results underneath say which — and for
      // nothing at all, offer to make it (M32). The camera's code is put in
      // the field too: it used to vanish without a word, which read as the
      // camera not working.
      //
      // Selected, so the next scan replaces it. A wedge types into whatever
      // is in the field, and appending the next packet's barcode to this one
      // would make that scan miss as well.
      _debounce?.cancel();
      _search.value = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      ref.read(posQueryProvider.notifier).state = text;
      _searchFocus.requestFocus();
      return;
    }
    if (item.tracksSerial) {
      // A phone cannot go on the bill without saying which phone.
      messenger.showSnackBar(SnackBar(content: Text(s.posScanTheSerial)));
      return;
    }

    ref.read(cartProvider.notifier).add(item);
    _clearSearch();
  }

  /// Makes the item a search, a scan or a scale label could not find, and
  /// puts it on the bill: one of it, or what the label weighed (M32).
  ///
  /// Whatever the sheet hands back goes the way a tapped result goes, so an
  /// item the shopkeeper said already existed is treated exactly like one
  /// picked from the list — a phone by serial still has to be scanned.
  Future<void> _quickAdd({
    String name = '',
    String? barcode,
    ({String plu, ScaleData label})? scale,
  }) async {
    final item = await showQuickItemSheet(
      context,
      name: name,
      barcode: barcode,
      code: scale?.plu,
      weighed: scale != null,
    );
    if (item == null || !mounted) return;
    if (item.tracksSerial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).posScanTheSerial)),
      );
      return;
    }
    final weighed = scale == null ? null : _scaleQty(item, scale.label);
    ref
        .read(cartProvider.notifier)
        .add(item, qty: weighed != null && weighed.isPositive ? weighed : null);
    _clearSearch();
  }

  /// The offer under a search that found nothing: what was typed as a name,
  /// or what was scanned as a barcode.
  void _quickAddFromSearch(String query) {
    final barcode = scannedBarcode(query);
    unawaited(
      barcode == null ? _quickAdd(name: query) : _quickAdd(barcode: barcode),
    );
  }

  /// How much a scale label rang up, in the item's own base unit. Grams for
  /// an item kept in grams, kilograms (to the gram) for anything else. A
  /// price label is turned into the quantity that price buys at the rate
  /// the buyer pays, to the gram.
  Qty? _scaleQty(ItemSummary item, ScaleData label) {
    final perGram = item.unitCode.toLowerCase() == 'g';
    if (label.grams case final grams?) {
      return perGram ? Qty.units(grams) : Qty.raw(grams);
    }
    final price = label.price;
    final rate = priceFor(item, ref.read(cartProvider).priceTier);
    if (price == null || rate.inMilliPaisa <= 0) return null;
    // amount (paisa) = qty (thousandths) x rate (milli-paisa) / 1,000,000
    final thousandths =
        (price.inPaisa * 1000000 + rate.inMilliPaisa ~/ 2) ~/ rate.inMilliPaisa;
    return Qty.raw(thousandths);
  }

  /// Opens the camera, and treats what it reads exactly like a wedge scan.
  ///
  /// Deliberately the same path. A barcode is a barcode however it was read,
  /// and routing the camera through its own lookup would be two places for the
  /// UPC-A/EAN-13 normalisation to be got right and one place for it to be
  /// forgotten.
  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code == null || !mounted) return;
    await _onSubmitted(code);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    ref.read(posQueryProvider.notifier).state = '';
    if (_scaleMiss != null) setState(() => _scaleMiss = null);
    _searchFocus.requestFocus();
  }

  void _addToCart(ItemSummary item) {
    if (item.tracksSerial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).posScanTheSerial)),
      );
      return;
    }
    ref.read(cartProvider.notifier).add(item);
    _clearSearch();
  }

  Future<void> _confirmClear() async {
    final s = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.posClearCart),
        content: Text(s.posClearCartConfirm),
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
    if (yes ?? false) {
      ref.read(cartProvider.notifier).clear();
      _clearSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cart = ref.watch(cartProvider);
    final query = ref.watch(posQueryProvider);

    // Wide means sideways: a phone turned over, or the tablet that is the
    // standard Pakistani counter setup.
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.posTitle),
        actions: [
          if (!cart.isEmpty)
            BlIconButton(
              icon: Icons.delete_sweep_outlined,
              label: s.posClearCart,
              colour: t.danger,
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final search = Padding(
              padding: const EdgeInsets.fromLTRB(
                BlTokens.space4,
                BlTokens.space3,
                BlTokens.space4,
                BlTokens.space2,
              ),
              child: BlField(
                controller: _search,
                focusNode: _searchFocus,
                label: s.actionSearch,
                hint: s.posSearchHint,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: _onSubmitted,
                prefix: const Icon(Icons.search, size: 20),
                // The camera when the field is empty, clear when it is not.
                // Both live in the same slot because a cashier reaches for one
                // or the other, never both, and the counter has no room to
                // spare beside a search field on a 720-wide screen.
                suffix: query.isEmpty
                    ? BlIconButton(
                        icon: Icons.qr_code_scanner,
                        label: s.scanTitle,
                        onPressed: _scan,
                      )
                    : BlIconButton(
                        icon: Icons.close,
                        label: s.actionClose,
                        onPressed: _clearSearch,
                      ),
              ),
            );

            final miss = _scaleMiss;
            final list = miss != null
                ? _ScaleMiss(
                    plu: miss.plu,
                    onAdd: () => unawaited(_quickAdd(scale: miss)),
                    onBack: _clearSearch,
                  )
                : query.isEmpty
                ? _CartList(onEmptyTapped: () => _searchFocus.requestFocus())
                : _SearchResults(
                    query: query,
                    onPick: _addToCart,
                    onQuickAdd: _quickAddFromSearch,
                  );

            // Wide means sideways, and sideways the counter is two columns.
            //
            // Stacking them was wrong twice over. A tablet on the counter is
            // the standard Pakistani retail setup and `main.dart` unlocks
            // every orientation on purpose, but landscape on a phone leaves
            // about 160dp of body once the keyboard is up — and the search
            // field and the totals bar together are taller than that. The
            // first attempt at a fix moved the totals bar into a scroll view
            // and was worse than useless: the cart list filled the fold and
            // won every gesture, so the outer scroll never moved and the
            // Charge button could not be reached by any finger. The test that
            // was supposed to catch it called `ensureVisible` first, which
            // scrolled programmatically what a person cannot scroll at all.
            //
            // Side by side, the button is simply always on screen. This is
            // also what every real point-of-sale does in landscape, for the
            // same reason.
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        search,
                        Expanded(child: list),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: box.maxWidth < 900 ? 300 : 360,
                    // The totals scroll if they must; the Charge button never
                    // does. Whatever else is squeezed, taking the money is
                    // reachable.
                    child: const _TotalsBar(scrollable: true),
                  ),
                ],
              );
            }

            return Column(
              children: [
                search,
                Expanded(child: list),
                const _TotalsBar(),
              ],
            );
          },
        ),
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// ---------------------------------------------------------------------------
// Search results
// ---------------------------------------------------------------------------

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.onPick,
    required this.onQuickAdd,
  });

  final String query;
  final ValueChanged<ItemSummary> onPick;

  /// Makes what was typed or scanned into a new item and puts it on the
  /// bill (M32).
  final ValueChanged<String> onQuickAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final results = ref.watch(itemSearchProvider(query));

    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(BlTokens.space4),
        child: BlSkeletonList(rows: 4),
      ),
      error: (error, _) => Center(
        child: BlError(
          title: s.commonSomethingWentWrong,
          message: '$error',
          retryLabel: s.actionRetry,
          onRetry: () => ref.invalidate(itemSearchProvider(query)),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          // The way on is the item itself, made here and put on this bill.
          //
          // This used to open the full item editor, which saved the item and
          // dropped the cashier back on a counter with the search still
          // showing "nothing found" and the item not on the bill — so they
          // searched again, found it, and tapped it. A scanned barcode
          // fared worse: the editor took the digits as the item's NAME.
          final barcode = scannedBarcode(query);
          return Center(
            child: BlEmpty(
              title: s.emptyNoResults,
              message: s.emptyNoResultsHint,
              icon: Icons.search_off,
              action: BlAddOffer(
                label: barcode == null
                    ? s.quickAddItem(query)
                    : s.quickAddBarcode(barcode),
                onTap: () => onQuickAdd(query),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: BlTokens.space4),
          itemCount: items.length,
          // A fixed extent lets the framework skip layout for every row it is
          // not drawing, which is the single biggest list win on a Go handset.
          itemExtent: blRowExtent(context, 64),
          itemBuilder: (context, i) {
            final item = items[i];
            return _ResultRow(
              key: ValueKey(item.id),
              item: item,
              onTap: () => onPick(item),
            );
          },
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.item, required this.onTap});

  final ItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final out = item.tracksStock && !item.stockOnHand.isPositive;

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
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      out
                          ? s.posNoStock
                          : s.posStockLeft(
                              item.stockOnHand.display,
                              item.unitCode,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: out ? t.warning : t.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              // Flexible and scaled, same reason as the khata list: a non-flex
              // child of a Row takes its full natural width first, and at 200%
              // the price left the item name about a third of the space it
              // needed. This one is on the billing path.
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
              const SizedBox(width: BlTokens.space3),
              Icon(Icons.add_circle_outline, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A weighing-scale label for a PLU the shop never coded, and what to do
/// about it (M32).
///
/// In the place the search results take, for the same reason: it is what
/// the counter is dealing with right now. The way back to the bill is a
/// button, and typing or scanning anything else also leaves it.
class _ScaleMiss extends StatelessWidget {
  const _ScaleMiss({
    required this.plu,
    required this.onAdd,
    required this.onBack,
  });

  final String plu;
  final VoidCallback onAdd;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Center(
      child: BlEmpty(
        title: s.posScaleUnknown(plu),
        message: s.quickAddScaleHint,
        icon: Icons.scale_outlined,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlAddOffer(label: s.quickAddCode(plu), onTap: onAdd),
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.quickBackToBill,
              kind: BlButtonKind.ghost,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

class _CartList extends ConsumerWidget {
  const _CartList({required this.onEmptyTapped});

  final VoidCallback onEmptyTapped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return Center(
        child: BlEmpty(
          title: s.posCartEmpty,
          message: s.posCartEmptyHint,
          icon: Icons.shopping_basket_outlined,
          action: BlButton(
            label: s.actionSearch,
            icon: Icons.search,
            kind: BlButtonKind.secondary,
            onPressed: onEmptyTapped,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: BlTokens.space4),
      itemCount: cart.lines.length,
      itemBuilder: (context, i) {
        final line = cart.lines[i];
        return _CartLineTile(key: ValueKey(line.item.id), line: line);
      },
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({super.key, required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final notifier = ref.read(cartProvider.notifier);
    final step = line.item.unitDecimals == 0
        ? Qty.one
        : const Qty.parts(0, 100);

    return Dismissible(
      key: ValueKey('dismiss-${line.item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: BlTokens.space4),
        color: t.dangerSurface,
        child: Icon(Icons.delete_outline, color: t.danger),
      ),
      onDismissed: (_) => notifier.remove(line.item.id),
      child: Padding(
        padding: const EdgeInsets.only(bottom: BlTokens.space2),
        child: BlCard(
          padding: const EdgeInsets.all(BlTokens.space3),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      line.item.name,
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
                  BlMoney(line.net, size: 16, semanticPrefix: line.item.name),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
              Row(
                children: [
                  _StepButton(
                    icon: Icons.remove,
                    label: s.posQty,
                    onTap: () => notifier.setQty(line.item.id, line.qty - step),
                  ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '${s.actionEdit} ${line.item.name}',
                      child: InkWell(
                        onTap: () => _editLine(context, ref),
                        child: Container(
                          height: BlTokens.touchKeypad,
                          alignment: Alignment.center,
                          // Scaled down rather than wrapped. At 200% "1 pcs"
                          // laid out on two lines inside a 56dp box and
                          // painted over the plus and minus buttons and the
                          // row beneath — silently, because a Container does
                          // not clip and Text raises no overflow assertion.
                          // A decimal quantity like "0.750 kg" is a single
                          // unbreakable token far wider than the box, and the
                          // quantity is the number the cashier is checking
                          // against what is on the counter.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: BlQty(
                              line.qty,
                              unit: line.item.unitCode,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add,
                    label: s.posQty,
                    onTap: () => notifier.setQty(line.item.id, line.qty + step),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  // Flexible, so the rate gives way to the quantity rather
                  // than claiming its full natural width first and squeezing
                  // the quantity into what is left.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '× ${line.rate.amountOnly}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          color: t.inkMuted,
                          fontFeatures: BlTokens.tabular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!line.discount.isZero) ...[
                const SizedBox(height: BlTokens.space1),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${s.posDiscount} −${line.discount.amountOnly}',
                    style: TextStyle(fontSize: 12, color: t.money),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editLine(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineEditor(line: line),
    );
  }
}

/// The units this line may be sold in.
///
/// Only what the shop has said is the same thing measured differently, and
/// only where the price carries across exactly. A unit that would need a
/// rounded price is not offered at all rather than offered and refused at the
/// moment of saving the bill — the counter should never present a choice it
/// is going to take back.
///
/// Nothing is shown when there is no choice to make, which is the ordinary
/// case: a kiryana counter sells pieces of what it stocks in pieces.
class _UnitChoice extends ConsumerWidget {
  const _UnitChoice({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitConverterProvider).valueOrNull;
    final all = ref.watch(unitsProvider).valueOrNull;
    if (units == null || all == null) return const SizedBox.shrink();

    final reachable = units.reachableFrom(
      line.item.unitId,
      itemId: line.item.id,
    );
    final offered = [
      for (final u in all)
        if (reachable.contains(u.id) &&
            (u.id == line.sellingUnitId ||
                units.canConvert(
                  Qty.one,
                  fromUnitId: u.id,
                  toUnitId: line.item.unitId,
                  itemId: line.item.id,
                )))
          u,
    ];
    if (offered.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: Wrap(
        spacing: BlTokens.space2,
        runSpacing: BlTokens.space2,
        children: [
          for (final u in offered)
            ChoiceChip(
              label: Text(u.code),
              selected: u.id == line.sellingUnitId,
              onSelected: (_) {
                if (u.id == line.sellingUnitId) return;
                ref
                    .read(cartProvider.notifier)
                    .setUnit(
                      line.item.id,
                      units,
                      unitId: u.id,
                      unitCode: u.code,
                    );
                // The sheet is rebuilt from the cart, so it closes and the
                // cashier taps the line again. Simpler than keeping two
                // copies of the same line in step, and one tap either way.
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        child: Container(
          // The counter's own keypad is 56, not 48. A cashier with dirty
          // hands under a customer's gaze is the constraint this number was
          // measured against.
          width: BlTokens.touchKeypad,
          height: BlTokens.touchKeypad,
          decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          ),
          child: Icon(icon, size: 20, color: t.ink),
        ),
      ),
    );
  }
}

/// Quantity, rate and a line discount, typed rather than stepped.
class _LineEditor extends ConsumerStatefulWidget {
  const _LineEditor({required this.line});

  final CartLine line;

  @override
  ConsumerState<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends ConsumerState<_LineEditor> {
  late final TextEditingController _qty = TextEditingController(
    text: widget.line.qty.display,
  );
  late final TextEditingController _rate = TextEditingController(
    text: widget.line.rate.amountOnly,
  );
  late final TextEditingController _discount = TextEditingController(
    text: widget.line.discount.isZero ? '' : widget.line.discount.amountOnly,
  );

  @override
  void dispose() {
    _qty.dispose();
    _rate.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _apply() {
    final notifier = ref.read(cartProvider.notifier);
    final id = widget.line.item.id;
    final qty = Qty.tryParse(_qty.text);
    final rate = Rate.tryParse(_rate.text);
    final discount = _discount.text.trim().isEmpty
        ? null
        : Money.tryParse(_discount.text);

    if (rate != null) notifier.setRate(id, rate);
    notifier.setLineDiscount(id, discount);
    if (qty != null) notifier.setQty(id, qty);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // Scrollable, like the tender sheet and unlike its previous self.
    //
    // The quantity field is autofocused, so the keyboard is always up when
    // this opens. Sideways that leaves about 160dp, and the confirm and
    // delete buttons were laid out a hundred pixels below it with nothing to
    // scroll: the shopkeeper typed the corrected quantity and had no way to
    // confirm it. The only escapes were dismissing the sheet and losing the
    // edit, or knowing to press system Back first to drop the keyboard.
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
          BlSectionHeader(widget.line.item.name),
          const SizedBox(height: BlTokens.space4),
          BlField(
            controller: _qty,
            label: '${s.posQty} (${widget.line.sellingUnitCode})',
            numeric: true,
            decimals: widget.line.item.unitDecimals,
            autofocus: true,
          ),
          _UnitChoice(line: widget.line),
          const SizedBox(height: BlTokens.space3),
          BlField(controller: _rate, label: s.posRate, numeric: true),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _discount,
            label: s.posLineDiscount,
            numeric: true,
          ),
          const SizedBox(height: BlTokens.space4),
          Row(
            children: [
              Expanded(
                child: BlButton(
                  label: s.posRemoveLine,
                  kind: BlButtonKind.danger,
                  onPressed: () {
                    ref.read(cartProvider.notifier).remove(widget.line.item.id);
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              Expanded(
                child: BlButton(label: s.actionDone, onPressed: _apply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals
// ---------------------------------------------------------------------------

class _TotalsBar extends ConsumerWidget {
  const _TotalsBar({this.scrollable = false});

  /// True in the two-column landscape layout, where this is a side panel
  /// rather than a strip along the bottom.
  ///
  /// The itemised rows scroll if the panel is short — a keyboard sideways
  /// leaves very little of it — and the Charge button is pinned below them so
  /// that whatever else is squeezed out, taking the money is still reachable.
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cart = ref.watch(cartProvider);
    final preview = ref.watch(cartPreviewProvider);

    if (preview == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border(top: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space3,
        BlTokens.space4,
        BlTokens.space4,
      ),
      child: SafeArea(
        top: false,
        child: _Stack(
          scrollable: scrollable,
          rows: [
            _TotalRow(label: s.posSubtotal, amount: preview.subtotal),
            if (!preview.lineDiscountTotal.isZero ||
                !preview.billDiscount.isZero)
              _TotalRow(
                label: s.posDiscount,
                amount: -(preview.lineDiscountTotal + preview.billDiscount),
                colour: t.money,
              ),
            if (!preview.tax.isZero)
              _TotalRow(label: s.posTax, amount: preview.tax),
            if (!preview.furtherTax.isZero)
              _TotalRow(label: s.posTax, amount: preview.furtherTax),
            if (!preview.roundOff.isZero)
              _TotalRow(label: s.posRoundOff, amount: preview.roundOff),
            const SizedBox(height: BlTokens.space2),
            BlAmountRow(
              label: s.posTotal,
              labelStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
              child: BlMoney(
                preview.total,
                size: 28,
                weight: FontWeight.w700,
                withSymbol: true,
                semanticPrefix: s.posTotal,
              ),
            ),
          ],
          action: BlButton(
            label: '${s.posCharge} · ${s.posItemsInCart(cart.lines.length)}',
            icon: Icons.payments_outlined,
            big: true,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const TenderSheet(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The totals, and under them the one button that must never be out of reach.
///
/// Pinned rather than scrolled with the rest, because a Charge button a
/// shopkeeper has to find by scrolling is a Charge button they cannot use with
/// a customer waiting — and, in the layout this replaced, one they could not
/// reach at all: the cart list filled the fold and won every gesture, so the
/// scroll view underneath it never moved.
class _Stack extends StatelessWidget {
  const _Stack({
    required this.scrollable,
    required this.rows,
    required this.action,
  });

  final bool scrollable;
  final List<Widget> rows;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final totals = Column(mainAxisSize: MainAxisSize.min, children: rows);
    if (!scrollable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          totals,
          const SizedBox(height: BlTokens.space3),
          action,
        ],
      );
    }
    // Sideways the button goes FIRST, at the top of the panel.
    //
    // The keyboard overlays the bottom of the screen there, so anything below
    // the fold is behind it. Putting the total and the Charge button in the
    // band the keyboard never reaches is what makes the counter usable with
    // one hand and a customer waiting; the itemised rows can scroll, because
    // nobody is blocked by not seeing the tax line.
    return Column(
      children: [
        action,
        const SizedBox(height: BlTokens.space3),
        Flexible(child: SingleChildScrollView(child: totals)),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount, this.colour});

  final String label;
  final Money amount;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return BlAmountRow(
      padding: const EdgeInsets.symmetric(vertical: 2),
      label: label,
      labelStyle: TextStyle(fontSize: 13, color: t.inkMuted),
      child: BlMoney(
        amount,
        size: 13,
        weight: FontWeight.w500,
        colour: colour ?? t.inkMuted,
        semanticPrefix: label,
      ),
    );
  }
}
