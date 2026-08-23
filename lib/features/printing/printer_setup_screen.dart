import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'printing_providers.dart';

/// Choosing the printer, and finding out how wide the paper is.
///
/// The column width is the whole reason this screen has a test print rather
/// than a Save button and a hope. ESC/POS has no query for it, and 80mm
/// printers ship as both 42 and 48 columns depending on whether the ROM font
/// is A or B — two machines that look identical on a shelf take different
/// receipts. Getting it wrong is not subtle: at 48 on a 42-column printer
/// every total wraps onto the next line and the bill becomes unreadable.
///
/// So the screen prints a ruler exactly as wide as the setting claims, and the
/// shopkeeper looks at the paper. That is the only reliable detector there is.
class PrinterSetupScreen extends ConsumerStatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  ConsumerState<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends ConsumerState<PrinterSetupScreen> {
  final _address = TextEditingController();

  String _kind = 'tcp';
  int _columns = 48;
  int _copies = 1;
  bool _drawer = false;
  String _name = '';

  bool _loaded = false;
  bool _busy = false;
  String? _failure;
  String? _notice;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _adopt(PrinterSettings? saved) {
    if (_loaded) return;
    _loaded = true;
    if (saved == null) return;
    _kind = saved.transportKind;
    _address.text = saved.address;
    _columns = saved.columns;
    _copies = saved.copies;
    _drawer = saved.openDrawerOnCash;
    _name = saved.name;
  }

  PrinterSettings get _draft => PrinterSettings(
    transportKind: _kind,
    address: _address.text.trim(),
    name: _name.isEmpty ? _address.text.trim() : _name,
    columns: _columns,
    copies: _copies,
    openDrawerOnCash: _drawer,
  );

