import 'dart:io';

import 'package:bazaar_ledger/app/preferences.dart';
import 'package:bazaar_ledger/design/text_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two choices that exist before the shop does.
///
/// Language and theme are chosen before there is a firm to attach them to, so
/// they live in a small file of their own. That file is written on a handset
/// that can be killed at any moment, so how it is written matters more than
/// what is in it.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bl_prefs');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the default is Roman Urdu, not English', () async {
    final prefs = await AppPreferences.load(directory: dir);
    expect(prefs.locale.languageCode, 'ur');
    expect(prefs.themeMode, ThemeMode.system);
  });

  test('a choice survives a restart', () async {
    await AppPreferences(locale: const Locale('en'), themeMode: ThemeMode.dark)
        .save(directory: dir);

    final reloaded = await AppPreferences.load(directory: dir);
    expect(reloaded.locale.languageCode, 'en');
    expect(reloaded.themeMode, ThemeMode.dark);
  });

  test('the text size survives a restart, and an older file reads as Normal',
      () async {
    await AppPreferences(
      locale: const Locale('ur'),
      themeMode: ThemeMode.light,
      textSize: BlTextSize.large,
    ).save(directory: dir);
    expect(
      (await AppPreferences.load(directory: dir)).textSize,
      BlTextSize.large,
    );

    // Written by a build from before M56: no text size in it at all.
    File('${dir.path}${Platform.pathSeparator}preferences.json')
        .writeAsStringSync('{"locale":"en","theme":"dark"}');
    final older = await AppPreferences.load(directory: dir);
    expect(older.locale.languageCode, 'en');
    expect(older.textSize, BlTextSize.normal);
  });

  test('a corrupt file gives defaults rather than a crash', () async {
    File('${dir.path}${Platform.pathSeparator}preferences.json')
        .writeAsStringSync('{not json at all');

    final prefs = await AppPreferences.load(directory: dir);
    expect(prefs.locale.languageCode, 'ur');
  });

  test('saving never leaves a half-written file behind', () async {
    await AppPreferences(locale: const Locale('en'), themeMode: ThemeMode.dark)
        .save(directory: dir);

    // Written beside and renamed over, so at no point does the real file hold
    // a fragment. `writeAsString` truncates first: a kill in the middle used
    // to leave a file that parses as nothing, and the shopkeeper who chose
    // English silently got Roman Urdu back.
    final names = dir
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList();
    expect(names, ['preferences.json']);
    expect(names.any((n) => n.endsWith('.tmp')), isFalse);
  });

  test('saving twice leaves one valid file', () async {
    for (final locale in const [Locale('en'), Locale('ur'), Locale('en')]) {
      await AppPreferences(locale: locale, themeMode: ThemeMode.light)
          .save(directory: dir);
    }
    final prefs = await AppPreferences.load(directory: dir);
    expect(prefs.locale.languageCode, 'en');
    expect(prefs.themeMode, ThemeMode.light);
    expect(dir.listSync(), hasLength(1));
  });
}
