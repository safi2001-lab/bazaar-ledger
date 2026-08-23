import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/printing_providers.dart';

/// Printing shelf stickers for one item.
///
/// This is the half of a barcode workflow that competitors put behind a higher
/// tier, and it is the half that makes the other half work. A shopkeeper who
/// has entered manufacturer barcodes for three thousand packets still cannot
/// scan the loose rice, the repacked masala, or anything else that came out of
/// a sack — none of those have a code, and the only way they get one is if the
/// shop prints it. Selling the scanning and charging for the labels is selling
/// half a feature.
class LabelPrintSheet extends ConsumerStatefulWidget {
  const LabelPrintSheet({
    super.key,
    required this.name,
    required this.code,
    required this.priceLabel,
  });

  final String name;

  /// The barcode, or failing that the shop's own item code. Null when the item
  /// has neither, which is a thing to say rather than a thing to print blank.
  final String? code;

  final String priceLabel;

  @override
  ConsumerState<LabelPrintSheet> createState() => _LabelPrintSheetState();
}

class _LabelPrintSheetState extends ConsumerState<LabelPrintSheet> {
  int _copies = 1;
  bool _busy = false;
  String? _failure;

  Future<void> _print() async {
    // First statement, before any await. A disabled button only disables on
    // the next build, so two taps in one frame both reach here.
    if (_busy) return;
    final code = widget.code;
    final s = AppStrings.of(context);
    if (code == null) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final settings = await ref.read(printerSettingsProvider.future);
      if (settings == null) {
        setState(() {
          _busy = false;
          _failure = s.labelNoPrinter;
        });
        return;
      }

      final services = ref.read(appServicesProvider);
      final result = await services.printing.print(
        actor: services.actorNow(),
        settings: settings,
        // Every run is a deliberate act by a person standing at the printer
        // with a sheet of stickers, so it carries the moment rather than being
        // deduplicated against the last one. Reprinting labels is normal;
        // reprinting a bill is not.
        jobKey: 'label#$code#${DateTime.now().microsecondsSinceEpoch}',
        bytes: const LabelRenderer().toBytes(
          LabelData(
            name: widget.name,
            code: code,
            priceLabel: widget.priceLabel,
          ),
          copies: _copies,
          spec: LabelSpec(dots: settings.paper.dots),
        ),
      );
      if (!mounted) return;

      if (result.ok) {
        navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(s.labelSent)));
        return;
      }
      setState(() {
        _busy = false;
        _failure = switch (result.outcome) {
          PrintOutcome.notSent => s.printerNotSent,
          PrintOutcome.partial => s.printerPartial,
          PrintOutcome.unknown => s.printerUnknownAsk,
          PrintOutcome.printed => null,
        };
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final code = widget.code;

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        // The keyboard, and then the gesture bar. Edge-to-edge is enforced at
        // targetSdk 36 with no opt-out.
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(s.labelTitle),
          const SizedBox(height: BlTokens.space3),

          if (code == null)
            BlEmpty(icon: Icons.qr_code_2_outlined, title: s.labelNoCode)
          else ...[
            // What the sticker will say, before any paper is used.
            BlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: t.ink),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Courier New'],
                      fontSize: 13,
                      color: t.inkMuted,
                    ),
                  ),
                  const SizedBox(height: BlTokens.space1),
                  Text(
                    widget.priceLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space4),

            Text(s.labelCopies, style: TextStyle(color: t.inkMuted)),
            const SizedBox(height: BlTokens.space2),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 5, label: Text('5')),
                ButtonSegment(value: 10, label: Text('10')),
                ButtonSegment(value: 25, label: Text('25')),
              ],
              selected: {_copies},
              onSelectionChanged: (v) => setState(() => _copies = v.first),
            ),
            const SizedBox(height: BlTokens.space4),

            if (_failure != null) ...[
              BlError(title: s.commonSomethingWentWrong, message: _failure!),
              const SizedBox(height: BlTokens.space3),
            ],

            BlButton(
              label: s.labelPrint,
              icon: Icons.print_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : _print,
            ),
          ],
        ],
      ),
    );
  }
}