  /// Sends a ruler and a sample money row, so the width can be read off paper.
  Future<void> _testPrint() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    if (_address.text.trim().isEmpty) {
      setState(() => _failure = s.printerAddressNeeded);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
      _notice = null;
    });

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = container.read(appServicesProvider);
      final result = await services.printing.print(
        actor: services.actorNow(),
        settings: _draft,
        // A test print belongs to no bill, and every run is a deliberate act
        // by a person standing at the printer — so it carries the attempt
        // number rather than being deduplicated against the last one.
        jobKey: 'test#${DateTime.now().microsecondsSinceEpoch}',
        bytes: testPrintBytes(_draft),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = result.ok ? s.printerTestSent : null;
        _failure = result.ok ? null : _describe(s, result);
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

  Future<void> _save() async {
    // First statement, before any await. A disabled button only disables on
    // the next build, so two taps in one frame both reach here.
    if (_busy) return;
    final s = AppStrings.of(context);
    if (_address.text.trim().isEmpty) {
      setState(() => _failure = s.printerAddressNeeded);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = container.read(appServicesProvider);
      await services.printing.saveSettings(services.actorNow(), _draft);
      container.invalidate(printerSettingsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(s.printerSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _forget() async {
    if (_busy) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = container.read(appServicesProvider);
      await services.printing.forgetPrinter(services.actorNow());
      container.invalidate(printerSettingsProvider);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  static String _describe(AppStrings s, PrintResult result) =>
      switch (result.outcome) {
        PrintOutcome.printed => s.printerDone,
        PrintOutcome.notSent => s.printerNotSent,
        PrintOutcome.partial => s.printerPartial,
        PrintOutcome.unknown => s.printerUnknownAsk,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final saved = ref.watch(printerSettingsProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.printerTitle)),
      body: SafeArea(
        child: saved.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(printerSettingsProvider),
            ),
          ),
          data: (settings) {
            _adopt(settings);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(BlTokens.space4),
                    children: [
                      BlSectionHeader(s.printerHowItConnects),
                      const SizedBox(height: BlTokens.space2),
                      _TransportChoice(
                        selected: _kind,
                        onChanged: (kind) => setState(() => _kind = kind),
                      ),
                      const SizedBox(height: BlTokens.space4),

                      BlField(
                        label: s.printerAddress,
                        hint: s.printerAddressHint,
                        controller: _address,
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: BlTokens.space4),

                      BlSectionHeader(s.printerWidth),
                      const SizedBox(height: BlTokens.space2),
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 32,
                            label: Text(s.printerColumns32),
                          ),
                          ButtonSegment(
                            value: 42,
                            label: Text(s.printerColumns42),
                          ),
                          ButtonSegment(
                            value: 48,
                            label: Text(s.printerColumns48),
                          ),
                        ],
                        selected: {_columns},
                        onSelectionChanged: (v) =>
                            setState(() => _columns = v.first),
                      ),
                      const SizedBox(height: BlTokens.space2),
                      Text(
                        s.printerWidthHelp,
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                      const SizedBox(height: BlTokens.space3),
                      BlButton(
                        label: s.printerTestPrint,
                        onPressed: _busy ? null : _testPrint,
                        kind: BlButtonKind.secondary,
                      ),
                      const SizedBox(height: BlTokens.space4),

                      SwitchListTile.adaptive(
                        value: _drawer,
                        onChanged: (v) => setState(() => _drawer = v),
                        title: Text(s.printerDrawer),
                        contentPadding: EdgeInsets.zero,
                      ),

                      if (_notice != null) ...[
                        const SizedBox(height: BlTokens.space3),
                        BlCard(child: Text(_notice!)),
                      ],
                      if (_failure != null) ...[
                        const SizedBox(height: BlTokens.space3),
                        BlError(
                          title: s.commonSomethingWentWrong,
                          message: _failure!,
                        ),
                      ],
                      if (settings != null) ...[
                        const SizedBox(height: BlTokens.space4),
                        BlButton(
                          label: s.printerForget,
                          onPressed: _busy ? null : _forget,
                          kind: BlButtonKind.danger,
                        ),
                      ],
                    ],
                  ),
                ),
                _SaveBar(busy: _busy, onSave: _save),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TransportChoice extends ConsumerWidget {
  const _TransportChoice({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final available = ref.watch(availableTransportsProvider);

    // Every transport this build carries is listed, and the ones that cannot
    // work here say so. Hiding them would leave a shopkeeper with a Bluetooth
    // printer wondering why the app has no Bluetooth; offering them without
    // the note fails at the moment they try to print.
    return Column(
      children: [
        for (final entry in const [
          ('tcp', Icons.wifi),
          ('bluetooth', Icons.bluetooth),
          ('usb', Icons.usb),
        ])
          _TransportRow(
            kind: entry.$1,
            icon: entry.$2,
            label: switch (entry.$1) {
              'bluetooth' => s.printerViaBluetooth,
              'usb' => s.printerViaUsb,
              _ => s.printerViaLan,
            },
            usable: available.valueOrNull?.contains(entry.$1) ?? false,
            selected: selected == entry.$1,
            onTap: () => onChanged(entry.$1),
          ),
      ],
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.kind,
    required this.icon,
    required this.label,
    required this.usable,
    required this.selected,
    required this.onTap,
  });

  final String kind;
  final IconData icon;
  final String label;
  final bool usable;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: usable ? onTap : null,
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space4,
          vertical: BlTokens.space3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: usable ? t.ink : t.inkMuted),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: usable ? t.ink : t.inkMuted,
                    ),
                  ),
                  if (!usable)
                    Text(
                      s.printerNotOnThisPhone,
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: 20, color: t.accent),
          ],
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.busy, required this.onSave});

  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    // Edge-to-edge is enforced at targetSdk 36 with no opt-out, so a bottom
    // bar that does not consume the inset renders under the gesture nav.
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space3,
        BlTokens.space4,
        BlTokens.space3,
      ),
      child: SafeArea(
        top: false,
        child: BlButton(label: s.printerSave, onPressed: busy ? null : onSave),
      ),
    );
  }
}
