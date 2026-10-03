import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Roboto, loaded as the family the app's text asks for, so a "fits on a
/// small phone" test measures what an Android phone draws.
///
/// The test font (Ahem) draws every glyph as a square, wider than any real
/// letter, so a layout test needs a real font. Each suite used to borrow one
/// from the machine it ran on — Segoe UI on Windows, DejaVu Sans on the Linux
/// CI runner — and the two disagree by several pixels a line: every layout
/// passed on the bench and three failed in CI with "overflowed by 37
/// pixels". Neither is what a phone uses. Roboto is, and the Flutter SDK
/// carries it in its own cache on every machine, so the bench, CI and the
/// phone now measure the same letters.
///
/// Regular, medium and bold, so a bold total is measured as bold.
Future<void> loadRealFont() async {
  final fonts = _materialFonts();
  if (fonts == null) {
    fail(
      "Roboto was not found in the Flutter SDK's cache "
      '(bin/cache/artifacts/material_fonts). Run `flutter precache` once; '
      'measuring against the test font would make every layout assertion '
      'meaningless.',
    );
  }
  final loader = FontLoader('Roboto');
  for (final name in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    final file = File('${fonts.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) {
      loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
  }
  await loader.load();
}

/// The SDK's `material_fonts` folder: from FLUTTER_ROOT when the tool set
/// it, otherwise found by walking up from the test runner, which lives in
/// `<sdk>/bin/cache/artifacts/engine/<host>/`.
Directory? _materialFonts() {
  Directory? usable(String path) {
    final dir = Directory(path);
    final regular = File('$path${Platform.pathSeparator}roboto-regular.ttf');
    return regular.existsSync() ? dir : null;
  }

  final sep = Platform.pathSeparator;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final found = usable(
      '$root${sep}bin${sep}cache${sep}artifacts${sep}material_fonts',
    );
    if (found != null) return found;
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final found = usable('${dir.path}${sep}material_fonts');
    if (found != null) return found;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
