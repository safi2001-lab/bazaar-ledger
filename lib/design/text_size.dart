import 'package:flutter/widgets.dart';

/// How big the app's words are, on top of the phone's own setting (M56).
///
/// The phone's font slider is the first answer, and the app has followed it
/// to 200% since the large-text audit. But the owner of a shop is often the
/// oldest person in it, the phone is often the shop's and not theirs, and
/// turning the whole phone's text up to read the khata makes every other
/// app on it unreadable to the cashier who shares it. Competitors are
/// reviewed for exactly this ("font too small"), so the app has a setting
/// of its own, kept with the language and the theme.
///
/// Three steps, not a slider: a shopkeeper can tell Normal from Large at a
/// glance, and nobody has ever wanted 1.07.
enum BlTextSize {
  normal(1),
  large(1.15),
  larger(1.3);

  const BlTextSize(this.factor);

  /// How much bigger than the phone's own size.
  final double factor;
}

/// The size words are drawn at: the phone's own [system] scale, made
/// bigger by [size], and kept between [min] and [max].
///
/// The cap applies to the two together. Two hundred percent is what every
/// screen is laid out and tested at (`large_text_test`); a phone already at
/// 200% with Larger on top would ask for 260%, and the money column would
/// leave the screen. So the setting can bring a small phone setting up to
/// the cap, never past it.
///
/// The printer and the PDF never read this. A receipt is rasterised and a
/// PDF is laid out off-screen, at the sizes paper needs, so what the
/// customer is handed is the same at every setting.
TextScaler shopTextScaler(
  TextScaler system,
  BlTextSize size, {
  double min = 0.85,
  double max = 2.0,
}) {
  final scaled = size == BlTextSize.normal
      ? system
      : _Enlarged(system, size.factor);
  return scaled.clamp(minScaleFactor: min, maxScaleFactor: max);
}

/// The phone's scaling, whatever shape it has (Android 14 scales large
/// text less than small), multiplied by the shop's own step.
final class _Enlarged extends TextScaler {
  const _Enlarged(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  /// Required by the interface, which keeps it for old callers. An estimate
  /// by definition; the scale of a one-point font is as good as any.
  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is _Enlarged && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);

  @override
  String toString() => '$base x $factor';
}
