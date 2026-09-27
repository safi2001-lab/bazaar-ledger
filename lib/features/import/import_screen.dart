import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Asks the system for a spreadsheet: its name, which says what kind of
/// file it is, and its bytes. A provider, so a test can hand one in.
final pickImportFileProvider =
    Provider<Future<(String, Uint8List)?> Function()>(
      (ref) => () async {
        // No type filter, as with backups: Android maps a filter to MIME
        // types, and phones label a CSV half a dozen different ways.
        final file = await openFile();
        if (file == null) return null;
        return (file.name, await file.readAsBytes());
      },
    );

enum _Kind { items, parties }

/// Bringing the shop's old item list or khata in from Excel or CSV: pick
/// the file, see what will come in and what will not, then bring it in.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _Kind _kind = _Kind.items;
  ImportPlan<ItemRow>? _items;
  ImportPlan<PartyRow>? _parties;
  ImportResult? _result;
  String? _error;
  bool _busy = false;

  int get _ready => _items?.rows.length ?? _parties?.rows.length ?? 0;

  List<ImportProblem> get _problems =>
      _items?.problems ?? _parties?.problems ?? const [];

  Map<String, String> get _columns =>
      _items?.columns ?? _parties?.columns ?? const {};

  List<String> get _names => [
    for (final (_, r) in _items?.rows ?? const <(int, ItemRow)>[]) r.name,
    for (final (_, r) in _parties?.rows ?? const <(int, PartyRow)>[]) r.name,
  ];

  void _choose(_Kind kind) => setState(() {
    _kind = kind;
    _items = null;
    _parties = null;
    _result = null;
    _error = null;
  });

  Future<void> _pick() async {
    final picked = await ref.read(pickImportFileProvider)();
    if (picked == null || !mounted) return;
    final (name, bytes) = picked;
    setState(() {
      _items = null;
      _parties = null;
      _result = null;
      _error = null;
      try {
        final sheet = readSpreadsheet(bytes, fileName: name);
        switch (_kind) {
          case _Kind.items:
            _items = planItems(sheet);
          case _Kind.parties:
            _parties = planParties(sheet);
        }
      } on ImportRefused catch (e) {
        _error = e.reason;
      }
    });
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final services = ref.read(appServicesProvider);
    try {
      final result = switch ((_items, _parties)) {
        (final items?, _) => await services.import.items(items),
        (_, final parties?) => await services.import.parties(parties),
        _ => const ImportResult(added: 0, skipped: []),
      };
      container.bumpRefresh();
      if (!mounted) return;
      setState(() {
        _result = result;
        _items = null;
        _parties = null;
      });
    } on PermissionDenied catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final planned = _items != null || _parties != null;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.importTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Text(s.importHint, style: TextStyle(fontSize: 14, color: t.ink)),
            const SizedBox(height: BlTokens.space3),
            SegmentedButton<_Kind>(
              segments: [
                ButtonSegment(
                  value: _Kind.items,
                  label: Text(s.importItems),
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: _Kind.parties,
                  label: Text(s.importParties),
                  icon: const Icon(Icons.people_outline),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (k) => _choose(k.single),
            ),
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.importPick,
              icon: Icons.upload_file_outlined,
              kind: BlButtonKind.secondary,
              onPressed: _busy ? null : () => unawaited(_pick()),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: BlTokens.space3),
              Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            if (planned) ...[
              const SizedBox(height: BlTokens.space4),
              BlChip(s.importReady('$_ready'), tone: BlChipTone.good),
              const SizedBox(height: BlTokens.space2),
              Text(
                s.importColumns(_columns.values.join(', ')),
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space2),
              for (final name in _names.take(5))
                Text('· $name', style: TextStyle(fontSize: 14, color: t.ink)),
              if (_problems.isNotEmpty) ...[
                const SizedBox(height: BlTokens.space3),
                BlChip(
                  s.importProblems('${_problems.length}'),
                  tone: BlChipTone.warn,
                ),
                for (final p in _problems.take(20))
                  Text('$p', style: TextStyle(fontSize: 12, color: t.inkMuted)),
              ],
              const SizedBox(height: BlTokens.space4),
              BlButton(
                label: s.importRun('$_ready'),
                icon: Icons.download_done_outlined,
                big: true,
                busy: _busy,
                onPressed: _busy || _ready == 0
                    ? null
                    : () => unawaited(_run()),
              ),
            ],
            if (_result case final result?) ...[
              const SizedBox(height: BlTokens.space4),
              BlChip(
                s.importDone('${result.added}', '${result.skipped.length}'),
                tone: result.skipped.isEmpty
                    ? BlChipTone.good
                    : BlChipTone.warn,
              ),
              for (final p in result.skipped.take(50))
                Text('$p', style: TextStyle(fontSize: 12, color: t.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
