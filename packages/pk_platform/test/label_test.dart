import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// Shelf labels, and whether a scanner could actually read one.
///
/// The temptation with barcode rendering is to assert that some bars came out
/// and move on. That passes on a symbol no scanner on earth can read, which is
/// the only failure mode that matters — a shopkeeper does not find out at the
/// bench, they find out at the counter with a queue, having already stuck
/// three hundred of them on shelves.
///
/// So these check the structure a Code 128 symbol must have: quiet zones, bars
/// that quantise to a whole module, and a module count consistent with the
/// encoding. A symbol failing any of those is unreadable regardless of how
/// convincing it looks.
void main() {
  const renderer = LabelRenderer();
  const spec = LabelSpec();

  group('the symbol itself', () {
    test('bars quantise to a whole module, or no scanner can read them', () {
      // The real risk in this renderer. Bar positions arrive as fractions of
      // the label width and are rounded to dots; if the rounding accumulates,
      // a bar that should be two modules wide comes out three, and the symbol
      // decodes to something else or to nothing.
      final runs = _runsOf(renderer.symbolFor('CHAWAL-5KG', spec));
      final module = _moduleWidth(runs);

      expect(
        module,
        greaterThanOrEqualTo(2),
        reason:
            'the narrowest bar is under two dots. At 203 dpi that is a '
            'quarter of a millimetre, thinner than the print head can place '
            'reliably, and the symbol reads intermittently.',
      );

      // EXACT multiples, not approximate ones.
      //
      // This first allowed a third of a module of slack, and a renderer that
      // rounded every bar to dots independently passed it — which is the
      // defect the whole test exists for. A correct symbol lands on module
      // boundaries by construction; anything else is a renderer that will
      // drift further the moment the label width changes.
      final ragged = [
        for (final run in runs.skip(1).take(runs.length - 2))
          if (run % module != 0) run,
      ];
      expect(
        ragged,
        isEmpty,
        reason:
            'these runs are not whole multiples of a $module-dot module: '
            '$ragged. A scanner measures bar widths in modules; ragged ones '
            'decode as the wrong character or not at all, and the label looks '
            'perfectly convincing while doing it.',
      );
    });

    test('the symbol has quiet zones at both ends', () {
      // Ten modules of white, either side. Without them a scanner cannot find
      // where the symbol starts, and a label butted against the edge of the
      // sticker fails while the same code on the bench succeeds.
      final bitmap = renderer.symbolFor('CHAWAL-5KG', spec);
      final row = _firstRow(bitmap);

      expect(row.first, isFalse, reason: 'the symbol starts in a black bar');
      expect(row.last, isFalse, reason: 'the symbol ends in a black bar');
    });

    test('the module count matches how Code 128 is built', () {
      // Every Code 128 symbol is 11 modules per character plus a 13-module
      // stop. A count that does not fit that shape means characters were
      // dropped or doubled.
      final runs = _runsOf(renderer.symbolFor('12345678', spec));
      final module = _moduleWidth(runs);
      // Without the quiet zones, which are margin rather than data. Counting
      // them was this test's own first mistake.
      final symbol = runs.skip(1).take(runs.length - 2);
      final total = symbol.fold<int>(0, (a, b) => a + b) ~/ module;

      expect(
        (total - 13) % 11,
        0,
        reason:
            'the symbol is $total modules, which is not 11n + 13. It is '
            'not a well-formed Code 128 symbol however it looks.',
      );
    });

    test('every scan line is identical', () {
      // A symbol whose rows disagree by a dot reads at some angles and not
      // others, which is the worst kind of bug: it works when tested.
      final bitmap = renderer.symbolFor('CHAWAL-5KG', spec);
      final first = _firstRow(bitmap);
      for (var y = 1; y < bitmap.height; y++) {
        expect(_rowAt(bitmap, y), first, reason: 'row $y differs from row 0');
      }
    });

    test('different codes make different symbols', () {
      expect(
        _firstRow(renderer.symbolFor('AAA111', spec)),
        isNot(_firstRow(renderer.symbolFor('BBB222', spec))),
      );
    });

    test('the same code makes the same symbol, every time', () {
      expect(
        renderer.symbolFor('CHAWAL-5KG', spec).bits,
        renderer.symbolFor('CHAWAL-5KG', spec).bits,
      );
    });

    test('an empty code is refused rather than printed blank', () {
      // A blank sticker on a shelf is worse than no sticker: it looks like it
      // works.
      expect(
        () => renderer.symbolFor('   ', spec),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the printed label', () {
    test('carries the name, the code and the price', () {
      final bytes = renderer.toBytes(
        const LabelData(
          name: 'Chawal Basmati 5kg',
          code: 'CHAWAL-5KG',
          priceLabel: 'Rs 2,450.00',
        ),
      );
      final text = _text(bytes);

      expect(text, contains('Chawal Basmati 5kg'));
      expect(
        text,
        contains('CHAWAL-5KG'),
        reason:
            'the digits are not under the bars. A scanner that fails '
            'leaves a cashier with nothing to type.',
      );
      expect(text, contains('Rs 2,450.00'));
    });

    test('the symbol goes out as a raster, not as GS k', () {
      // `GS k` support varies: cheap printers accept it, print nothing, and
      // report no error. A raster is the same bytes on every machine.
      final bytes = renderer.toBytes(
        const LabelData(name: 'Chawal', code: 'CHAWAL-5KG'),
      );
      expect(
        _containsSequence(bytes, const [0x1D, 0x76, 0x30]),
        isTrue,
        reason: 'no GS v 0 raster in the output',
      );
      expect(
        _containsSequence(bytes, const [0x1D, 0x6B]),
        isFalse,
        reason: 'the printer is being asked to draw the barcode itself',
      );
    });

    test('a name too long for the label is cut, never wrapped', () {
      // A wrapped name pushes the barcode off the sticker.
      final bytes = renderer.toBytes(
        const LabelData(
          name: 'Chawal Basmati Extra Long Super Premium Sella 5 Kilo Bag',
          code: 'X1',
        ),
      );
      for (final line in _text(bytes).split('\n')) {
        expect(line.length, lessThanOrEqualTo(48));
      }
    });

    test('ten labels are ten labels', () {
      final one = renderer.toBytes(const LabelData(name: 'Chawal', code: 'X1'));
      final ten = renderer.toBytes(
        const LabelData(name: 'Chawal', code: 'X1'),
        copies: 10,
      );
      expect(
        _countSequence(ten, const [0x1D, 0x76, 0x30]),
        10,
        reason:
            'a shopkeeper asked for ten stickers and got '
            '${_countSequence(ten, const [0x1D, 0x76, 0x30])}',
      );
      expect(ten.length, greaterThan(one.length * 5));
    });

    test('zero copies is refused rather than printing nothing quietly', () {
      expect(
        () => renderer.toBytes(
          const LabelData(name: 'Chawal', code: 'X1'),
          copies: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a 58mm roll gets a narrower symbol, not a clipped one', () {
      const narrow = LabelSpec(dots: 384);
      final bitmap = renderer.symbolFor('CHAWAL-5KG', narrow);
      expect(bitmap.width, 384);
      expect(_runsOf(bitmap).fold<int>(0, (a, b) => a + b), 384);
    });

    test('two labels across share the paper, minus a gutter', () {
      const two = LabelSpec(perRow: 2);
      expect(two.labelWidthDots, lessThan(576 ~/ 2 + 1));
      expect(renderer.symbolFor('X1', two).width, two.labelWidthDots);
    });
  });
}

// ---------------------------------------------------------------------------
// Reading the bitmap back
// ---------------------------------------------------------------------------

List<bool> _firstRow(MonoBitmap bitmap) => _rowAt(bitmap, 0);

List<bool> _rowAt(MonoBitmap bitmap, int y) => [
  for (var x = 0; x < bitmap.width; x++)
    (bitmap.bits[y * bitmap.bytesPerRow + (x >> 3)] & (0x80 >> (x & 7))) != 0,
];

/// The run lengths of alternating white and black, left to right.
List<int> _runsOf(MonoBitmap bitmap) {
  final row = _firstRow(bitmap);
  final runs = <int>[];
  var current = row.first;
  var length = 0;
  for (final pixel in row) {
    if (pixel == current) {
      length++;
    } else {
      runs.add(length);
      current = pixel;
      length = 1;
    }
  }
  runs.add(length);
  return runs;
}

/// The narrowest bar, which is one module.
int _moduleWidth(List<int> runs) =>
    runs.skip(1).take(runs.length - 2).reduce((a, b) => a < b ? a : b);

/// The characters a shopkeeper would actually read off the paper.
///
/// Escape sequences are skipped rather than filtered by byte value. `ESC a 1`
/// is 0x1B 0x61 0x01, and 0x61 is the letter 'a' — a naive printable-byte
/// filter invents characters that were never printed, which is how this
/// helper first reported a 52-character line on a 48-column label.
String _text(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1B) {
      // ESC. Most commands here are three bytes (`ESC a n`, `ESC t n`,
      // `ESC M n`, `ESC E n`, `ESC d n`), but `ESC @` is two — and skipping
      // three for it swallowed the first real character of the label, which
      // is how this helper reported a 49-character line on a 48-column one.
      i += (i + 1 < bytes.length && bytes[i + 1] == 0x40) ? 2 : 3;
      continue;
    }
    if (b == 0x1D && i + 7 < bytes.length && bytes[i + 1] == 0x76) {
      // `GS v 0 m xL xH yL yH` then xL+xH*256 bytes per row, yL+yH*256 rows.
      //
      // The length has to be read rather than guessed at. Skipping to the
      // next line feed instead landed in the MIDDLE of the raster — image
      // data contains 0x0A like any other byte — and everything after it was
      // read as text, which lost the code printed under the bars.
      final bytesPerRow = bytes[i + 4] + bytes[i + 5] * 256;
      final rows = bytes[i + 6] + bytes[i + 7] * 256;
      i += 8 + bytesPerRow * rows;
      continue;
    }
    if (b == 0x1D) {
      // Every other GS command this renderer emits is three bytes.
      i += 3;
      continue;
    }
    if (b == 0x0A || (b >= 32 && b < 127)) out.writeCharCode(b);
    i++;
  }
  return out.toString();
}

bool _containsSequence(List<int> bytes, List<int> pattern) =>
    _countSequence(bytes, pattern) > 0;

int _countSequence(List<int> bytes, List<int> pattern) {
  var found = 0;
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) found++;
  }
  return found;
}
