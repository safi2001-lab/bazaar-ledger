// Architectural rules, enforced as a build step.
//
// Every rule here exists because the previous build broke it, and because
// breaking it is invisible in review. A folder convention enforces nothing; a
// script that fails the build enforces it every time.
//
// Run with `dart run tool/arch_check.dart`. Exit code 1 means at least one
// rule was broken, and the output says which file, which line, and why.
//
// Deliberately a plain script over `dart:io` rather than a `custom_lint`
// plugin. A lint plugin has to keep three packages version-locked against the
// analyzer, and an analyzer bump that silently disables the rules is worse
// than no rules — you keep the green tick and lose the guarantee. This has no
// dependencies at all and cannot stop working.

import 'dart:io';

void main(List<String> args) {
  final violations = <Violation>[];
  for (final rule in rules) {
    violations.addAll(rule.run());
  }

  if (violations.isEmpty) {
    stdout.writeln('arch_check: ${rules.length} rules, no violations.');
    return;
  }

  final byRule = <String, List<Violation>>{};
  for (final v in violations) {
    byRule.putIfAbsent(v.rule, () => []).add(v);
  }

  stderr.writeln('arch_check: ${violations.length} violation(s).\n');
  for (final entry in byRule.entries) {
    final rule = rules.firstWhere((r) => r.name == entry.key);
    stderr.writeln('== ${rule.name} ==');
    stderr.writeln('${rule.why}\n');
    for (final v in entry.value) {
      stderr.writeln('  ${v.file}:${v.line}');
      stderr.writeln('    ${v.source.trim()}');
    }
    stderr.writeln('');
  }
  exit(1);
}

final class Violation {
  Violation({
    required this.rule,
    required this.file,
    required this.line,
    required this.source,
  });

  final String rule;
  final String file;
  final int line;
  final String source;
}

/// What part of a line a rule is about.
enum Reads {
  /// Code with the contents of string literals blanked out. The default: a
  /// rule about `double` is about the type, not about the word.
  code,

  /// The line exactly as written, literals included. For rules whose whole
  /// subject is what a literal says.
  raw,

  /// String literals with `${...}` interpolations removed, so a rule about
  /// untranslated prose does not fire on `Text('$count')`.
  prose;

  String apply(String line) => switch (this) {
        Reads.raw => line,
        Reads.code => line
            .replaceAll(RegExp(r"'[^']*'"), "''")
            .replaceAll(RegExp(r'"[^"]*"'), '""'),
        Reads.prose => line.replaceAll(RegExp(r'\$\{[^}]*\}'), '').replaceAll(
              RegExp(r'\$\w+'),
              '',
            ),
      };
}

/// One rule: which files it looks at, and what it refuses to find in them.
final class Rule {
  const Rule({
    required this.name,
    required this.why,
    required this.include,
    required this.forbid,
    this.exclude = const [],
    this.reads = Reads.code,
    this.allowLines,
  });

  final String name;

  /// Written for whoever trips over it at 2am, not for whoever wrote it.
  final String why;

  /// Path prefixes this rule applies to, relative to the repository root.
  final List<String> include;

  /// Path fragments exempt from it, each of which must be justified in the
  /// rule's own `why`.
  final List<String> exclude;

  final List<RegExp> forbid;

  /// What the rule reads on each line.
  ///
  /// Most rules are about code, and a rule that cannot tell code from prose
  /// fires on its own error messages — `no_floating_point_money` matched the
  /// word "double" inside the sentence explaining why doubles are refused.
  final Reads reads;

  /// A last-resort escape hatch for a line that legitimately matches.
  final bool Function(String line)? allowLines;

  List<Violation> run() {
    final found = <Violation>[];
    for (final path in include) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalised = entity.path.replaceAll(r'\', '/');
        if (normalised.contains('/build/')) continue;
        if (normalised.endsWith('.g.dart')) continue;
        if (normalised.endsWith('.drift.dart')) continue;
        if (exclude.any(normalised.contains)) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('arch_check: allow')) continue;
          if (allowLines != null && allowLines!(line)) continue;
          final subject = reads.apply(line);
          for (final pattern in forbid) {
            if (pattern.hasMatch(subject)) {
              found.add(
                Violation(
                  rule: name,
                  file: normalised,
                  line: i + 1,
                  source: line,
                ),
              );
              break;
            }
          }
        }
      }
    }
    return found;
  }
}

