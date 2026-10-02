import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'spreadsheet.dart';

/// The old binary Excel workbook (`.xls`, Excel 97 to 2003), first sheet,
/// as text — without a dependency.
///
/// M14 refused these and asked the shopkeeper to open the file in Excel and
/// save it again. Plenty of the shops this app is for have no Excel: the
/// file came off a desktop billing program, or a nephew's laptop, and the
/// phone is the only computer in the shop. The format is two old layers,
/// both documented by Microsoft ([MS-CFB] and [MS-XLS]), and reading cell
/// values out of them is a few hundred lines rather than a package: the
/// compound file is a little FAT file system, and the workbook inside it a
/// run of typed records. Formatting, formulas' workings, charts and every
/// other sheet are skipped; only what a cell shows is read.
///
/// Numbers in this format are IEEE doubles on disk, so one is decoded here
/// for as long as it takes to write it as the shortest decimal that is the
/// same double — exactly what Excel writes into an `.xlsx` — and from then
/// on it is text, read to the paisa by the same parser as every other sheet.
SheetRows readXls(Uint8List bytes) {
  try {
    return _Biff(_workbookStream(bytes)).firstSheet();
  } on ImportRefused {
    rethrow;
  } on Object {
    throw const ImportRefused(_damaged);
  }
}

/// Whether [bytes] are a compound file — the container every `.xls` is.
bool isCompoundFile(Uint8List bytes) =>
    bytes.length >= 512 &&
    const [
      0xD0,
      0xCF,
      0x11,
      0xE0,
      0xA1,
      0xB1,
      0x1A,
      0xE1,
    ].indexed.every((e) => bytes[e.$1] == e.$2);

const _damaged =
    'This .xls file could not be read. Open it in Excel and save it as '
    '.xlsx or .csv, then import that.';

// ---------------------------------------------------------------------------
// The compound file: sectors, a FAT, a directory of streams.
// ---------------------------------------------------------------------------

const _endOfChain = 0xFFFFFFFE;
const _free = 0xFFFFFFFF;

