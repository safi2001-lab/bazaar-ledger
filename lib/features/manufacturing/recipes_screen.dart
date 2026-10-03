import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../recycle/put_away.dart'; // M60

final recipesProvider = FutureProvider.autoDispose<List<BomView>>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.boms(firm.id);
});

/// Every item that carries stock, for the recipe editor's choices.
final _stockItemsProvider = FutureProvider.autoDispose<List<ItemSummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  final items = await services.queries.searchItems(firm.id, limit: 1000);
  return [
    for (final i in items)
      if (i.tracksStock) i,
  ];
});

/// What the shop makes, and making it (M17).
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.recipesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RecipeEditorScreen()),
        ),
        icon: const Icon(Icons.add),
        label: Text(s.recipesNew),
      ),
      body: SafeArea(
        child: ref
            .watch(recipesProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 3),
              ),
              error: (e, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$e'),
              data: (recipes) => recipes.isEmpty
                  ? BlEmpty(icon: Icons.blender_outlined, title: s.recipesEmpty)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        BlTokens.space4,
                        BlTokens.space4,
                        BlTokens.space4,
                        BlTokens.space10 * 2,
                      ),
                      children: [
                        for (final r in recipes)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: _RecipeCard(recipe: r),
                          ),
                      ],
                    ),
            ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});

  final BomView recipe;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final d = recipe.draft;
    return BlCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecipeEditorScreen(recipe: recipe),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          Text(
            s.recipesMakes(
              d.outputQty.display,
              recipe.outputUnitCode,
              recipe.outputName,
            ),
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          Text(
            recipe.componentNames.values.join(', '),
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.recipesMake,
            icon: Icons.play_arrow_outlined,
            kind: BlButtonKind.secondary,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _MakeSheet(recipe: recipe),
            ),
          ),
        ],
      ),
    );
  }
}

class _MakeSheet extends ConsumerStatefulWidget {
  const _MakeSheet({required this.recipe});

  final BomView recipe;

  @override
  ConsumerState<_MakeSheet> createState() => _MakeSheetState();
}

class _MakeSheetState extends ConsumerState<_MakeSheet> {
  final _runs = TextEditingController(text: '1');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _runs.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final runs = int.tryParse(_runs.text.trim()) ?? 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      final result = await services.manufacturing.assemble(
        services.actorNow(),
        widget.recipe.id,
        runs,
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.recipesMade(
              result.assemblyNo,
              result.plan.outputQty.display,
              widget.recipe.outputName,
            ),
          ),
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          AssemblyRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$e',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space4,
        BlTokens.space4,
        MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.recipe.draft.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(controller: _runs, label: s.recipesRuns, numeric: true),
          if (_error case final error?) ...[
            const SizedBox(height: BlTokens.space2),
            Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.recipesMake,
            icon: Icons.check,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_make()),
          ),
        ],
      ),
    );
  }
}

class _Line {
  _Line({this.itemId, String qty = ''})
    : qty = TextEditingController(text: qty);

  String? itemId;
  final TextEditingController qty;
}

/// Writing or changing a recipe: what it makes, how much, the work on top,
/// and each component per batch.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({this.recipe, super.key});

  final BomView? recipe;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<RecipeEditorScreen> {
  late final _name = TextEditingController(
    text: widget.recipe?.draft.name ?? '',
  );
  late final _outputQty = TextEditingController(
    text: widget.recipe?.draft.outputQty.display ?? '',
  );
  late final _overhead = TextEditingController(
    text: widget.recipe == null || widget.recipe!.draft.overhead.isZero
        ? ''
        : widget.recipe!.draft.overhead.amountOnly,
  );
  late String? _output = widget.recipe?.draft.outputItemId;
  late final List<_Line> _lines = widget.recipe == null
      ? [_Line()]
      : [
          for (final l in widget.recipe!.draft.lines)
            _Line(itemId: l.itemId, qty: l.qty.display),
        ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _outputQty.dispose();
    _overhead.dispose();
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      await services.manufacturing.saveBom(
        services.actorNow(),
        BomDraft(
          name: _name.text,
          outputItemId: _output ?? '',
          outputQty: Qty.tryParse(_outputQty.text) ?? Qty.zero,
          overhead: Money.tryParse(_overhead.text) ?? Money.zero,
          lines: [
            for (final l in _lines)
              if (l.itemId != null)
                BomLineDraft(
                  itemId: l.itemId!,
                  qty: Qty.tryParse(l.qty.text) ?? Qty.zero,
                ),
          ],
        ),
        bomId: widget.recipe?.id,
      );
      container.bumpRefresh();
      navigator.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          AssemblyRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$e',
        };
      });
    }
  }

  Widget _itemChoice(
    List<ItemSummary> items,
    String? value,
    String hint,
    ValueChanged<String?> onChanged,
    Key key,
  ) => DropdownButton<String>(
    key: key,
    isExpanded: true,
    value: items.any((i) => i.id == value) ? value : null,
    hint: Text(hint),
    items: [
      for (final i in items)
        DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.unitCode})')),
    ],
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final items = ref.watch(_stockItemsProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(
          widget.recipe == null ? s.recipesNew : widget.recipe!.draft.name,
        ),
        actions: [PutRecipeAwayButton(recipe: widget.recipe)], // M60
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlField(controller: _name, label: s.recipesName),
            const SizedBox(height: BlTokens.space3),
            Text(
              s.recipesOutput,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            _itemChoice(
              items,
              _output,
              s.recipesPickItem,
              (v) => setState(() => _output = v),
              const ValueKey('output'),
            ),
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: BlField(
                    controller: _outputQty,
                    label: s.recipesBatchMakes,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: BlTokens.space3),
                Expanded(
                  child: BlField(
                    controller: _overhead,
                    label: s.recipesOverhead,
                    numeric: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recipesComponents),
            const SizedBox(height: BlTokens.space2),
            for (final (i, line) in _lines.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: BlCard(
                  child: Column(
                    children: [
                      _itemChoice(
                        items,
                        line.itemId,
                        s.recipesPickItem,
                        (v) => setState(() => line.itemId = v),
                        ValueKey('component-$i'),
                      ),
                      BlField(
                        controller: line.qty,
                        label: s.recipesPerBatch,
                        numeric: true,
                      ),
                    ],
                  ),
                ),
              ),
            BlButton(
              label: s.recipesAddComponent,
              icon: Icons.add,
              kind: BlButtonKind.secondary,
              onPressed: () => setState(() => _lines.add(_Line())),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: BlTokens.space3),
              Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.recipesSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
