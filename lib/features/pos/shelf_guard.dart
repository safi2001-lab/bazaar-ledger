import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'cart.dart';
import 'scheme_book.dart'; // M43

/// Never sold into thin air, at the counter (M53).
///
/// Vyapar sold seven hundred kilos against six hundred and said nothing.
/// Here, the moment a line would take an item below what is on the shelf —
/// added, stepped up, typed in, switched to the carton — the counter says so
/// in the item's own terms:
///
///  * an item set to ask ([NegativeStock.warn]) asks: "Stock sirf 600 kg
///    hai — phir bhi bechein?" Yes keeps the line, and the bill does not ask
///    again for as much or less; no puts the line back as it was;
///  * an item set to refuse ([NegativeStock.block]) is refused in words and
///    the line is put back. The owner changes the item's rule or puts the
///    stock right; nobody at the counter talks past it;
///  * an item that sells on ([NegativeStock.allow]) says nothing.
///
/// Asked again just before the bill is saved ([shelfAllowsBill]), because a
/// bill restored after the app was killed, a quotation put on the counter or
/// a sale on the other till can each change the answer after the line went
/// on. And beneath both, the sale path refuses a blocked item on its own
/// (`refuseBlockedShortfalls`), so no screen that forgets to ask can sell one.
///
/// Its own file so the counter's screens change by a line each: this widget
/// sits around the counter and watches the bill, rather than every way of
/// changing a quantity learning to ask.

/// What the cashier said yes to on this bill: for each item, how much of it
/// in its base unit. Cleared with the bill.
final shelfAcceptedProvider = StateProvider<Map<String, Qty>>(
  (ref) => const {},
);

/// Watches the bill being rung, and asks or refuses as each line grows past
/// the shelf. Draws nothing of its own: it is placed anywhere on the
/// counter's screen, and is there for as long as the counter is.
class ShelfGuard extends ConsumerStatefulWidget {
  const ShelfGuard({super.key, this.child = const SizedBox.shrink()});

  final Widget child;

  @override
  ConsumerState<ShelfGuard> createState() => _ShelfGuardState();
}

class _ShelfGuardState extends ConsumerState<ShelfGuard> {
  /// For each item, how much of it (base unit) has already passed: it was
  /// on the shelf, the cashier said yes, or the item sells on.
  final _passed = <String, Qty>{};

  /// Each item's line as it last passed, to put back on a no.
  final _good = <String, CartLine>{};

  bool _running = false;
  bool _again = false;

  @override
  void initState() {
    super.initState();
    // A bill brought back after the app was killed is taken as it stands;
    // it is asked about once more before it is saved.
    final cart = ref.read(cartProvider);
    _adopt(cart);
    // A yes belongs to the bill it was said on. One left from a bill that
    // ended while this counter was not on screen is let go, after the frame:
    // a provider is not changed while the tree is being built.
    final onBill = {for (final l in cart.lines) l.item.id};
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(shelfAcceptedProvider.notifier);
      final kept = {
        for (final e in notifier.state.entries)
          if (onBill.contains(e.key)) e.key: e.value,
      };
      if (kept.length != notifier.state.length) notifier.state = kept;
    });
  }

  void _adopt(Cart cart) {
    _passed.clear();
    _good.clear();
    final units = ref.read(unitConverterProvider).valueOrNull;
    for (final line in cart.lines) {
      if (_baseOf(line, units) case final base?) {
        _passed[line.item.id] = base;
        _good[line.item.id] = line;
      }
    }
  }

  void _onCart(Cart? before, Cart now) {
    if (now.isEmpty) {
      _passed.clear();
      _good.clear();
      ref.read(shelfAcceptedProvider.notifier).state = const {};
      return;
    }
    // A quotation or a challan put on the counter arrives whole. A
    // challan's goods have already left, and a quotation's are asked about
    // before the bill is saved, so nothing is asked line by line here.
    if (before?.sourceId != now.sourceId) {
      _adopt(now);
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    try {
      do {
        _again = false;
        await _check();
      } while (_again && mounted);
    } finally {
      _running = false;
    }
  }

  /// What [line] takes off the shelf in the item's base unit, or null for a
  /// line that takes nothing (a loose line, a service) or that cannot be
  /// converted — which the sale path refuses in words of its own.
  static Qty? _baseOf(CartLine line, UnitConverter? units) {
    if (line.isLoose || !line.item.tracksStock) return null;
    try {
      return Qty.sum([for (final d in line.toDrafts(units)) d.baseQty]);
    } on Object {
      return null;
    }
  }

  Future<void> _check() async {
    final cart = ref.read(cartProvider);
    final units = ref.read(unitConverterProvider).valueOrNull;
    final lineOf = <String, CartLine>{};
    final grown = <String, Qty>{};
    for (final line in cart.lines) {
      final base = _baseOf(line, units);
      if (base == null) continue;
      final id = line.item.id;
      lineOf[id] = line;
      if (base > (_passed[id] ?? Qty.zero)) {
        grown[id] = base;
      } else {
        // Less than before, or the same: nothing to ask, and this is the
        // line to come back to.
        _passed[id] = base;
        _good[id] = line;
      }
    }
    _passed.removeWhere((id, _) => !lineOf.containsKey(id));
    _good.removeWhere((id, _) => !lineOf.containsKey(id));
    if (grown.isEmpty) return;

    final shelf = await ref
        .read(appServicesProvider)
        .shelf
        .atCounter(grown.keys);
    if (!mounted) return;
    final short = {for (final s in shelfShortfalls(grown, shelf)) s.itemId: s};
    for (final MapEntry(key: id, value: base) in grown.entries) {
      final s = short[id];
      if (s == null || _accepted(s)) {
        _passed[id] = base;
        _good[id] = lineOf[id]!;
        continue;
      }
      final yes = s.rule == NegativeStock.warn
          ? await askToSellShort(context, [s])
          : await _refuse(s);
      if (!mounted) return;
      if (yes) {
        _accept([s]);
        _passed[id] = base;
        _good[id] = lineOf[id]!;
      } else {
        // M53's one change to the cart: the line goes back to how it last
        // stood within the shelf, or off the bill when it never did.
        ref.read(cartProvider.notifier).putBack(id, _good[id]);
      }
    }
  }

  Future<bool> _refuse(ShelfShort s) async {
    await showShelfRefusal(context, [s]);
    return false;
  }

  bool _accepted(ShelfShort s) {
    final said = ref.read(shelfAcceptedProvider)[s.itemId];
    return s.rule == NegativeStock.warn && said != null && s.wanted <= said;
  }

  void _accept(List<ShelfShort> shorts) {
    final notifier = ref.read(shelfAcceptedProvider.notifier);
    notifier.state = {
      ...notifier.state,
      for (final s in shorts) s.itemId: s.wanted,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Cart>(cartProvider, _onCart);
    return widget.child;
  }
}

/// Asks the cashier whether to sell [shorts] below nothing. True on yes.
Future<bool> askToSellShort(
  BuildContext context,
  List<ShelfShort> shorts,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) {
      final s = AppStrings.of(context);
      return AlertDialog(
        icon: const Icon(Icons.inventory_2_outlined),
        title: Text(s.shelfWarnTitle),
        content: _ShortList(
          shorts: shorts,
          headline: (short) => s.shelfWarnAsk(short.onHandWords),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.commonNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.shelfSellAnyway),
          ),
        ],
      );
    },
  );
  return yes ?? false;
}

