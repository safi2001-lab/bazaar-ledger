import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';

/// A thermal printer in software: it takes the byte stream a real one would
/// be sent and puts it on paper the way an ESC/POS controller does.
///
/// There is no thermal printer on the bench this product is built on, and
/// the shop owner decided (27 Sep 2026) that M2 closes on this emulator
/// rather than wait for one. So it is strict where a real machine is
/// unforgiving: an unknown command, a raster whose byte count does not match
/// its header, or a byte outside the Latin code page is an error here, not
/// a guess. What it cannot know is a particular clone's quirks — which is
/// why the app's test print exists, and why the ledger says so.
///
/// Geometry is the Epson reference for a 203 dpi head: Font A cells are 12
/// by 24 dots, a line is 30 dots, a motion unit is one dot, and the cutter
/// sits [cutterAboveHeadDots] above the print head.
final class VirtualPrinter {
  VirtualPrinter({required this.dots, this.cutterAboveHeadDots = 96});

  /// The printable width: 576 on 80 mm, 384 on 58 mm.
  final int dots;

  /// How far above the head the blade is. About 12 mm on the clones this
  /// ships against; a cut sent without feeding first lands this far up the
  /// paper, through whatever was printed there.
  final int cutterAboveHeadDots;

  static const cellWidth = 12;
  static const cellHeight = 24;
  static const lineDots = 30;

  /// Characters a line holds in Font A at normal width.
  int get columns => dots ~/ cellWidth;

  PrintedPaper print(Uint8List bytes) {
    final page = PrintedPaper._(dots);
    var i = 0;
    var align = 0;
    var widthMul = 1;
    var heightMul = 1;
    var bold = false;
    final pending = StringBuffer();

    void flushLine({required bool feed}) {
      final text = pending.toString();
      pending.clear();
      final perLine = dots ~/ (cellWidth * widthMul);
      // A line longer than the paper wraps, as a real controller does. The
      // layout is meant never to let that happen, so it is recorded.
      final chunks = <String>[];
      for (var s = 0; s < text.length; s += perLine) {
        chunks.add(
          text.substring(
            s,
            s + perLine > text.length ? text.length : s + perLine,
          ),
        );
      }
      if (chunks.isEmpty) chunks.add('');
      if (chunks.length > 1) page.wrapped.add(text);
      for (final chunk in chunks) {
        final h = lineDots * heightMul;
        page._items.add(
          PrintedText._(
            text: chunk,
            y: page.y,
            height: h,
            align: align,
            widthMul: widthMul,
            heightMul: heightMul,
            bold: bold,
          ),
        );
        page.y += h;
      }
      if (!feed) return;
    }

    int take() {
      if (i >= bytes.length) {
        throw const PrinterFault('the job ends in the middle of a command');
      }
      return bytes[i++];
    }

    while (i < bytes.length) {
      final b = take();
      if (b == 0x0A) {
        flushLine(feed: true);
      } else if (b == 0x1B) {
        final c = take();
        switch (c) {
          case 0x40: // ESC @
            align = 0;
            widthMul = 1;
            heightMul = 1;
            bold = false;
            page.initialised = true;
          case 0x74: // ESC t n
            page.codePage = take();
          case 0x4D: // ESC M n
            page.font = take();
          case 0x61: // ESC a n
            align = take();
          case 0x45: // ESC E n
            bold = take() == 1;
          case 0x2D: // ESC - n
            take();
          case 0x64: // ESC d n
            final n = take();
            if (pending.isNotEmpty) flushLine(feed: true);
            page.y += n * lineDots;
          case 0x70: // ESC p m t1 t2
            take();
            take();
            take();
            page.drawerKicks++;
          default:
            throw PrinterFault('unknown command ESC 0x${c.toRadixString(16)}');
        }
      } else if (b == 0x1D) {
        final c = take();
        switch (c) {
          case 0x21: // GS ! n
            final n = take();
            widthMul = (n >> 4) + 1;
            heightMul = (n & 0x0F) + 1;
          case 0x56: // GS V
            final m = take();
            if (pending.isNotEmpty) flushLine(feed: true);
            if (m == 0x41 || m == 0x42) {
              // Feed to the cutting position, then n units more, then cut:
              // the blade is brought down to where the head has reached.
              final n = take();
              page.y += cutterAboveHeadDots + n;
              page.cuts.add(page.y);
            } else {
              // Cut where the blade already is.
              page.cuts.add(page.y - cutterAboveHeadDots);
            }
          case 0x76: // GS v 0 m xL xH yL yH d...
            if (take() != 0x30) throw const PrinterFault('unknown GS v form');
            take(); // m, the scale; always 0 from this app
            final widthBytes = take() | (take() << 8);
            final height = take() | (take() << 8);
            final count = widthBytes * height;
            if (i + count > bytes.length) {
              throw PrinterFault(
                'a raster declares $count bytes and the job has '
                '${bytes.length - i} left: the printer would eat the rest of '
                'the job as pixels and wait for more',
              );
            }
            if (widthBytes * 8 > dots + 7) {
              throw PrinterFault(
                'a raster ${widthBytes * 8} dots wide does not fit a '
                '$dots-dot head',
              );
            }
            if (pending.isNotEmpty) flushLine(feed: true);
            final bitmap = MonoBitmap(
              width: widthBytes * 8,
              height: height,
              bits: Uint8List.fromList(bytes.sublist(i, i + count)),
            );
            i += count;
            page._items.add(
              PrintedRaster._(bitmap: bitmap, y: page.y, align: align),
            );
            page.y += height;
          default:
            throw PrinterFault('unknown command GS 0x${c.toRadixString(16)}');
        }
      } else if (b >= 0x20 && b <= 0x7E) {
        pending.writeCharCode(b);
      } else {
        throw PrinterFault(
          'byte 0x${b.toRadixString(16)} is outside the Latin code page and '
          'would print as an unrelated glyph',
        );
      }
    }
    if (pending.isNotEmpty) flushLine(feed: false);
    return page;
  }
}

