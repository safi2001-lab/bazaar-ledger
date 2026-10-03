import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../l10n/app_strings.dart';

/// Why a number is not an IMEI, in the shopkeeper's language (M50): the
/// same refusal the books make beneath the screen, said before Save.
String imeiProblemWords(AppStrings s, ImeiProblem problem) =>
    switch (problem.kind) {
      ImeiProblemKind.empty => s.mobileImeiEmpty,
      ImeiProblemKind.notDigits => s.mobileImeiNotDigits,
      ImeiProblemKind.wrongLength => s.mobileImeiLength(problem.digits.length),
      ImeiProblemKind.checkDigit => s.mobileImeiMistyped(
        problem.digits,
        '${problem.expectedLast}',
      ),
      ImeiProblemKind.sameAsFirst => s.mobileImeiSameTwice,
    };

/// The check for an IMEI field: null when [raw] is an IMEI, or the words
/// for why not. [optional] lets an empty field through (IMEI 2).
String? imeiFieldProblem(AppStrings s, String raw, {bool optional = false}) {
  if (optional && imeiDigits(raw).isEmpty) return null;
  final problem = imeiProblem(raw);
  return problem == null ? null : imeiProblemWords(s, problem);
}
