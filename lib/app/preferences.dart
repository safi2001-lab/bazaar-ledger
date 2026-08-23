import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// The two choices that have to survive a restart and exist before the shop
/// does: which language, and light or dark.
///
/// Deliberately a small file rather than a row in `settings`. Settings rows are
/// firm-scoped and the first-run wizard has to be readable before any firm
/// exists — a shopkeeper who cannot read English needs the wizard in Roman
/// Urdu, which is why Roman Urdu is also the default rather than a preference
/// they have to find.
final class AppPreferences {
  AppPreferences({required this.locale, required this.themeMode});

  AppPreferences.defaults()
    : locale = const Locale('ur'),
      themeMode = ThemeMode.system;

  Locale locale;
  ThemeMode themeMode;

  static const String _fileName = 'preferences.json';

  static Future<AppPreferences> load({Directory? directory}) async {
    try {
      final file = await _file(directory);
      if (!file.existsSync()) return AppPreferences.defaults();
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return AppPreferences.defaults();
      return AppPreferences(
        locale: Locale(raw['locale'] as String? ?? 'ur'),
        themeMode: switch (raw['theme']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
      );
    } on Object {
      // A corrupt preferences file must never stop a shopkeeper opening the
      // app. Defaults are always a valid answer.
      return AppPreferences.defaults();
    }
  }

  Future<void> save({Directory? directory}) async {
    final file = await _file(directory);
    final payload = jsonEncode({
      'locale': locale.languageCode,
      'theme': switch (themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    });

    // Written beside, then renamed over. `writeAsString` truncates first, so a
    // kill or a full disk in the middle leaves a half-written file; `load`
    // then catches the parse error and returns defaults, and the shopkeeper
    // who chose English silently gets Roman Urdu back with no idea why. A
    // rename is atomic on every filesystem this app runs on.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    await temporary.rename(file.path);
  }

  static Future<File> _file(Directory? directory) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
