import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// What this phone remembers about the reports (M33): the ones starred as
/// favourites, the last few opened, and the period each was last read for.
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
  });

  /// Starred, in the order they were starred.
  final List<ReportKind> favourites;

  /// Most recently opened first, at most [recentLimit].
  final List<ReportKind> recent;

  /// The period each report was last read for: a [DatePreset] name, or for
  /// picked dates `custom:YYYY-MM-DD:YYYY-MM-DD`.
  final Map<ReportKind, String> periods;

  static const recentLimit = 4;
  static const fileName = 'report_shelf.json';

  bool isFavourite(ReportKind kind) => favourites.contains(kind);

  ReportShelf toggleFavourite(ReportKind kind) => ReportShelf(
    favourites: isFavourite(kind)
        ? [
            for (final k in favourites)
              if (k != kind) k,
          ]
        : [...favourites, kind],
    recent: recent,
    periods: periods,
  );

  ReportShelf opened(ReportKind kind) => ReportShelf(
    favourites: favourites,
    recent: [
      kind,
      for (final k in recent)
        if (k != kind) k,
    ].take(recentLimit).toList(),
    periods: periods,
  );

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
  }) => ReportShelf(
    favourites: favourites,
    recent: recent,
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
      return ReportShelf(
        favourites: kinds(raw['favourites']).toSet().toList(),
        recent: kinds(raw['recent']).toSet().take(recentLimit).toList(),
        periods: {
          if (periods is Map)
            for (final e in periods.entries)
              if (kind(e.key) case final k? when e.value is String)
                k: e.value as String,
        },
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