Uint8List _workbookStream(Uint8List file) {
  if (!isCompoundFile(file)) throw const ImportRefused(_damaged);
  final data = ByteData.sublistView(file);
  int u32(int at) => data.getUint32(at, Endian.little);
  final sectorShift = data.getUint16(0x1E, Endian.little);
  final miniShift = data.getUint16(0x20, Endian.little);
  if (sectorShift != 9 && sectorShift != 12) {
    throw const ImportRefused(_damaged);
  }
  final sectorSize = 1 << sectorShift;
  final miniSize = 1 << miniShift;
  final sectorCount = (file.length >> sectorShift) + 1;
  final miniCutoff = u32(0x38);

  int sectorAt(int id) => (id + 1) << sectorShift;

  // Where the FAT's own sectors are: 109 in the header, the rest in a
  // chain of DIFAT sectors.
  final fatSectors = <int>[];
  final fatCount = u32(0x2C);
  for (var i = 0; i < 109 && fatSectors.length < fatCount; i++) {
    final id = u32(0x4C + i * 4);
    if (id == _free) break;
    fatSectors.add(id);
  }
  var difat = u32(0x44);
  for (
    var guard = 0;
    difat != _endOfChain && difat != _free && fatSectors.length < fatCount;
    guard++
  ) {
    if (guard > sectorCount) throw const ImportRefused(_damaged);
    final at = sectorAt(difat);
    final perSector = sectorSize ~/ 4 - 1;
    for (var i = 0; i < perSector && fatSectors.length < fatCount; i++) {
      fatSectors.add(u32(at + i * 4));
    }
    difat = u32(at + perSector * 4);
  }
  final fat = <int>[
    for (final s in fatSectors)
      for (var i = 0; i < sectorSize ~/ 4; i++) u32(sectorAt(s) + i * 4),
  ];

  /// A chain of sectors read end to end. A loop or a sector off the end of
  /// the file is a damaged file, not an endless read.
  Uint8List chain(int start, List<int> table, Uint8List Function(int) read) {
    final out = BytesBuilder(copy: false);
    var id = start;
    for (var guard = 0; id != _endOfChain && id != _free; guard++) {
      if (guard > table.length || id >= table.length) {
        throw const ImportRefused(_damaged);
      }
      out.add(read(id));
      id = table[id];
    }
    return out.takeBytes();
  }

  Uint8List sector(int id) {
    final at = sectorAt(id);
    if (at + sectorSize > file.length) {
      // The last sector of a file can be short; what is there is all of it.
      if (at >= file.length) throw const ImportRefused(_damaged);
      return Uint8List.sublistView(file, at);
    }
    return Uint8List.sublistView(file, at, at + sectorSize);
  }

  final directory = chain(u32(0x30), fat, sector);
  final dir = ByteData.sublistView(directory);
  Uint8List? root;
  var rootStart = _endOfChain;
  ({int start, int size})? workbook;
  var oldBook = false;
  for (var at = 0; at + 128 <= directory.length; at += 128) {
    final type = directory[at + 0x42];
    final nameBytes = dir.getUint16(at + 0x40, Endian.little);
    if (nameBytes < 2 || nameBytes > 64) continue;
    final name = String.fromCharCodes([
      for (var i = 0; i < nameBytes ~/ 2 - 1; i++)
        dir.getUint16(at + i * 2, Endian.little),
    ]);
    final start = dir.getUint32(at + 0x74, Endian.little);
    // Version 3 files keep only the low half of the size; the high half can
    // be anything.
    final size = dir.getUint32(at + 0x78, Endian.little);
    if (type == 5) {
      rootStart = start;
    } else if (type == 2) {
      final lower = name.toLowerCase();
      if (lower == 'workbook') workbook = (start: start, size: size);
      if (lower == 'book') oldBook = true;
    }
  }
  if (workbook == null) {
    throw ImportRefused(
      oldBook
          ? 'This .xls is from Excel 95 or older. Open it in Excel and save it '
                'as .xlsx or .csv, then import that.'
          : _damaged,
    );
  }

  Uint8List bytes;
  if (workbook.size < miniCutoff) {
    // A small stream lives in the mini stream: 64-byte sectors inside the
    // root entry's own stream, chained by a FAT of their own.
    root ??= chain(rootStart, fat, sector);
    final miniFatBytes = chain(u32(0x3C), fat, sector);
    final miniData = ByteData.sublistView(miniFatBytes);
    final miniFat = [
      for (var i = 0; i + 4 <= miniFatBytes.length; i += 4)
        miniData.getUint32(i, Endian.little),
    ];
    final container = root;
    bytes = chain(workbook.start, miniFat, (id) {
      final at = id * miniSize;
      if (at + miniSize > container.length) throw const ImportRefused(_damaged);
      return Uint8List.sublistView(container, at, at + miniSize);
    });
  } else {
    bytes = chain(workbook.start, fat, sector);
  }
  if (bytes.length < workbook.size) throw const ImportRefused(_damaged);
  return Uint8List.sublistView(bytes, 0, workbook.size);
}

// ---------------------------------------------------------------------------
// The workbook: BIFF8 records.
// ---------------------------------------------------------------------------

const _bof = 0x0809;
const _eof = 0x000A;
const _filePass = 0x002F;
const _boundSheet = 0x0085;
const _sst = 0x00FC;
const _continue = 0x003C;
const _labelSst = 0x00FD;
const _label = 0x0204;
const _rString = 0x00D6;
const _number = 0x0203;
const _rk = 0x027E;
const _mulRk = 0x00BD;
const _boolErr = 0x0205;
const _formula = 0x0006;
const _string = 0x0207;

final class _Record {
  const _Record(this.type, this.offset, this.data);

  final int type;

  /// Where the record starts in the stream; a sheet is found by this.
  final int offset;
  final Uint8List data;

  int u16(int at) => data[at] | (data[at + 1] << 8);

  int u32(int at) => u16(at) | (u16(at + 2) << 16);
}

final class _Biff {
  _Biff(this._stream);

  final Uint8List _stream;

  Iterable<_Record> _records(int from) sync* {
    var at = from;
    while (at + 4 <= _stream.length) {
      final type = _stream[at] | (_stream[at + 1] << 8);
      final size = _stream[at + 2] | (_stream[at + 3] << 8);
      final end = math.min(at + 4 + size, _stream.length);
      yield _Record(type, at, Uint8List.sublistView(_stream, at + 4, end));
      at = at + 4 + size;
    }
  }

