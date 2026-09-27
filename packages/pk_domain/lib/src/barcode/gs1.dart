/// Reading what a medicine pack's barcode says.
///
/// Packs printed to the GS1 standard carry more than a product number in
/// one symbol: the GTIN (01), the batch (10), the expiry (17) and often a
/// serial (21). DRAP's track-and-trace rules put exactly these on every
/// pack. A scanner hands them over either with a group-separator character
/// between the variable-length fields, or, from a label printed for people,
/// with the codes in brackets. Both are read here.
library;

import '../time/clock.dart';

/// What one GS1 barcode said.
final class Gs1Data {
  const Gs1Data({this.gtin, this.batch, this.expiry, this.serial});

  /// Fourteen digits.
  final String? gtin;
  final String? batch;
  final BusinessDate? expiry;
  final String? serial;

  /// The GTIN as a shop's EAN-13 barcode field would hold it: the leading
  /// zero of a GTIN-14 dropped.
  String? get ean13 =>
      gtin != null && gtin!.startsWith('0') ? gtin!.substring(1) : gtin;
}

const _groupSeparator = '\u001d';

/// The fixed lengths of the application identifiers read here.
const _fixed = {'01': 14, '11': 6, '15': 6, '17': 6};

/// The variable-length identifiers read here, with their longest value.
const _variable = {'10': 20, '21': 20, '30': 8};

/// Reads [raw] as a GS1 element string, or returns null when it is not one
/// (an ordinary EAN-13, an IMEI, a shop's own code).
Gs1Data? parseGs1(String raw) {
  var s = raw.trim();
  // A scanner may prefix the symbology: ]d2 DataMatrix, ]C1 GS1-128, ]Q3 QR.
  if (RegExp(r'^\][A-Za-z]\d').hasMatch(s)) s = s.substring(3);
  if (s.startsWith('(')) return _parseBracketed(s);
  if (!s.startsWith('01') || s.length < 16) return null;

  final fields = <String, String>{};
  var i = 0;
  while (i < s.length) {
    if (s[i] == _groupSeparator) {
      i++;
      continue;
    }
    if (i + 2 > s.length) return null;
    final ai = s.substring(i, i + 2);
    i += 2;
    if (_fixed[ai] case final len?) {
      if (i + len > s.length) return null;
      fields[ai] = s.substring(i, i + len);
      i += len;
    } else if (_variable[ai] case final max?) {
      final end = s.indexOf(_groupSeparator, i);
      final stop = end < 0 ? s.length : end;
      if (stop - i > max) return null;
      fields[ai] = s.substring(i, stop);
      i = stop;
    } else {
      // An identifier this reader does not know: stop, and keep what was
      // read, since the product and batch come first on every pack.
      break;
    }
  }
  return _data(fields);
}

Gs1Data? _parseBracketed(String s) {
  final fields = <String, String>{};
  for (final m in RegExp(r'\((\d{2,4})\)([^(]*)').allMatches(s)) {
    fields[m.group(1)!] = m.group(2)!.trim();
  }
  if (!fields.containsKey('01')) return null;
  return _data(fields);
}

Gs1Data? _data(Map<String, String> f) {
  final gtin = f['01'];
  if (gtin == null || !RegExp(r'^\d{14}$').hasMatch(gtin)) return null;
  return Gs1Data(
    gtin: gtin,
    batch: f['10'],
    serial: f['21'],
    expiry: _date(f['17']),
  );
}

/// YYMMDD, with day 00 meaning the last day of the month, as GS1 has it.
BusinessDate? _date(String? yymmdd) {
  if (yymmdd == null || !RegExp(r'^\d{6}$').hasMatch(yymmdd)) return null;
  final year = 2000 + int.parse(yymmdd.substring(0, 2));
  final month = int.parse(yymmdd.substring(2, 4));
  var day = int.parse(yymmdd.substring(4, 6));
  if (month < 1 || month > 12) return null;
  if (day == 0) day = DateTime.utc(year, month + 1, 0).day;
  return BusinessDate.tryParse(
    '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  );
}
