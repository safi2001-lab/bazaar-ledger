import 'dart:async';
import 'dart:isolate';
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

/// A file bigger than this is read on another isolate, and a sheet longer
/// than [_offThreadRows] is checked on one.
///
/// A five-thousand-line Vyapar export is a megabyte of XML. Parsed on the UI
/// thread of a Rs 25,000 phone it froze the screen for seconds with nothing
/// to say why; on an isolate the screen says it is reading, and stays a
/// screen. Small files stay on the UI thread, where they are done before a
/// frame would notice, and where a widget test's fake clock can see them
/// finish.
const _offThreadBytes = 256 * 1024;
const _offThreadRows = 2000;

// The jobs are top-level on purpose. A closure written inside the screen's
// own methods shares their context, which holds the screen itself, and an
// isolate cannot be sent a widget's state.

Future<T> _work<T>(bool heavy, T Function() job) =>
    heavy ? Isolate.run(job) : Future.sync(job);

Future<({SheetRows sheet, ImportSource? recognised, ImportKind kind})>
_readFile(Uint8List bytes, String name) =>
    _work(bytes.length > _offThreadBytes, () {
      final sheet = readSpreadsheet(bytes, fileName: name);
      return (
        sheet: sheet,
        recognised: recogniseSource(sheet),
        kind: guessKind(sheet),
      );
    });

Future<ImportPlan<ItemRow>> _planItems(
  SheetRows sheet,
  ImportSource source,
  ColumnMap map,
) => _work(
  sheet.rows.length > _offThreadRows,
  () => planItems(sheet, source: source, columns: map),
);

Future<ImportPlan<PartyRow>> _planParties(
  SheetRows sheet,
  ImportSource source,
  ColumnMap map,
  bool? owedAreSuppliers,
) => _work(
  sheet.rows.length > _offThreadRows,
  () => planParties(
    sheet,
    source: source,
    columns: map,
    owedAreSuppliers: owedAreSuppliers,
  ),
);

