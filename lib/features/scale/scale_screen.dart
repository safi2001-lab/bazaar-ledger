import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

final _formatProvider = FutureProvider.autoDispose<ScaleFormat>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).scaleFormat();
});

/// How the shop's weighing scale prints its labels, so the counter can read
/// the item and the weight or price off one scan.
class ScaleScreen extends ConsumerStatefulWidget {
  const ScaleScreen({super.key});

  @override
  ConsumerState<ScaleScreen> createState() => _ScaleScreenState();
}

class _ScaleScreenState extends ConsumerState<ScaleScreen> {
  final _weight = TextEditingController();
  final _price = TextEditingController();
  int _plu = 5;
  bool _paisa = false;
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _weight.dispose();
    _price.dispose();
    super.dispose();
  }

  void _load(ScaleFormat f) {
    if (_loaded) return;
    _loaded = true;
    _weight.text = (f.weightPrefixes.toList()..sort()).join(', ');
    _price.text = (f.pricePrefixes.toList()..sort()).join(', ');
    _plu = f.pluDigits;
    _paisa = f.priceDecimals == 2;
  }

  static Set<String> _prefixes(String text) => {
    for (final p in text.split(RegExp(r'[,\s]+')))
      if (p.trim().isNotEmpty) p.trim(),
  };

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref
          .read(appServicesProvider)
          .setScaleFormat(
            ScaleFormat(
              weightPrefixes: _prefixes(_weight.text),
              pricePrefixes: _prefixes(_price.text),
              pluDigits: _plu,
              priceDecimals: _paisa ? 2 : 0,
            ),
          );
      container.bumpRefresh();
      if (mounted) setState(() => _message = s.scaleSaved);
    } on PermissionDenied catch (e) {
      if (mounted) setState(() => _message = e.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final format = ref.watch(_formatProvider).valueOrNull;
    if (format != null) _load(format);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.scaleTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Text(s.scaleHint, style: TextStyle(fontSize: 14, color: t.ink)),
            const SizedBox(height: BlTokens.space4),
            BlField(controller: _weight, label: s.scaleWeightPrefixes),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _price, label: s.scalePricePrefixes),
            const SizedBox(height: BlTokens.space3),
            Text(
              s.scalePluDigits,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            Wrap(
              spacing: BlTokens.space2,
              children: [
                for (final n in [4, 5, 6])
                  ChoiceChip(
                    selected: _plu == n,
                    label: Text('$n'),
                    onSelected: (_) => setState(() => _plu = n),
                  ),
              ],
            ),
            SwitchListTile.adaptive(
              value: _paisa,
              onChanged: (v) => setState(() => _paisa = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.scalePriceInPaisa),
            ),
            if (_message case final message?) ...[
              const SizedBox(height: BlTokens.space2),
              Text(message, style: TextStyle(fontSize: 14, color: t.ink)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.scaleSave,
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
