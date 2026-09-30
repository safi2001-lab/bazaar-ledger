/// Reading what a weighing scale's label says.
///
/// A butcher's, a sabzi seller's or a dry-fruit shop's scale prints its own
/// EAN-13 label: a prefix in the 20–29 range that says "this is a scale
/// label", the item's PLU (the number the shop keyed into the scale for it),
/// then either the weight or the price, then a check digit. The counter
/// reads the item and the quantity off one scan, and the cashier types
/// nothing (M16).
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

/// How this shop's scale lays out its labels. Scales are configured by the
/// shop, so the app has to be told, once, in Settings.
final class ScaleFormat {
  const ScaleFormat({
    this.weightPrefixes = const {'21', '22'},
    this.pricePrefixes = const {'23', '24'},
    this.pluDigits = 5,
    this.priceDecimals = 0,
  });

  /// Prefixes whose labels carry a weight in grams.
  final Set<String> weightPrefixes;

  /// Prefixes whose labels carry a price.
  final Set<String> pricePrefixes;

  /// Digits of PLU after the prefix; the value takes the rest of the ten.
  final int pluDigits;

  /// Decimal places in a printed price: 0 for whole rupees, 2 for paisa.
  final int priceDecimals;

  int get valueDigits => 10 - pluDigits;

  static const standard = ScaleFormat();

  String toJson() => jsonEncode({
    'weight': weightPrefixes.toList()..sort(),
    'price': pricePrefixes.toList()..sort(),
    'plu': pluDigits,
    'priceDecimals': priceDecimals,
  });

  /// Reads a stored format, or the standard one if it cannot be read.
  static ScaleFormat fromJson(String? raw) {
    if (raw == null) return standard;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final format = ScaleFormat(
        weightPrefixes: {for (final p in json['weight']! as List) '$p'},
        pricePrefixes: {for (final p in json['price']! as List) '$p'},
        pluDigits: json['plu']! as int,
        priceDecimals: json['priceDecimals']! as int,
      );
      return format.isValid ? format : standard;
    } on Object {
      return standard;
    }
  }

  bool get isValid {
    final prefix = RegExp(r'^2[0-9]$');
    return pluDigits >= 4 &&
        pluDigits <= 6 &&
        (priceDecimals == 0 || priceDecimals == 2) &&
        weightPrefixes.every(prefix.hasMatch) &&
        pricePrefixes.every(prefix.hasMatch) &&
        weightPrefixes.intersection(pricePrefixes).isEmpty;
  }
}

/// What one scale label said.
final class ScaleData {
  const ScaleData({required this.plu, this.grams, this.price});

  /// The shop's own code for the item, as keyed into the scale, without
  /// leading zeros.
  final String plu;

  /// The weight, when the label carries one.
  final int? grams;

  /// The price, when the label carries one.
  final Money? price;
}

/// Reads [raw] as a scale label in [format], or returns null when it is not
/// one: not thirteen digits, a prefix the format does not name, or a check
/// digit that does not match — a torn label must not ring up the wrong
/// weight.
ScaleData? parseScaleBarcode(String raw, ScaleFormat format) {
  final code = raw.trim();
  if (!RegExp(r'^\d{13}$').hasMatch(code)) return null;
  final prefix = code.substring(0, 2);
  final isWeight = format.weightPrefixes.contains(prefix);
  final isPrice = format.pricePrefixes.contains(prefix);
  if (!isWeight && !isPrice) return null;
  if (!_checkDigitOk(code)) return null;

  final pluRaw = code.substring(2, 2 + format.pluDigits);
  final value = int.parse(code.substring(2 + format.pluDigits, 12));
  final plu = pluRaw.replaceFirst(RegExp('^0+(?=.)'), '');
  if (isWeight) return ScaleData(plu: plu, grams: value);
  final paisa = format.priceDecimals == 2 ? value : value * 100;
  return ScaleData(plu: plu, price: Money.paisa(paisa));
}

bool _checkDigitOk(String code) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = code.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return (10 - sum % 10) % 10 == code.codeUnitAt(12) - 48;
}
