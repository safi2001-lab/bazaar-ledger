import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/item_editor.dart';
import 'cart.dart';
import 'tender_sheet.dart';

/// What the counter typed, after debouncing.
///
/// Debounced rather than raw because a 20,000-SKU catalogue on an Android Go
/// handset cannot afford a query per keystroke, and because the search field
/// owns its own controller — no keystroke rebuilds the results list.
final posQueryProvider = StateProvider<String>((ref) => '');

/// The running total, computed by the same pure function that will post the
/// sale.
///
/// Not a second implementation of the arithmetic. A counter whose displayed
/// total disagrees with the posted total by one paisa is the defect class this
/// whole money layer exists to make impossible, so there is exactly one
/// calculator and both callers use it.
final cartPreviewProvider = Provider<CalculatedSale?>((ref) {
  final cart = ref.watch(cartProvider);
  final firm = ref.watch(firmProvider).valueOrNull;
  if (firm == null || cart.isEmpty) return null;

  return const SaleCalculator().calculate(
    SaleDraft(
      lines: [for (final l in cart.lines) l.toDraft()],
      partyId: cart.partyId,
      partyName: cart.partyName,
      billDiscount: cart.billDiscount,
      roundToRupee: firm.roundInvoiceToRupee,
    ),
    TaxContext(
      isSellerRegistered: firm.isSalesTaxRegistered,
      buyerIsRegistered: false,
      buyerIsOnAtl: null,
      province: firm.province,
      pricesIncludeTax: false,
      ruleVersion: 'm0',
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

    final scanned = await services.queries.itemByBarcode(firm.id, text);
    final item = scanned ??
        (await services.queries.searchItems(firm.id, query: text, limit: 2))
            .let((rows) => rows.length == 1 ? rows.single : null);

    if (!mounted) return;
    if (item == null) return;

    ref.read(cartProvider.notifier).add(item);
    _clearSearch();
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    ref.read(posQueryProvider.notifier).state = '';
    _searchFocus.requestFocus();
  }

  void _addToCart(ItemSummary item) {
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
                focusNode: _searchFocus,
                label: s.actionSearch,
                hint: s.posSearchHint,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: _onSubmitted,
                prefix: const Icon(Icons.search, size: 20),
                suffix: query.isEmpty
                    ? null
                    : BlIconButton(
                        icon: Icons.close,
                        label: s.actionClose,
                        onPressed: _clearSearch,
                      ),
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? _CartList(onEmptyTapped: () => _searchFocus.requestFocus())
                  : _SearchResults(query: query, onPick: _addToCart),
            ),
            const _TotalsBar(),
          ],
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
  const _SearchResults({required this.query, required this.onPick});

  final String query;
  final ValueChanged<ItemSummary> onPick;

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
          return Center(
            child: BlEmpty(
              title: s.emptyNoResults,
              message: s.emptyNoResultsHint,
              icon: Icons.search_off,
              action: BlButton(
                label: s.itemsAdd,
                icon: Icons.add,
                kind: BlButtonKind.secondary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ItemEditorScreen(initialName: query),
                  ),
                ),
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
              Text(
                item.saleRate.amountOnly,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                  fontFeatures: BlTokens.tabular,
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
    final step = line.item.unitDecimals == 0 ? Qty.one : const Qty.parts(0, 100);

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
                    onTap: () =>
                        notifier.setQty(line.item.id, line.qty - step),
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
                          child: BlQty(
                            line.qty,
                            unit: line.item.unitCode,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add,
                    label: s.posQty,
                    onTap: () =>
                        notifier.setQty(line.item.id, line.qty + step),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  Text(
                    '× ${line.rate.amountOnly}',
                    style: TextStyle(
                      fontSize: 13,
                      color: t.inkMuted,
                      fontFeatures: BlTokens.tabular,
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
  late final TextEditingController _qty =
      TextEditingController(text: widget.line.qty.display);
  late final TextEditingController _rate =
      TextEditingController(text: widget.line.rate.amountOnly);
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
          BlSectionHeader(widget.line.item.name),
          const SizedBox(height: BlTokens.space4),
          BlField(
            controller: _qty,
            label: '${s.posQty} (${widget.line.item.unitCode})',
            numeric: true,
            decimals: widget.line.item.unitDecimals,
            autofocus: true,
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _rate,
            label: s.posRate,
            numeric: true,
          ),
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
                    ref
                        .read(cartProvider.notifier)
                        .remove(widget.line.item.id);
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
  const _TotalsBar();

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Row(
              children: [
                Text(
                  s.posTotal,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BlMoney(
                    preview.total,
                    size: 28,
                    weight: FontWeight.w700,
                    withSymbol: true,
                    semanticPrefix: s.posTotal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlButton(
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
          ],
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: t.inkMuted)),
          const Spacer(),
          BlMoney(
            amount,
            size: 13,
            weight: FontWeight.w500,
            colour: colour ?? t.inkMuted,
            semanticPrefix: label,
          ),
        ],
      ),
    );
  }
}
