import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// What this phone remembers about the reports (M33): the ones starred as
/// favourites, the last few opened, and the period each was last read for.
/// Since M67 also how each report's columns are arranged, and the ageing
/// buckets the shop reads its udhaar in.
///
/// Kept beside the language and theme in a small file of its own, the way
/// `AppPreferences` is, and not in the books: a favourite is how one person
/// likes their phone, it is not the shop's, and it must not travel to the
/// other counters with a sync or come back with somebody else's backup.
final class ReportShelf {
  const ReportShelf({
    this.favourites = const [],
    this.recent = const [],
    this.periods = const {},
    this.columns = const {}, // M67
    this.ageing = AgeingBuckets.standard, // M67
  });

  /// Starred, in the order they were starred.
  final List<ReportKind> favourites;

  /// Most recently opened first, at most [recentLimit].
  final List<ReportKind> recent;

  /// The period each report was last read for: a [DatePreset] name, or for
  /// picked dates `custom:YYYY-MM-DD:YYYY-MM-DD`.
  final Map<ReportKind, String> periods;

  /// Each report's columns as the shop arranged them (M67): shown, hidden
  /// and moved, never its column filters, which are the screen's and a
  /// saved view's.
  final Map<ReportKind, TableArrangement> columns;

  /// Where the ageing reports cut their buckets (M67).
  final AgeingBuckets ageing;

  static const recentLimit = 4;
  static const fileName = 'report_shelf.json';

  bool isFavourite(ReportKind kind) => favourites.contains(kind);

  ReportShelf toggleFavourite(ReportKind kind) => _with(
    favourites: isFavourite(kind)
        ? [
            for (final k in favourites)
              if (k != kind) k,
          ]
        : [...favourites, kind],
  );

  ReportShelf opened(ReportKind kind) => _with(
    recent: [
      kind,
      for (final k in recent)
        if (k != kind) k,
    ].take(recentLimit).toList(),
  );

  /// The same shelf with what is given replaced (M67).
  ReportShelf _with({
    List<ReportKind>? favourites,
    List<ReportKind>? recent,
    Map<ReportKind, String>? periods,
    Map<ReportKind, TableArrangement>? columns,
    AgeingBuckets? ageing,
  }) => ReportShelf(
    favourites: favourites ?? this.favourites,
    recent: recent ?? this.recent,
    periods: periods ?? this.periods,
    columns: columns ?? this.columns,
    ageing: ageing ?? this.ageing,
  );

  /// How [kind]'s columns were last arranged on this phone (M67).
  TableArrangement columnsFor(ReportKind kind) =>
      columns[kind] ?? TableArrangement.none;

  /// Keeps [kind]'s columns as [arrangement] arranges them; a report put
  /// back as it was built is forgotten.
  ReportShelf rememberColumns(ReportKind kind, TableArrangement arrangement) =>
      _with(
        columns: {
          for (final e in columns.entries)
            if (e.key != kind) e.key: e.value,
          if (arrangement.arrangesColumns) kind: arrangement.columnsOnly,
        },
      );

  /// The ageing buckets the shop set (M67).
  ReportShelf withAgeing(AgeingBuckets buckets) =>
      _with(ageing: buckets.isValid ? buckets : AgeingBuckets.standard);

  /// The period [kind] was last read for, or null if it never was.
  ({DatePreset preset, ReportPeriod? custom})? periodFor(ReportKind kind) {
    final saved = periods[kind];
    if (saved == null) return null;
    if (saved.startsWith('custom:')) {
      final parts = saved.split(':');
      final from = parts.length == 3 ? BusinessDate.tryParse(parts[1]) : null;
      final to = parts.length == 3 ? BusinessDate.tryParse(parts[2]) : null;
      if (from == null || to == null || to.value.compareTo(from.value) < 0) {
        return null;
      }
      return (preset: DatePreset.custom, custom: ReportPeriod(from, to));
    }
    final preset = DatePreset.values.where((p) => p.name == saved).firstOrNull;
    return preset == null || preset == DatePreset.custom
        ? null
        : (preset: preset, custom: null);
  }

  ReportShelf rememberPeriod(
    ReportKind kind,
    DatePreset preset, {
    ReportPeriod? custom,
  }) => _with(
    periods: {
      ...periods,
      kind: preset == DatePreset.custom && custom != null
          ? 'custom:${custom.from.value}:${custom.to.value}'
          : preset.name,
    },
  );