/// Says why [shorts] will not sell. Nothing to answer but OK.
Future<void> showShelfRefusal(BuildContext context, List<ShelfShort> shorts) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final s = AppStrings.of(context);
        return AlertDialog(
          icon: Icon(Icons.block, color: context.bl.danger),
          title: Text(s.shelfBlockedTitle),
          content: _ShortList(
            shorts: shorts,
            headline: (short) => s.shelfBlocked(short.onHandWords),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.actionOk),
            ),
          ],
        );
      },
    );

class _ShortList extends StatelessWidget {
  const _ShortList({required this.shorts, required this.headline});

  final List<ShelfShort> shorts;
  final String Function(ShelfShort) headline;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final short in shorts) ...[
            Text(headline(short), style: TextStyle(fontSize: 15, color: t.ink)),
            const SizedBox(height: BlTokens.space1),
            Text(
              s.shelfOnBill(short.shelf.itemName, short.wantedWords),
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
          ],
        ],
      ),
    );
  }
}

/// Asks the shelf once more just before a bill or a challan is saved.
///
/// True when it may go: nothing is short, or what is short is set to ask
/// and the cashier said yes — now, or for as much when the line went on.
/// False, after saying why, when a blocked item is short; the sale path
/// would refuse it anyway, and this says so in the shopkeeper's words
/// before anything is written.
///
/// [forChallan] reads the shop floor, which is where a challan's goods are
/// taken from whatever phone writes it. A bill made from challans moves
/// nothing and is not asked about.
Future<bool> shelfAllowsBill(
  BuildContext context,
  WidgetRef ref,
  Cart cart, {
  bool forChallan = false,
}) async {
  final services = ref.read(appServicesProvider);
  final units = ref.read(unitConverterProvider).valueOrNull;
  final List<SaleLineDraft> lines;
  try {
    // M43: the bonus leaves the shelf with the goods that earned it.
    lines = cart.forBooks(units, schemesFor(ref)).lines;
  } on Object {
    // A unit that will not convert is the sale path's to refuse, in words.
    return true;
  }
  final wanted = shelfWanted(lines);
  if (wanted.isEmpty) return true;
  final sources = [?cart.sourceId, ...cart.alsoSourceIds];
  if (!forChallan && await services.shelf.anyChallan(sources)) return true;
  final shelf = await services.shelf.atCounter(
    wanted.keys,
    locationCode: forChallan ? 'MAIN' : null,
  );
  if (!context.mounted) return false;

  final said = ref.read(shelfAcceptedProvider);
  final short = shelfShortfalls(wanted, shelf);
  final blocked = [
    for (final s in short)
      if (s.rule == NegativeStock.block) s,
  ];
  if (blocked.isNotEmpty) {
    await showShelfRefusal(context, blocked);
    return false;
  }
  bool saidYes(ShelfShort s) => switch (said[s.itemId]) {
    final q? => s.wanted <= q,
    null => false,
  };
  final ask = [
    for (final s in short)
      if (!saidYes(s)) s,
  ];
  if (ask.isEmpty) return true;
  final yes = await askToSellShort(context, ask);
  if (yes) {
    final notifier = ref.read(shelfAcceptedProvider.notifier);
    notifier.state = {
      ...notifier.state,
      for (final s in ask) s.itemId: s.wanted,
    };
  }
  return yes;
}