  SheetRows firstSheet() {
    final globals = _records(0).iterator;
    if (!globals.moveNext() || globals.current.type != _bof) {
      throw const ImportRefused(_damaged);
    }
    if (globals.current.u16(0) != 0x0600) {
      throw const ImportRefused(
        'This .xls is from Excel 95 or older. Open it in Excel and save it '
        'as .xlsx or .csv, then import that.',
      );
    }
    int? sheetAt;
    final sstParts = <Uint8List>[];
    var inSst = false;
    while (globals.moveNext()) {
      final r = globals.current;
      if (r.type == _eof) break;
      if (r.type == _filePass) {
        throw const ImportRefused(
          'This workbook has a password. Open it in Excel, take the password '
          'off, and save it as .xlsx, then import that.',
        );
      }
      if (r.type == _boundSheet && sheetAt == null && r.data[5] == 0) {
        sheetAt = r.u32(0);
      }
      if (r.type == _sst) {
        sstParts.add(r.data);
        inSst = true;
      } else if (r.type == _continue && inSst) {
        sstParts.add(r.data);
      } else {
        inSst = false;
      }
    }
    if (sheetAt == null) {
      throw const ImportRefused('This workbook has no sheets.');
    }
    final shared = sstParts.isEmpty ? const <String>[] : _readSst(sstParts);
    return _readSheet(sheetAt, shared);
  }

  SheetRows _readSheet(int at, List<String> shared) {
    final cells = <int, Map<int, String>>{};
    void put(int row, int col, String value) =>
        (cells[row] ??= <int, String>{})[col] = value;

    var first = true;
    (int, int)? pendingString;
    for (final r in _records(at)) {
      if (first) {
        if (r.type != _bof) throw const ImportRefused(_damaged);
        first = false;
        continue;
      }
      if (r.type == _eof) break;
      if (r.type != _string) pendingString = null;
      switch (r.type) {
        case _labelSst:
          final i = r.u32(6);
          put(r.u16(0), r.u16(2), i < shared.length ? shared[i] : '');
        case _label || _rString:
          put(r.u16(0), r.u16(2), _shortString(r.data, 6));
        case _number:
          put(r.u16(0), r.u16(2), _numberText(_float(r.data, 6)));
        case _rk:
          put(r.u16(0), r.u16(2), _rkText(r.u32(6)));
        case _mulRk:
          final row = r.u16(0);
          final firstCol = r.u16(2);
          final count = (r.data.length - 6) ~/ 6;
          for (var i = 0; i < count; i++) {
            put(row, firstCol + i, _rkText(r.u32(4 + i * 6 + 2)));
          }
        case _boolErr:
          if (r.data[7] == 0) {
            put(r.u16(0), r.u16(2), r.data[6] == 0 ? 'FALSE' : 'TRUE');
          }
        case _formula:
          final row = r.u16(0);
          final col = r.u16(2);
          if (r.data[12] == 0xFF && r.data[13] == 0xFF) {
            switch (r.data[6]) {
              case 0:
                // The text a formula shows is in the STRING record after it.
                pendingString = (row, col);
              case 1:
                put(row, col, r.data[8] == 0 ? 'FALSE' : 'TRUE');
              default:
                break;
            }
          } else {
            put(row, col, _numberText(_float(r.data, 6)));
          }
        case _string:
          if (pendingString case (final row, final col)) {
            put(row, col, _shortString(r.data, 0));
          }
          pendingString = null;
        default:
          break;
      }
    }
    if (cells.isEmpty) return const SheetRows([]);
    final last = cells.keys.reduce(math.max);
    return SheetRows([
      for (var row = 0; row <= last; row++)
        if (cells[row] case final columns?)
          [
            for (var c = 0; c <= columns.keys.reduce(math.max); c++)
              columns[c] ?? '',
          ]
        else
          const <String>[],
    ]);
  }
}

/// An XLUnicodeString inside one record: a count, a flags byte, then the
/// characters one byte each (Latin-1) or two (UTF-16).
String _shortString(Uint8List data, int at) {
  if (at + 3 > data.length) return '';
  final count = data[at] | (data[at + 1] << 8);
  final wide = data[at + 2] & 1 != 0;
  final from = at + 3;
  if (wide) {
    final view = ByteData.sublistView(
      data,
      from,
      math.min(from + count * 2, data.length),
    );
    return String.fromCharCodes([
      for (var i = 0; i + 1 < view.lengthInBytes; i += 2)
        view.getUint16(i, Endian.little),
    ]);
  }
  return latin1.decode(
    Uint8List.sublistView(data, from, math.min(from + count, data.length)),
  );
}

