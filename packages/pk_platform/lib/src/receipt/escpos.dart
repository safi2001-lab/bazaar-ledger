import 'dart:convert';
import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';

/// Text alignment for [EscPos.align].
enum EscPosAlign { left, centre, right }

/// Which of the printer's two built-in fonts to print in.
///
/// The column count depends on it, and so does whether the receipt is
/// readable at all: an 80mm head is 576 dots, and the same head gives a
/// different number of columns in each font.
enum EscPosFont { a, b }

/// Builds an ESC/POS byte stream.
///
/// Every command here is from the Epson ESC/POS reference and is supported by
/// the clone controllers that Black Copper, Speed-X and Xprinter units ship
/// with — the Rs 6,800 to Rs 12,000 band that Pakistani counters actually buy.
/// Nothing exotic is used, because a receipt that only prints on an Epson
/// TM-T82 is a receipt that does not print.
final class EscPos {
  EscPos();

  final BytesBuilder _out = BytesBuilder(copy: false);

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  Uint8List get bytes => _out.toBytes();

  /// ESC @ — reset the printer to a known state.
  ///
  /// Always first. A printer left in double-width by the last job will happily
  /// print this one in double-width too.
  EscPos initialise() => _raw([_esc, 0x40]);

  /// ESC t n — select a code page. 0 is PC437; the Latin fast path needs
  /// nothing more, and anything that is not Latin goes through [raster].
  EscPos codePage(int page) => _raw([_esc, 0x74, page]);

  /// ESC M n — select the built-in font. 0 is Font A, 1 is Font B.
  ///
  /// Sent explicitly, always, because the column count the whole layout is
  /// built on depends on it and the default is not the same on every machine.
  /// An 80mm head is 576 dots; Font A at 12 dots wide gives 48 columns and
  /// Font B at 9 gives 64, but the clones this ships against are not
  /// consistent — several are 42 columns in Font A. A layout that assumes 48
  /// and meets a printer sitting in a 42-column font wraps EVERY line, and
  /// the receipt is unreadable rather than slightly wrong.
  ///
  /// Selecting it does not make the assumption true on every machine, which
  /// is why the column count is also a per-printer setting. What it does is
  /// make the printer's state ours rather than whatever the last job left.
  EscPos font(EscPosFont f) =>
      _raw([_esc, 0x4D, f == EscPosFont.a ? 0 : 1]);

  EscPos align(EscPosAlign a) => _raw([
        _esc,
        0x61,
        switch (a) {
          EscPosAlign.left => 0,
          EscPosAlign.centre => 1,
          EscPosAlign.right => 2,
        },
      ]);

  /// ESC E n — emphasised.
  EscPos bold({bool on = true}) => _raw([_esc, 0x45, on ? 1 : 0]);

  /// GS ! n — character size. `1` is one step, so `size(2, 2)` is double
  /// height and double width.
  EscPos size({int width = 1, int height = 1}) {
    if (width < 1 || width > 8 || height < 1 || height > 8) {
      throw ArgumentError('character size steps run from 1 to 8');
    }
    return _raw([_gs, 0x21, ((width - 1) << 4) | (height - 1)]);
  }

  /// ESC - n — underline.
  EscPos underline({bool on = true}) => _raw([_esc, 0x2D, on ? 1 : 0]);

  EscPos text(String value) {
    // The receipt is Roman Urdu in Latin script, which is the whole reason the
    // ASCII fast path covers the common case. Anything outside it is replaced
    // rather than emitted as a byte the printer will render as a random glyph.
    _out.add(latin1.encode(_toPrintableLatin(value)));
    return this;
  }

  EscPos line([String value = '']) => text(value)._raw([_lf]);

  /// Several lines, in order. A convenience so a caller that wrapped a
  /// string does not have to decide how to feed the parts.
  EscPos lines(Iterable<String> values) {
    for (final value in values) {
      line(value);
    }
    return this;
  }

  EscPos feed([int lines = 1]) => _raw([_esc, 0x64, lines]);

  /// GS V 66 n — feed n units, then cut.
  ///
  /// Not the bare `GS V 0`, which is what this used to send. The cutter sits
  /// several millimetres above the print head, so cutting without feeding
  /// first drives the blade through the last lines of the receipt — the
  /// symptom is a bill whose total is missing, or a cut that lands mid-word,
  /// and it looks like a layout bug rather than a cut bug.
  ///
  /// Three units of feed is the figure the Epson reference and the field
  /// reports agree on for an 80mm head.
  EscPos cut({int feedUnits = 3}) => _raw([_gs, 0x56, 0x42, feedUnits]);

  /// GS V 1 — partial cut, for printers that tear rather than guillotine.
  ///
  /// Kept as the bare form: a partial cut leaves the paper attached, so a
  /// blade landing early tears rather than severs and the shopkeeper can
  /// still read what it took.
  EscPos partialCut() => _raw([_gs, 0x56, 0x01]);

  /// ESC p m t1 t2 — kick the cash drawer on pin 2.
  ///
  /// The drawer is wired to the printer, not to the phone, which is why this
  /// belongs in the print job rather than anywhere else.
  EscPos openDrawer() => _raw([_esc, 0x70, 0x00, 0x19, 0xFA]);

  /// GS v 0 — raster bit image.
  ///
  /// This is the Urdu path and the logo path. Printer ROM fonts have no
  /// shaping engine and no bidi, and the community capability database lists
  /// seventy code pages with no Urdu among them, so Nastaliq has to arrive as
  /// pixels or not at all.
  EscPos raster(MonoBitmap bitmap) {
    final widthBytes = bitmap.bytesPerRow;
    if (widthBytes > 0xFFFF || bitmap.height > 0xFFFF) {
      throw ArgumentError('bitmap is too large for a single GS v 0 command');
    }
    // The header declares exactly widthBytes x height bytes of pixels, and
    // the printer counts them. One byte short and it keeps reading: the feed,
    // the cut and the drawer kick are all consumed as image data, and the
    // machine sits waiting for the rest of a picture that will never arrive,
    // mid-job, with a customer at the counter. A logo decoder that rounds its
    // row stride is all it takes.
    final expected = widthBytes * bitmap.height;
    if (bitmap.bits.length != expected) {
      throw ArgumentError(
        'bitmap declares ${bitmap.width}x${bitmap.height} '
        '($expected bytes) but carries ${bitmap.bits.length}',
      );
    }
    _raw([
      _gs,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      bitmap.height & 0xFF,
      (bitmap.height >> 8) & 0xFF,
    ]);
    _out.add(bitmap.bits);
    return this;
  }

  EscPos _raw(List<int> data) {
    _out.add(Uint8List.fromList(data));
    return this;
  }

  /// Folds the handful of non-ASCII characters the app itself emits down to
  /// something a Latin code page can print.
  static String _toPrintableLatin(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      buffer.write(switch (rune) {
        0x2014 || 0x2013 => '-', // em and en dash
        0x2018 || 0x2019 => "'",
        0x201C || 0x201D => '"',
        0x2212 => '-', // minus sign
        0x00A0 => ' ',
        _ when rune >= 0x20 && rune <= 0x7E => String.fromCharCode(rune),
        _ when rune == 0x0A => '\n',
        _ => '?',
      });
    }
    return buffer.toString();
  }
}
