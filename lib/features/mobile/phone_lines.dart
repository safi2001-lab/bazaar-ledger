import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../l10n/app_strings.dart';
import 'imei_words.dart';

/// A delivery of phones as the serial box takes it, in a mobile shop (M50):
/// one phone a line, "IMEI 1" or "IMEI 1 / IMEI 2" for a dual-SIM one.
///
/// Read as phones only when every line starts with something that is an
/// IMEI or meant to be one — fourteen to seventeen digits once the dashes
/// are out — so a mistyped IMEI is caught rather than kept as a serial,
/// while a power bank's "PB2024X001" in the same shop stays a plain serial
/// as M11 always kept it. Empty when the lines are not phones.
List<PhoneUnitDraft> phonesFromLines(List<String> lines) {
  final split = [
    for (final line in lines)
      [
        for (final part in line.split(RegExp(r'[\s/|]+')))
          if (part.trim().isNotEmpty) part.trim(),
      ],
  ];
  final phones =
      split.isNotEmpty &&
      split.every(
        (parts) =>
            parts.isNotEmpty &&
            RegExp(r'^\d{14,17}$').hasMatch(imeiDigits(parts.first)),
      );
  if (!phones) return const [];
  return [
    for (final parts in split)
      PhoneUnitDraft(
        imei1: imeiDigits(parts.first),
        imei2: parts.length > 1 ? imeiDigits(parts[1]) : null,
      ),
  ];
}

/// [phone] as a line of the serial box: "IMEI 1 / IMEI 2".
String phoneLine(PhoneUnitDraft phone) => switch (phone.imei2) {
  final second? when second.isNotEmpty => '${phone.imei1} / $second',
  _ => phone.imei1,
};

/// What is wrong with the first phone that has something wrong, in words,
/// or null when every IMEI is one.
String? phonesProblem(AppStrings s, List<PhoneUnitDraft> phones) {
  for (final phone in phones) {
    try {
      phone.check();
    } on ImeiRefused catch (refused) {
      return imeiProblemWords(s, refused.problem);
    }
  }
  return null;
}