/// The shared strings, which run on from the SST record into as many
/// CONTINUE records as they need. A string's characters can break across
/// the join, and where they do the next record starts with a fresh flags
/// byte saying whether the rest is one byte a character or two.
List<String> _readSst(List<Uint8List> parts) {
  final out = <String>[];
  var part = 0;
  var at = 8;
  int byte() {
    while (at >= parts[part].length) {
      part++;
      at = 0;
      if (part >= parts.length) throw const ImportRefused(_damaged);
    }
    return parts[part][at++];
  }

  int u16() => byte() | (byte() << 8);
  int u32() => u16() | (u16() << 16);
  void skip(int n) {
    for (var left = n; left > 0;) {
      while (at >= parts[part].length) {
        part++;
        at = 0;
        if (part >= parts.length) throw const ImportRefused(_damaged);
      }
      final take = math.min(left, parts[part].length - at);
      at += take;
      left -= take;
    }
  }

  final unique = ByteData.sublistView(parts.first).getUint32(4, Endian.little);
  for (var n = 0; n < unique; n++) {
    if (part == parts.length - 1 && at >= parts[part].length) break;
    final count = u16();
    final flags = byte();
    var wide = flags & 0x01 != 0;
    final runs = flags & 0x08 != 0 ? u16() : 0;
    final extra = flags & 0x04 != 0 ? u32() : 0;
    final chars = StringBuffer();
    for (var left = count; left > 0;) {
      if (at >= parts[part].length) {
        part++;
        at = 0;
        if (part >= parts.length) throw const ImportRefused(_damaged);
        wide = parts[part][at++] & 0x01 != 0;
      }
      final width = wide ? 2 : 1;
      final take = math.min(left, (parts[part].length - at) ~/ width);
      if (take == 0) throw const ImportRefused(_damaged);
      final bytes = parts[part];
      for (var i = 0; i < take; i++) {
        chars.writeCharCode(
          wide
              ? bytes[at + i * 2] | (bytes[at + i * 2 + 1] << 8)
              : bytes[at + i],
        );
      }
      at += take * width;
      left -= take;
    }
    skip(runs * 4 + extra);
    out.add(chars.toString());
  }
  return out;
}

double _float(Uint8List data, int at) =>
    ByteData.sublistView(data, at, at + 8).getFloat64(0, Endian.little);

/// An RK number: thirty bits of either an integer or the top of a double,
/// perhaps a hundred times too big. The integer kind is done in integers,
/// so `1250.50` stored as 125050 comes out as exactly that.
String _rkText(int rk) {
  final hundredths = rk & 1 != 0;
  if (rk & 2 != 0) {
    var whole = rk >> 2;
    if (whole & 0x20000000 != 0) whole -= 0x40000000;
    if (!hundredths) return '$whole';
    final sign = whole < 0 ? '-' : '';
    final a = whole.abs();
    return '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  }
  final bits = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
  final text = _numberText(bits.getFloat64(0, Endian.little));
  return hundredths ? _shiftPoint(text, -2) : text;
}

/// A double as the shortest decimal that reads back as the same double,
/// without a trailing `.0` on a whole number — what Excel writes into an
/// `.xlsx` for the same cell. Phone numbers and barcodes kept as numbers
/// come out as their digits.
String _numberText(double d) {
  if (d.isNaN || d.isInfinite) return '';
  if (d == d.truncateToDouble() && d.abs() < 1e15) return '${d.toInt()}';
  return '$d';
}

/// [text] with its decimal point moved [shift] places right (left when
/// negative), written out in full.
String _shiftPoint(String text, int shift) {
  final m = RegExp(
    r'^(-?)(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?$',
  ).firstMatch(text);
  if (m == null) return text;
  var digits = '${m[2]}${m[3] ?? ''}';
  var point = m[2]!.length + (int.tryParse(m[4] ?? '') ?? 0) + shift;
  if (point <= 0) {
    digits = '${'0' * (1 - point)}$digits';
    point = 1;
  }
  if (point > digits.length) digits = digits.padRight(point, '0');
  final whole = digits
      .substring(0, point)
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final frac = digits.substring(point).replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? '${m[1]}$whole' : '${m[1]}$whole.$frac';
}