/// Bringing the shop's old item list or khata in from Excel or CSV — its
/// own, or the one Vyapar or Khatabook exported (M52): say where it came
/// from, pick the file, see what will come in, what will not and why, what
/// the shop already has, then bring it in.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ImportSource _source = ImportSource.other;
  ImportKind _kind = ImportKind.items;

  SheetRows? _sheet;
  ColumnMap? _map;
  ImportSource? _recognised;

  ImportPlan<ItemRow>? _items;
  ImportPlan<PartyRow>? _parties;
  ImportReview? _review;

  /// Who the parties the shop owes are, when their rows do not say. Null
  /// is whatever the source usually means.
  bool? _owedAreSuppliers;
  DuplicateChoice _duplicates = DuplicateChoice.skip;

  ImportResult? _result;
  String? _error;

  /// The columns could not be found, so the shop is asked to choose them.
  bool _needsColumns = false;
  bool _reading = false;
  bool _busy = false;
  (int, int)? _progress;

  /// Bumped by every new plan, so a review of an older one that finishes
  /// late is dropped rather than shown against the wrong rows.
  int _generation = 0;

  /// The Columns fold, opened for the shop when a column has to be chosen
  /// and left open while it is being chosen.
  final _columnsFold = ExpansibleController();

  @override
  void dispose() {
    _columnsFold.dispose();
    super.dispose();
  }

  bool get _planned => _items != null || _parties != null;

  int get _ready => _items?.rows.length ?? _parties?.rows.length ?? 0;

  List<ImportProblem> get _problems =>
      _items?.problems ?? _parties?.problems ?? const [];

  List<ImportProblem> get _caveats =>
      _items?.caveats ?? _parties?.caveats ?? const [];

  List<ImportNote> get _notes => _items?.notes ?? _parties?.notes ?? const [];

  Map<String, String> get _columns =>
      _items?.columns ?? _parties?.columns ?? const {};

  int get _toWrite {
    final duplicates = _review?.matches.length ?? 0;
    return _duplicates == DuplicateChoice.skip ? _ready - duplicates : _ready;
  }

  /// The first few names, for the shop to see its own list in the preview.
  List<String> get _firstNames => [
    for (final (_, r) in (_items?.rows ?? const <(int, ItemRow)>[]).take(5))
      r.name,
    for (final (_, r) in (_parties?.rows ?? const <(int, PartyRow)>[]).take(5))
      r.name,
  ];

  void _clearPlan() {
    _items = null;
    _parties = null;
    _review = null;
    _result = null;
    _error = null;
    _needsColumns = false;
    _generation++;
  }

  void _chooseSource(ImportSource source) {
    setState(() {
      _source = source;
      _kind = source.kind ?? _kind;
      _owedAreSuppliers = null;
      _recognised = null;
    });
    if (_sheet != null) unawaited(_plan(fresh: true));
  }

  void _chooseKind(ImportKind kind) {
    setState(() => _kind = kind);
    if (_sheet != null) unawaited(_plan(fresh: true));
  }

  Future<void> _pick() async {
    final picked = await ref.read(pickImportFileProvider)();
    if (picked == null || !mounted) return;
    final (name, bytes) = picked;
    setState(() {
      _sheet = null;
      _map = null;
      _recognised = null;
      _owedAreSuppliers = null;
      _duplicates = DuplicateChoice.skip;
      _clearPlan();
      _reading = true;
    });
    try {
      final read = await _readFile(bytes, name);
      if (!mounted) return;
      setState(() {
        _sheet = read.sheet;
        // The file says what it is louder than the chip the shop tapped
        // before choosing it.
        if (read.recognised case final source?) {
          _recognised = source;
          _source = source;
          // The shop's own list can be either; its headings say which.
          _kind = source.kind ?? read.kind;
        }
      });
      await _plan(fresh: true);
    } on ImportRefused catch (e) {
      if (mounted) setState(() => _error = _refusal(e));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// The words for a file that cannot be read, in the shop's language.
  String _refusal(ImportRefused e) {
    final s = AppStrings.of(context);
    final why = e.reason.toLowerCase();
    if (why.contains('password')) return s.importRefusedPassword;
    if (why.contains('excel 95')) return s.importRefusedOld;
    return s.importRefusedUnreadable;
  }

  /// Reads the sheet as the chosen list, from scratch when [fresh] (a new
  /// file, another source, another kind), otherwise with the columns as the
  /// shop has pointed them.
  Future<void> _plan({bool fresh = false}) async {
    final sheet = _sheet;
    if (sheet == null) return;
    final source = _source;
    final kind = _kind;
    final owed = _owedAreSuppliers;
    final map = fresh || _map == null
        ? findColumns(sheet, kind, source: source)
        : _map!;
    setState(() {
      _clearPlan();
      _map = map;
    });
    final generation = _generation;
    try {
      if (kind == ImportKind.items) {
        final plan = await _planItems(sheet, source, map);
        if (!mounted || generation != _generation) return;
        setState(() => _items = plan);
        final review = await ref
            .read(appServicesProvider)
            .import
            .reviewItems(plan);
        if (mounted && generation == _generation) {
          setState(() => _review = review);
        }
      } else {
        final plan = await _planParties(sheet, source, map, owed);
        if (!mounted || generation != _generation) return;
        setState(() => _parties = plan);
        final review = await ref
            .read(appServicesProvider)
            .import
            .reviewParties(plan);
        if (mounted && generation == _generation) {
          setState(() => _review = review);
        }
      }
    } on ImportRefused {
      if (!mounted || generation != _generation) return;
      final s = AppStrings.of(context);
      setState(() {
        _needsColumns = true;
        _error = kind == ImportKind.items
            ? s.importNeedItemColumns
            : s.importNeedPartyColumns;
      });
      _columnsFold.expand();
    }
  }

  void _pointField(ImportField field, int? column) {
    final map = _map;
    if (map == null) return;
    setState(() => _map = map.withField(field, column));
    unawaited(_plan());
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = (0, _ready);
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final services = ref.read(appServicesProvider);
    void progress(int done, int total) {
      // Every row would be five thousand rebuilds; every twenty-fifth is
      // smooth enough to watch.
      if (done % 25 == 0 || done == total) {
        if (mounted) setState(() => _progress = (done, total));
      }
    }

    try {
      final result = switch ((_items, _parties)) {
        (final items?, _) => await services.import.items(
          items,
          duplicates: _duplicates,
          onProgress: progress,
        ),
        (_, final parties?) => await services.import.parties(
          parties,
          duplicates: _duplicates,
          onProgress: progress,
        ),
        _ => const ImportResult(added: 0, skipped: []),
      };
      container.bumpRefresh();
      if (!mounted) return;
      setState(() {
        _result = result;
        _items = null;
        _parties = null;
        _review = null;
        _sheet = null;
        _map = null;
        _recognised = null;
      });
    } on PermissionDenied catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  String _sourceName(AppStrings s, ImportSource source) => switch (source) {
    ImportSource.bazaarLedger => s.importSourceOurs,
    ImportSource.vyaparItems => s.importSourceVyaparItems,
    ImportSource.vyaparParties => s.importSourceVyaparParties,
    ImportSource.khatabook => s.importSourceKhatabook,
    ImportSource.other => s.importSourceOther,
  };

  String _guide(AppStrings s) => switch (_source) {
    ImportSource.bazaarLedger => s.importGuideOurs(
      (_kind == ImportKind.items
              ? bazaarLedgerItemHeadings
              : bazaarLedgerPartyHeadings)
          .join(', '),
    ),
    ImportSource.vyaparItems => s.importGuideVyaparItems,
    ImportSource.vyaparParties => s.importGuideVyaparParties,
    ImportSource.khatabook => s.importGuideKhatabook,
    ImportSource.other => s.importGuideOther,
  };

  String _fieldName(AppStrings s, ImportField field) => switch (field) {
    ImportField.name => s.importFieldName,
    ImportField.salePrice => s.importFieldSalePrice,
    ImportField.purchasePrice => s.importFieldPurchasePrice,
    ImportField.wholesalePrice => s.importFieldWholesalePrice,
    ImportField.mrp => s.importFieldMrp,
    ImportField.openingStock => s.importFieldStock,
    ImportField.minStock => s.importFieldMinStock,
    ImportField.unit => s.importFieldUnit,
    ImportField.secondaryUnit => s.importFieldSecondaryUnit,
    ImportField.conversion => s.importFieldConversion,
    ImportField.code => s.importFieldCode,
    ImportField.barcode => s.importFieldBarcode,
    ImportField.category => s.importFieldCategory,
    ImportField.description => s.importFieldDescription,
    ImportField.hsCode => s.importFieldHsCode,
    ImportField.itemType => s.importFieldItemType,
    ImportField.genericName => s.importFieldGeneric, // M54
    ImportField.hsn => s.importFieldHsn,
    ImportField.tax => s.importFieldTax,
    ImportField.phone => s.importFieldPhone,
    ImportField.balance => s.importFieldBalance,
    ImportField.receivable => s.importFieldReceivable,
    ImportField.payable => s.importFieldPayable,
    ImportField.balanceType => s.importFieldBalanceType,
    ImportField.type => s.importFieldType,
    ImportField.city => s.importFieldCity,
    ImportField.address => s.importFieldAddress,
    ImportField.creditLimit => s.importFieldCreditLimit,
    ImportField.gstin => s.importFieldGstin,
  };

  /// One row's problem, in the shop's language.
  String _say(AppStrings s, ImportProblem p) {
    final n = p.name;
    final v = p.value;
    final same = n.toLowerCase() == v.toLowerCase();
    final reason = switch (p.issue) {
      ImportIssue.noName => s.importIssueNoName,
      ImportIssue.inSheetTwice => s.importIssueTwice(n),
      ImportIssue.totalLine => s.importIssueTotal,
      ImportIssue.noSalePrice => s.importIssueNoPrice(n),
      ImportIssue.notAPrice => s.importIssueNotPrice(n, v),
      ImportIssue.notAQuantity => s.importIssueNotQty(n, v),
      ImportIssue.notAnAmount => s.importIssueNotAmount(n, v),
      ImportIssue.negativeStock => s.importIssueNegativeStock(n, v),
      ImportIssue.barcodeMangled => s.importIssueBarcode(n, v),
      ImportIssue.supplierOwed => s.importIssueSupplierOwed(n, v),
      ImportIssue.supplierOwes => s.importIssueSupplierOwes(n, v),
      ImportIssue.alreadyItem =>
        same ? s.importIssueAlreadyItem(n) : s.importIssueAlreadyItemAs(n, v),
      ImportIssue.alreadyParty =>
        same ? s.importIssueAlreadyParty(n) : s.importIssueAlreadyPartyAs(n, v),
      ImportIssue.updated || ImportIssue.other => s.importIssueOther(n, v),
    };
    return s.importLine('${p.line}', reason);
  }

  String _note(AppStrings s, ImportNote note) => switch (note.kind) {
    ImportNoteKind.gstNotCarried => s.importNoteGst(
      '${note.count}',
      note.detail,
    ),
    ImportNoteKind.taxNotRead => s.importNoteTax('${note.count}'),
    ImportNoteKind.hsnNotCarried => s.importNoteHsn('${note.count}'),
    ImportNoteKind.gstinNotKept => s.importNoteGstin('${note.count}'),
    ImportNoteKind.rupeeSign => s.importNoteRupee,
    ImportNoteKind.columnsNotKept => s.importNoteColumns(note.detail),
    ImportNoteKind.services => s.importNoteServices('${note.count}'),
  };

  /// The khata a sheet brings, added up: what customers owe, what the shop
  /// holds for those who paid ahead, and what it owes suppliers and is not
  /// bringing in.
  List<String> _balances(AppStrings s) {
    final parties = _parties;
    if (parties == null) return const [];
    var owedN = 0, aheadN = 0, suppliersN = 0;
    var owed = Money.zero, ahead = Money.zero, suppliers = Money.zero;
    for (final (_, p) in parties.rows) {
      if (p.isSupplier) {
        if (p.owesShop.isNegative) {
          suppliersN++;
          suppliers += p.owesShop.abs;
        }
      } else if (p.balance.isPositive) {
        owedN++;
        owed += p.balance;
      } else if (p.balance.isNegative) {
        aheadN++;
        ahead += p.balance.abs;
      }
    }
    return [
      if (owedN > 0) s.importBalancesOwed('$owedN', '$owed'),
      if (aheadN > 0) s.importBalancesAhead('$aheadN', '$ahead'),
      if (suppliersN > 0)
        s.importBalancesSuppliers('$suppliersN', '$suppliers'),
    ];
  }

  /// The first [show] of [problems], each in words, and how many more.
  /// Only what is shown is worded: a file can have thousands.
  Widget _lines(
    BuildContext context,
    List<ImportProblem> problems, {
    required int show,
  }) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final style = TextStyle(fontSize: 12, color: t.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in problems.take(show))
          Padding(
            padding: const EdgeInsets.only(top: BlTokens.space1),
            child: Text(_say(s, p), style: style),
          ),
        if (problems.length > show)
          Padding(
            padding: const EdgeInsets.only(top: BlTokens.space1),
            child: Text(
              s.importMore('${problems.length - show}'),
              style: style,
            ),
          ),
      ],
    );
  }

  Widget _columnsEditor(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final map = _map!;
    final fields = _kind == ImportKind.items
        ? ImportField.items
        : ImportField.parties;
    String letter(int i) {
      var n = i + 1;
      var out = '';
      while (n > 0) {
        final r = (n - 1) % 26;
        out = String.fromCharCode(65 + r) + out;
        n = (n - 1) ~/ 26;
      }
      return out;
    }

    return _Fold(
      key: ValueKey(('columns', _kind)),
      controller: _columnsFold,
      title: s.importColumnsTitle,
      subtitle: _columns.isEmpty
          ? s.importColumnsHint
          : s.importColumns(_columns.values.join(', ')),
      children: [
        Text(
          s.importColumnsHint,
          style: TextStyle(fontSize: 12, color: t.inkMuted),
        ),
        for (final field in fields) ...[
          const SizedBox(height: BlTokens.space3),
          Text(
            _fieldName(s, field),
            style: TextStyle(fontSize: 13, color: t.ink),
          ),
          DropdownButton<int>(
            key: ValueKey(('importField', field)),
            isExpanded: true,
            value: map.fields[field] ?? -1,
            items: [
              DropdownMenuItem(value: -1, child: Text(s.importColumnNone)),
              for (final (i, heading) in map.headings.indexed)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    heading.trim().isEmpty
                        ? s.importColumnLetter(letter(i))
                        : heading.trim(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) => _pointField(field, v == null || v < 0 ? null : v),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final review = _review;
    final plan = _items ?? _parties;
    final balances = _balances(s);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.importTitle)),
      // A column, not a lazy list: the preview is a page of short lines
      // whose longest lists are cut at twenty, and everything on it has to
      // exist to be read out by a screen reader or found by a test.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BlTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.importHint, style: TextStyle(fontSize: 14, color: t.ink)),
              const SizedBox(height: BlTokens.space4),
              Text(
                s.importFromWhere,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final source in ImportSource.values)
                    ChoiceChip(
                      selected: _source == source,
                      label: Text(_sourceName(s, source)),
                      onSelected: _busy || _reading
                          ? null
                          : (_) => _chooseSource(source),
                    ),
                ],
              ),
              if (_source.kind == null) ...[
                const SizedBox(height: BlTokens.space3),
                SegmentedButton<ImportKind>(
                  segments: [
                    ButtonSegment(
                      value: ImportKind.items,
                      label: Text(s.importItems),
                      icon: const Icon(Icons.inventory_2_outlined),
                    ),
                    ButtonSegment(
                      value: ImportKind.parties,
                      label: Text(s.importParties),
                      icon: const Icon(Icons.people_outline),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _busy || _reading
                      ? null
                      : (k) => _chooseKind(k.single),
                ),
              ],
              const SizedBox(height: BlTokens.space3),
              _Fold(
                key: ValueKey(('guide', _source)),
                title: s.importGuideTitle,
                children: [
                  Text(_guide(s), style: TextStyle(fontSize: 13, color: t.ink)),
                ],
              ),
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.importPick,
                icon: Icons.upload_file_outlined,
                kind: BlButtonKind.secondary,
                busy: _reading,
                onPressed: _busy || _reading ? null : () => unawaited(_pick()),
              ),
              if (_reading) ...[
                const SizedBox(height: BlTokens.space2),
                Text(
                  s.importReading,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
              ],
              if (_recognised case final source?) ...[
                const SizedBox(height: BlTokens.space3),
                BlChip(
                  s.importRecognised(_sourceName(s, source)),
                  icon: Icons.check_circle_outline,
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: BlTokens.space3),
                Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
              ],
              if (_map != null && (_planned || _needsColumns)) ...[
                const SizedBox(height: BlTokens.space3),
                _columnsEditor(context),
              ],
              if (_planned && plan != null) ...[
                const SizedBox(height: BlTokens.space4),
                BlChip(s.importReady('$_ready'), tone: BlChipTone.good),
                const SizedBox(height: BlTokens.space2),
                for (final name in _firstNames)
                  Text('· $name', style: TextStyle(fontSize: 14, color: t.ink)),
                for (final line in balances)
                  Padding(
                    padding: const EdgeInsets.only(top: BlTokens.space2),
                    child: Text(
                      line,
                      style: TextStyle(fontSize: 13, color: t.ink),
                    ),
                  ),
                for (final note in _notes)
                  Padding(
                    padding: const EdgeInsets.only(top: BlTokens.space2),
                    child: Text(
                      _note(s, note),
                      style: TextStyle(fontSize: 13, color: t.warning),
                    ),
                  ),
                if (review != null) ...[
                  for (final MapEntry(key: unit, value: n)
                      in review.unknownUnits.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space2),
                      child: Text(
                        s.importUnknownUnit('$n', unit),
                        style: TextStyle(fontSize: 13, color: t.warning),
                      ),
                    ),
                  for (final MapEntry(key: unit, value: n)
                      in review.secondaryUnits.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space2),
                      child: Text(
                        s.importSecondUnit('$n', unit),
                        style: TextStyle(fontSize: 13, color: t.warning),
                      ),
                    ),
                  // M54: Vyapar's second unit, kept as the item's pack.
                  for (final MapEntry(key: pack, value: n)
                      in review.packs.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space2),
                      child: Text(
                        s.importSecondUnitPack('$n', pack),
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                ],
                if (plan.owedUnsaid > 0) ...[
                  const SizedBox(height: BlTokens.space3),
                  Text(
                    s.importOwedQuestion('${plan.owedUnsaid}'),
                    style: TextStyle(fontSize: 13, color: t.ink),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      for (final suppliers in const [true, false])
                        ChoiceChip(
                          selected:
                              (_owedAreSuppliers ?? _source.owedAreSuppliers) ==
                              suppliers,
                          label: Text(
                            suppliers
                                ? s.importOwedSuppliers
                                : s.importOwedCustomers,
                          ),
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(() => _owedAreSuppliers = suppliers);
                                  unawaited(_plan());
                                },
                        ),
                    ],
                  ),
                ],
                if (review == null) ...[
                  const SizedBox(height: BlTokens.space3),
                  Text(
                    s.importChecking,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                ] else if (review.matches.isNotEmpty) ...[
                  const SizedBox(height: BlTokens.space3),
                  BlChip(
                    s.importDuplicates('${review.matches.length}'),
                    tone: BlChipTone.warn,
                  ),
                  _lines(context, [
                    for (final m in review.matches)
                      ImportProblem.of(
                        m.line,
                        _kind == ImportKind.items
                            ? ImportIssue.alreadyItem
                            : ImportIssue.alreadyParty,
                        name: m.name,
                        value: m.existingName,
                      ),
                  ], show: 10),
                  const SizedBox(height: BlTokens.space2),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      for (final choice in DuplicateChoice.values)
                        ChoiceChip(
                          selected: _duplicates == choice,
                          label: Text(
                            choice == DuplicateChoice.skip
                                ? s.importDuplicatesSkip
                                : s.importDuplicatesUpdate,
                          ),
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _duplicates = choice),
                        ),
                    ],
                  ),
                  if (_duplicates == DuplicateChoice.update)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space2),
                      child: Text(
                        _kind == ImportKind.items
                            ? s.importDuplicatesItemsHint
                            : s.importDuplicatesPartiesHint,
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                    ),
                ],
                if (_problems.isNotEmpty) ...[
                  const SizedBox(height: BlTokens.space3),
                  BlChip(
                    s.importProblems('${_problems.length}'),
                    tone: BlChipTone.warn,
                  ),
                  _lines(context, _problems, show: 20),
                ],
                if (_caveats.isNotEmpty) ...[
                  const SizedBox(height: BlTokens.space3),
                  BlChip(
                    s.importPartial('${_caveats.length}'),
                    tone: BlChipTone.warn,
                  ),
                  _lines(context, _caveats, show: 20),
                ],
                const SizedBox(height: BlTokens.space4),
                if (_progress case (final done, final total)) ...[
                  LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    s.importProgress('$total', '$done'),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space2),
                ],
                BlButton(
                  label: s.importRun('$_toWrite'),
                  icon: Icons.download_done_outlined,
                  big: true,
                  busy: _busy,
                  onPressed: _busy || review == null || _toWrite <= 0
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
                if (result.updated > 0) ...[
                  const SizedBox(height: BlTokens.space2),
                  BlChip(s.importUpdated('${result.updated}')),
                ],
                _lines(context, result.skipped, show: 50),
                if (result.partial.isNotEmpty) ...[
                  const SizedBox(height: BlTokens.space3),
                  BlChip(
                    s.importPartial('${result.partial.length}'),
                    tone: BlChipTone.warn,
                  ),
                  _lines(context, result.partial, show: 50),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled section that opens on a tap, in a card. It is its own
/// Material, so the tap's ripple shows on the card instead of under it.
class _Fold extends StatelessWidget {
  const _Fold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.controller,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final ExpansibleController? controller;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return BlCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          controller: controller,
          title: Text(title),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
          childrenPadding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            0,
            BlTokens.space4,
            BlTokens.space4,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