/// Something the printer would have got wrong, in words.
final class PrinterFault implements Exception {
  const PrinterFault(this.reason);

  final String reason;

  @override
  String toString() => 'PrinterFault: $reason';
}

sealed class PrintedItem {
  const PrintedItem(this.y);

  /// Dots down the paper from where the job started.
  final int y;
  int get height;
}

final class PrintedText extends PrintedItem {
  const PrintedText._({
    required this.text,
    required int y,
    required this.height,
    required this.align,
    required this.widthMul,
    required this.heightMul,
    required this.bold,
  }) : super(y);

  final String text;
  @override
  final int height;
  final int align;
  final int widthMul;
  final int heightMul;
  final bool bold;
}

final class PrintedRaster extends PrintedItem {
  const PrintedRaster._({
    required this.bitmap,
    required int y,
    required this.align,
  }) : super(y);

  final MonoBitmap bitmap;
  final int align;

  @override
  int get height => bitmap.height;

  /// Whether dot ([x], [row]) of the picture is black.
  bool ink(int x, int row) =>
      bitmap.bits[row * bitmap.bytesPerRow + (x >> 3)] & (0x80 >> (x & 7)) != 0;

  bool get hasInk => bitmap.bits.any((b) => b != 0);
}

/// What came out of the printer.
final class PrintedPaper {
  PrintedPaper._(this.dots);

  final int dots;
  final List<PrintedItem> _items = [];

  /// Where the head is, in dots from the start of the job.
  int y = 0;

  bool initialised = false;
  int? codePage;
  int? font;
  int drawerKicks = 0;

  /// Where on the paper each cut landed.
  final List<int> cuts = [];

  /// Lines longer than the paper, which the printer wrapped.
  final List<String> wrapped = [];

  List<PrintedItem> get items => List.unmodifiable(_items);