final rules = <Rule>[
  // -------------------------------------------------------------------------
  // Layering
  // -------------------------------------------------------------------------
  Rule(
    name: 'ui_cannot_reach_the_database',
    why: 'The app package does not list pk_data or drift in its pubspec, so '
        'this is already a resolution error. The rule exists so that adding '
        'the dependency "just for one screen" fails here, loudly, rather '
        'than passing review because the import looked harmless.',
    include: ['lib'],
    forbid: [
      RegExp(r'''import\s+.package:drift'''),
      RegExp(r'''import\s+.package:pk_data'''),
      RegExp(r'''import\s+.package:sqlite3'''),
    ],
  ),

  Rule(
    name: 'domain_is_pure',
    why: 'pk_domain holds the posting rules. It knows nothing about SQL, '
        'Flutter, files or the network, which is what lets every rule in it '
        'be tested exhaustively without a database and what keeps a UI '
        'concern from quietly becoming an accounting one.',
    include: ['packages/pk_domain/lib', 'packages/pk_money/lib'],
    forbid: [
      RegExp(r'''import\s+.package:drift'''),
      RegExp(r'''import\s+.package:flutter'''),
      RegExp(r'''import\s+.package:pk_data'''),
      RegExp(r'''import\s+.dart:io'''),
      RegExp(r'''import\s+.dart:ui'''),
    ],
  ),

  Rule(
    name: 'money_has_no_dependencies',
    why: 'pk_money is the bottom of the stack. Everything else may depend on '
        'it; it depends on nothing, so there is no version of this codebase '
        'in which the definition of a rupee is affected by a package bump.',
    include: ['packages/pk_money/lib'],
    forbid: [RegExp(r'''import\s+.package:(?!pk_money)''')],
  ),

  Rule(
    name: 'application_layer_holds_no_sql',
    why: 'Use cases orchestrate ports. A use case that writes SQL is a use '
        'case that cannot be tested against a fake in four lines, and the '
        'first thing that happens then is that it stops being tested.',
    include: ['packages/pk_application/lib'],
    forbid: [
      RegExp(r'''import\s+.package:drift'''),
      RegExp(r'''import\s+.package:pk_data'''),
      RegExp(r'\bSELECT\b.*\bFROM\b'),
    ],
  ),

  // -------------------------------------------------------------------------
  // Money
  // -------------------------------------------------------------------------
  Rule(
    name: 'no_floating_point_money',
    why: 'Money is whole paisa, quantity is thousandths of a base unit, and a '
        'rate is milli-paisa per base unit. A double anywhere in this stack '
        'is a rounding error waiting for a large enough invoice. The old '
        'ledger carried a hardcoded 0.01 tolerance to hide exactly this.',
    include: [
      'packages/pk_money/lib',
      'packages/pk_domain/lib',
      'packages/pk_application/lib',
      'packages/pk_data/lib',
    ],
    forbid: [
      RegExp(r'\bdouble\b'),
      RegExp(r'\.toDouble\(\)'),
      RegExp(r'\bnum\b\s+\w'),
    ],
  ),

  // -------------------------------------------------------------------------
  // The single write path
  // -------------------------------------------------------------------------
  Rule(
    name: 'one_write_path',
    why: 'Every mutation goes through TxRunner, which writes change_log and '
        'audit_log inside the same transaction and asserts the books balance '
        'before commit. A write that goes round it produces a row nobody can '
        'attribute, that no other counter will ever see, and that no '
        'integrity check will ever look at. FirstRunSeeder is the one '
        'exception and says so in its own doc comment: at first run there is '
        'no actor yet for the envelope to name.',
    include: ['packages/pk_data/lib', 'packages/pk_bootstrap/lib'],
    exclude: [
      'pk_data/lib/src/write/tx_runner.dart',
      'pk_data/lib/src/write/first_run.dart',
      'pk_data/lib/src/db/app_database.dart',
    ],
    forbid: [
      RegExp(r'\.customStatement\('),
      RegExp(r'\.customInsert\('),
      RegExp(r'\.customUpdate\('),
      RegExp(r'\bINSERT\s+INTO\b', caseSensitive: false),
      RegExp(r'\bUPDATE\s+\w+\s+SET\b', caseSensitive: false),
      RegExp(r'\bDELETE\s+FROM\b', caseSensitive: false),
    ],
  ),

  Rule(
    name: 'no_hard_delete',
    why: 'Six-year retention under s.24 STA and s.174(3) ITO is a legal '
        'obligation, not a preference, and a shopkeeper who deletes a bill by '
        'accident on a Tuesday wants it back on the Wednesday. Rows are '
        'tombstoned, never destroyed.',
    include: ['lib', 'packages'],
    exclude: ['/test/', 'tool/'],
    forbid: [
      // Upper case only. SQL is written that way throughout this codebase,
      // and `RoundingMode.truncate` is a rounding mode rather than a way to
      // empty a table.
      RegExp(r'\bDROP\s+TABLE\b'),
      RegExp(r'\bTRUNCATE\s+TABLE\b'),
      RegExp(r'\bDELETE\s+FROM\b'),
    ],
    reads: Reads.raw,
  ),

  // -------------------------------------------------------------------------
  // Payments
  // -------------------------------------------------------------------------
  Rule(
    name: 'no_qr_payload_construction',
    why: 'SBP Interoperable QR Standard 8.1(a): the scheme identifier in a QR '
        'payload is issued by the State Bank only to authorised PSO/PSPs. '
        'Breaching an SBP instruction is an offence under s.56 of the PS&EFT '
        'Act 2007 -- up to three years or PKR 3 million. The previous build '
        'minted merchant QRs with an invented pk.raast identifier and a '
        'hardcoded IBAN, and shipped it to every user. We print the '
        "merchant's own alias and IBAN as text, and we re-render a QR image "
        'their own bank gave them. We never build a payload.',
    include: ['lib', 'packages'],
    forbid: [
      RegExp('pk.raast', caseSensitive: false),
      RegExp(r'A000000736'),
      RegExp(r'\bformatTag\b'),
      RegExp(r'\bemvco\b', caseSensitive: false),
      RegExp(r'\bcrc16\b', caseSensitive: false),
      // Any IBAN-shaped literal. A merchant's own IBAN lives in their firm
      // row, typed by them; one in source is somebody else's bank account.
      RegExp(r'''['"]PK\d{2}[A-Z]{4}\d'''),
    ],
    // Tests are exempt because the assertions that prove we do NOT mint a
    // payload have to name the thing they are refusing.
    exclude: ['/test/'],
    reads: Reads.raw,
  ),

  Rule(
    name: 'no_payment_integration',
    why: 'This product records the money; it never moves it. Routing, '
        'switching, settling or holding funds is what triggers PSO/PSP '
        'licensing under Rule 2(p) -- PKR 200 million paid-up capital, and '
        'six licensed operators in the country. A payment mode here is a '
        'label on a ledger row, exactly like the mode column in a paper cash '
        'book, and that is what keeps this outside the perimeter.',
    include: ['lib', 'packages'],
    forbid: [
      RegExp(r'''https?://[^'"]*(jazzcash|easypaisa|hbl|meezan|1link|nift)''',
          caseSensitive: false),
      RegExp(r'\bapi\.raast\b', caseSensitive: false),
    ],
  ),

  // -------------------------------------------------------------------------
  // The interface
  // -------------------------------------------------------------------------
  Rule(
    name: 'no_hardcoded_colour',
    why: 'Colour, type, spacing, radius and motion come from BlTokens. The '
        'previous build had 154 hardcoded Colors.* references against a '
        'ColorScheme nobody used, and shipped a dark mode with white text on '
        'white cards. Tokens are the only place a colour is written down.',
    include: ['lib'],
    exclude: ['lib/design/tokens.dart'],
    forbid: [
      RegExp(r'\bColors\.'),
      RegExp(r'\bColor\(0x'),
    ],
  ),

  Rule(
    name: 'no_hardcoded_user_string',
    why: 'Roman Urdu is the default locale and English is a switch. A literal '
        'in a Text widget is a sentence one of the two audiences cannot '
        'read. Strings come from AppStrings, which is generated from the ARB '
        'files, so a missing translation is a compile error.',
    include: ['lib'],
    forbid: [
      // Text('...') with a literal that contains a letter. Interpolations,
      // single symbols and the empty string are fine.
      RegExp(r'''\bText\(\s*'[^']*[A-Za-z]{2}[^']*'\s*[,)]'''),
    ],
    allowLines: _isLabelledException,
  ),

  Rule(
    name: 'every_icon_button_is_labelled',
    why: 'The previous build had zero Semantics in the entire codebase and '
        'used icon-only buttons as its primary navigation. BlIconButton takes '
        'a required label; a bare IconButton does not.',
    include: ['lib'],
    exclude: ['lib/design/components.dart'],
    forbid: [RegExp(r'\bIconButton\(')],
    allowLines: _isLabelledException,
  ),
];

/// Lines that legitimately match a pattern.
///
/// Two cases only, and both are visible in the source: a `// arch_check:` note
/// naming the reason, or an acronym that is the same word in both languages.
bool _isLabelledException(String line) {
  const sameInBothLanguages = ['NTN', 'STRN', 'IBAN', 'CNIC', 'PDF', 'QR'];
  final match = RegExp(r"'([^']*)'").firstMatch(line);
  if (match == null) return false;
  return sameInBothLanguages.contains(match.group(1));
}
