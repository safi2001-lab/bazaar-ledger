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
/// pixels". Neither is what a phone uses. Roboto is.
///
/// The files live in the repository (test/support/fonts, Apache 2.0, licence
/// beside them) rather than being borrowed from the Flutter SDK's cache: the
/// cache had them on the bench and not on the CI runner, and every layout
/// test in CI failed in setUp. Checked in, the bench, CI and the phone
/// measure the same letters wherever the suite runs.
///
/// Regular, medium and bold, so a bold total is measured as bold.
Future<void> loadRealFont() async {
  final loader = FontLoader('Roboto');
  for (final name in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    final file = File(
      ['test', 'support', 'fonts', name].join(Platform.pathSeparator),
    );
    if (!file.existsSync()) {
      fail(
        'Roboto was not found at ${file.absolute.path}. The layout tests '
        'measure against it; measuring against the test font would make '
        'every layout assertion meaningless.',
      );
    }
    loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}