  List<PrintedText> get texts => _items.whereType<PrintedText>().toList();

  List<PrintedRaster> get rasters => _items.whereType<PrintedRaster>().toList();

  /// The bottom edge of the last thing printed.
  int get lastInk => _items
      .where((it) => it is! PrintedText || it.text.trim().isNotEmpty)
      .fold(0, (m, it) => it.y + it.height > m ? it.y + it.height : m);

  /// The text line containing [needle].
  PrintedText line(String needle) =>
      texts.firstWhere((t) => t.text.contains(needle));

  /// The paper as a picture, for a person to look at.
  img.Image toImage() {
    final height =
        (cuts.isEmpty ? y : [y, ...cuts].reduce((a, b) => a > b ? a : b)) + 20;
    final image = img.Image(width: dots + 40, height: height + 20);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (final it in _items) {
      switch (it) {
        case PrintedText():
          final cell = VirtualPrinter.cellWidth * it.widthMul;
          final used = it.text.length * cell;
          final left = switch (it.align) {
            1 => (dots - used) ~/ 2,
            2 => dots - used,
            _ => 0,
          };
          for (final (k, ch) in it.text.split('').indexed) {
            if (ch == ' ') continue;
            img.drawString(
              image,
              ch,
              font: img.arial24,
              x: 20 + left + k * cell,
              y: 10 + it.y + (it.height - 24) ~/ 2,
              color: img.ColorRgb8(0, 0, 0),
            );
          }
        case PrintedRaster():
          final left = switch (it.align) {
            1 => (dots - it.bitmap.width) ~/ 2,
            2 => dots - it.bitmap.width,
            _ => 0,
          };
          for (var row = 0; row < it.bitmap.height; row++) {
            for (var x = 0; x < it.bitmap.width; x++) {
              if (it.ink(x, row)) {
                image.setPixelRgb(20 + left + x, 10 + it.y + row, 0, 0, 0);
              }
            }
          }
      }
    }
    for (final cut in cuts) {
      for (var x = 0; x < image.width; x += 2) {
        image.setPixelRgb(x, 10 + cut, 220, 0, 0);
      }
    }
    return image;
  }

  Uint8List toPng() => img.encodePng(toImage());
}

/// Reads a Code 128 symbol off one row of a raster, the way a scanner's
/// sweep does: bar and space widths, divided by the narrowest, looked up.
///
/// Independent of how the symbol was drawn — the table is built from single
/// characters encoded by the `barcode` package, then the checksum and the
/// stop pattern are checked here. Returns null when it does not decode.
String? readCode128(PrintedRaster raster, {int? row}) {
  final y = row ?? raster.bitmap.height ~/ 2;
  final runs = <(bool, int)>[];
  for (var x = 0; x < raster.bitmap.width; x++) {
    final ink = raster.ink(x, y);
    if (runs.isNotEmpty && runs.last.$1 == ink) {
      runs[runs.length - 1] = (ink, runs.last.$2 + 1);
    } else {
      runs.add((ink, 1));
    }
  }
  if (runs.length < 3 || runs.first.$1 || runs.last.$1) return null;
  final bars = runs.sublist(1, runs.length - 1);
  final module = bars.map((r) => r.$2).reduce((a, b) => a < b ? a : b);
  // Ten modules of white each side, or a scanner cannot find the edges.
  if (runs.first.$2 < 10 * module || runs.last.$2 < 10 * module) return null;
  final widths = <int>[];
  for (final (_, w) in bars) {
    if (w % module != 0) return null; // a ragged bar misreads
    widths.add(w ~/ module);
  }
  if ((widths.length - 7) % 6 != 0) return null;
  final table = _code128Table();
  final values = <int>[];
  for (var s = 0; s + 6 <= widths.length - 7; s += 6) {
    final v = table[widths.sublist(s, s + 6).join()];
    if (v == null) return null;
    values.add(v);
  }
  if (widths.sublist(widths.length - 7).join() != '2331112') return null;
  if (values.length < 3) return null;
  var sum = values.first;
  for (var k = 1; k < values.length - 1; k++) {
    sum += values[k] * k;
  }
  if (sum % 103 != values.last) return null;

  final out = StringBuffer();
  String? set = switch (values.first) {
    104 => 'B',
    105 => 'C',
    103 => 'A',
    _ => null,
  };
  if (set == null) return null;
  for (final v in values.sublist(1, values.length - 1)) {
    if (set == 'C') {
      if (v < 100) {
        out.write(v.toString().padLeft(2, '0'));
      } else if (v == 100) {
        set = 'B';
      } else if (v == 101) {
        set = 'A';
      } else {
        return null;
      }
    } else {
      if (v == 99) {
        set = 'C';
      } else if (v == 100 && set == 'A') {
        set = 'B';
      } else if (v == 101 && set == 'B') {
        set = 'A';
      } else if (v < 95) {
        out.writeCharCode(set == 'B' ? v + 32 : (v < 64 ? v + 32 : v - 64));
      } else {
        return null;
      }
    }
  }
  return out.toString();
}

