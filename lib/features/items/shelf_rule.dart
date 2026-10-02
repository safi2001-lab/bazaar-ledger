import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Selling below nothing, as the shop and its items say it (M53).
///
/// The rule itself lives in the domain ([NegativeStock]) and is enforced
/// beneath every screen; this file is only how a shopkeeper reads and sets
/// it: the shop's own rule in Settings, an item's in its editor.

/// The shop's own rule, as it stands.
final shopShelfRuleProvider = FutureProvider<NegativeStock>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).shelf.shopRule();
});

/// A rule's name, in the shopkeeper's words.
String shelfRuleName(AppStrings s, NegativeStock rule) => switch (rule) {
  NegativeStock.allow => s.shelfRuleAllow,
  NegativeStock.warn => s.shelfRuleWarn,
  NegativeStock.block => s.shelfRuleBlock,
};

/// What a rule does, in a sentence.
String shelfRuleHint(AppStrings s, NegativeStock rule) => switch (rule) {
  NegativeStock.allow => s.shelfRuleAllowHint,
  NegativeStock.warn => s.shelfRuleWarnHint,
  NegativeStock.block => s.shelfRuleBlockHint,
};

/// The shop's own rule, from Settings. Only the owner may change it; anybody
/// else reads it.
class ShelfRuleScreen extends ConsumerStatefulWidget {
  const ShelfRuleScreen({super.key});

  @override
  ConsumerState<ShelfRuleScreen> createState() => _ShelfRuleScreenState();
}

class _ShelfRuleScreenState extends ConsumerState<ShelfRuleScreen> {
  bool _busy = false;
  String? _failure;

  Future<void> _set(NegativeStock rule) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(appServicesProvider).shelf.setShopRule(rule);
      ref.bumpRefresh();
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final mayChange = services.shelf.canSetRules;
    final current = ref.watch(shopShelfRuleProvider).valueOrNull;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.shelfRuleTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Text(
              s.shelfRuleShopHint,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            if (current != null)
              RadioGroup<NegativeStock>(
                groupValue: current,
                onChanged: (rule) {
                  if (rule != null && mayChange) _set(rule);
                },
                child: Column(
                  children: [
                    for (final rule in NegativeStock.values)
                      RadioListTile<NegativeStock>(
                        value: rule,
                        enabled: mayChange && !_busy,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          shelfRuleName(s, rule),
                          style: TextStyle(fontSize: 15, color: t.ink),
                        ),
                        subtitle: Text(
                          shelfRuleHint(s, rule),
                          style: TextStyle(fontSize: 13, color: t.inkMuted),
                        ),
                      ),
                  ],
                ),
              ),
            if (!mayChange) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.shelfRuleOwnerOnly,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
            ],
          ],
        ),
      ),
    );
  }
}

/// An item's own rule, in its editor: the shop's, or one of the three.
///
/// Null is the shop's, and is the first choice, named with what the shop's
/// rule is today so nobody has to go and look. Read-only to anybody but the
/// owner, who is the one the rule is for.
class ShelfRuleField extends ConsumerWidget {
  const ShelfRuleField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final NegativeStock? value;
  final ValueChanged<NegativeStock?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayChange = ref.watch(appServicesProvider).shelf.canSetRules;
    final shop = ref.watch(shopShelfRuleProvider).valueOrNull;
    final chosen = value ?? shop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<NegativeStock?>(
          // Keyed by the value, so a rule set from outside (the shop's
          // arriving a frame late) is what the field shows.
          key: ValueKey(('shelf-rule', value, shop)),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.shelfRuleTitle),
          items: [
            DropdownMenuItem<NegativeStock?>(
              child: Text(
                s.shelfRuleShop(shop == null ? '' : shelfRuleName(s, shop)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final rule in NegativeStock.values)
              DropdownMenuItem<NegativeStock?>(
                value: rule,
                child: Text(shelfRuleName(s, rule)),
              ),
          ],
          onChanged: mayChange ? onChanged : null,
        ),
        if (chosen != null) ...[
          const SizedBox(height: BlTokens.space1),
          Text(
            mayChange ? shelfRuleHint(s, chosen) : s.shelfRuleOwnerOnly,
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
        ],
      ],
    );
  }
}

/// "Below nothing", in red, for a list row (M53): sold past what it had.
class BelowNothingChip extends StatelessWidget {
  const BelowNothingChip({super.key});

  @override
  Widget build(BuildContext context) => BlChip(
    AppStrings.of(context).itemsBelowNothing,
    tone: BlChipTone.bad,
    icon: Icons.remove_circle_outline,
  );
}