  String encode() => jsonEncode({
    'favourites': [for (final k in favourites) k.name],
    'recent': [for (final k in recent) k.name],
    'periods': {for (final e in periods.entries) e.key.name: e.value},
    // M67
    if (columns.isNotEmpty)
      'columns': {
        for (final e in columns.entries) e.key.name: e.value.toJson(),
      },
    if (!ageing.isStandard) 'ageing': ageing.bounds,
  });

  /// Reads what [encode] wrote. A report this build no longer has is
  /// dropped rather than failing the rest, and anything unreadable is an
  /// empty shelf: a favourites file must never stop the reports opening.
  static ReportShelf decode(String text) {
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) return const ReportShelf();
      ReportKind? kind(Object? name) =>
          ReportKind.values.where((k) => k.name == name).firstOrNull;
      List<ReportKind> kinds(Object? list) => [
        if (list is List)
          for (final n in list) ?kind(n),
      ];
      final periods = raw['periods'];
      final columns = raw['columns'];
      final ageing = raw['ageing'];
      final bounds = AgeingBuckets([
        if (ageing is List)
          for (final b in ageing)
            if (b is int) b,
      ]);
      return ReportShelf(
        favourites: kinds(raw['favourites']).toSet().toList(),
        recent: kinds(raw['recent']).toSet().take(recentLimit).toList(),
        periods: {
          if (periods is Map)
            for (final e in periods.entries)
              if (kind(e.key) case final k? when e.value is String)
                k: e.value as String,
        },
        // M67: a report's columns, and the shop's buckets; anything this
        // build cannot read arranges nothing and ages as before.
        columns: {
          if (columns is Map)
            for (final e in columns.entries)
              if (kind(e.key) case final k?)
                if (TableArrangement.fromJson(e.value).columnsOnly case final a
                    when a.arrangesColumns)
                  k: a,
        },
        ageing: bounds.isValid ? bounds : AgeingBuckets.standard,
      );
    } on FormatException {
      return const ReportShelf();
    }
  }

  /// The shelf kept in [directory], or an empty one.
  ///
  /// Read synchronously: a few hundred bytes, read once when the reports
  /// open, and a read that completed at some unknown later moment would
  /// redraw the list under the shopkeeper's thumb.
  static ReportShelf loadFrom(Directory directory) {
    try {
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      if (!file.existsSync()) return const ReportShelf();
      return decode(file.readAsStringSync());
    } on FileSystemException {
      return const ReportShelf();
    }
  }

  /// Writes the shelf into [directory], beside and then renamed over, as
  /// `AppPreferences.save` does, so a kill mid-write leaves the old file.
  void saveTo(Directory directory) {
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    final temporary = File('$path.tmp');
    temporary.writeAsStringSync(encode(), flush: true);
    temporary.renameSync(path);
  }
}

/// Where the shelf is kept: the app's own support directory. Overridden in
/// tests with a directory of their own.
final reportShelfDirectoryProvider = FutureProvider<Directory>(
  (ref) => getApplicationSupportDirectory(),
);

/// The shelf, as the hub and the report screens read and change it.
final reportShelfProvider = NotifierProvider<ReportShelfNotifier, ReportShelf>(
  ReportShelfNotifier.new,
);

class ReportShelfNotifier extends Notifier<ReportShelf> {
  Directory? _directory;

  @override
  ReportShelf build() {
    final directory = ref.watch(reportShelfDirectoryProvider).valueOrNull;
    _directory = directory;
    if (directory == null) return const ReportShelf();
    return ReportShelf.loadFrom(directory);
  }

  void toggleFavourite(ReportKind kind) => _keep(state.toggleFavourite(kind));

  void opened(ReportKind kind) => _keep(state.opened(kind));

  void rememberPeriod(
    ReportKind kind,
    DatePreset preset, {
    ReportPeriod? custom,
  }) => _keep(state.rememberPeriod(kind, preset, custom: custom));

  /// M67: a report's columns as the shop arranged them.
  void rememberColumns(ReportKind kind, TableArrangement arrangement) =>
      _keep(state.rememberColumns(kind, arrangement));

  /// M67: the shop's ageing buckets.
  void setAgeing(AgeingBuckets buckets) => _keep(state.withAgeing(buckets));

  void _keep(ReportShelf next) {
    state = next;
    final directory = _directory;
    if (directory == null) return;
    try {
      next.saveTo(directory);
    } on FileSystemException {
      // A full disk loses a star, never a report. The shelf on screen is
      // still right until the app is closed.
    }
  }
}