Map<String, int>? _table;

/// Pattern → symbol value, learned from the `barcode` package's encoder.
Map<String, int> _code128Table() {
  if (_table case final t?) return t;
  List<int> widthsOf(String data) {
    final bars = [
      for (final e in bc.Barcode.code128().make(
        data,
        width: 10000,
        height: 1,
        drawText: false,
      ))
        if (e is bc.BarcodeBar) e,
    ];
    final narrow = bars.map((b) => b.width).reduce((a, b) => a < b ? a : b);
    // Bars and the spaces between them, in modules.
    final out = <int>[];
    for (var k = 0; k < bars.length; k++) {
      if (!bars[k].black) continue;
      out.add((bars[k].width / narrow).round());
      if (k + 1 < bars.length && !bars[k + 1].black) {
        out.add((bars[k + 1].width / narrow).round());
      }
    }
    return out;
  }

  // The three start patterns are fixed by the specification.
  final table = <String, int>{'211412': 103, '211214': 104, '211232': 105};
  // Single characters: a start, the character, checksum, stop. Printable
  // ASCII has the same value, c - 32, in whichever of sets A and B the
  // encoder picks.
  for (var c = 32; c < 127; c++) {
    final w = widthsOf(String.fromCharCode(c));
    table.putIfAbsent(w.sublist(6, 12).join(), () => c - 32);
  }
  // Pairs of digits in set C give every value up to 99.
  for (var v = 0; v < 100; v++) {
    final w = widthsOf('${v.toString().padLeft(2, '0')}00');
    if (w.sublist(0, 6).join() == '211232') {
      table.putIfAbsent(w.sublist(6, 12).join(), () => v);
    }
  }
  // The set switches (99 to 101) only appear between runs, so they are
  // learned from strings that force one, each solved from the checksum:
  // with every other symbol known, the one unknown value is the one that
  // makes the sum come out.
  for (final probe in ['0000a', '0000\u0001', 'a0000', '\u0001a', 'a\u0001']) {
    final List<int> w;
    try {
      w = widthsOf(probe);
    } on Object {
      continue;
    }
    final symbols = [
      for (var k = 0; k + 6 <= w.length - 7; k += 6) w.sublist(k, k + 6).join(),
    ];
    final unknown = [
      for (var k = 0; k < symbols.length - 1; k++)
        if (!table.containsKey(symbols[k])) k,
    ];
    final check = table[symbols.last];
    if (unknown.length != 1 || unknown.single == 0 || check == null) continue;
    final at = unknown.single;
    var known = table[symbols.first]!;
    for (var k = 1; k < symbols.length - 1; k++) {
      if (k != at) known += table[symbols[k]]! * k;
    }
    for (var v = 0; v < 107; v++) {
      if ((known + v * at) % 103 == check) {
        table[symbols[at]] = v;
        break;
      }
    }
  }
  return _table = table;
}
