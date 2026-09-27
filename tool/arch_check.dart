// Architectural rules, enforced as a build step.
//
// Every rule here exists because the previous build broke it, and because
// breaking it is invisible in review. A folder convention enforces nothing; a
// script that fails the build enforces it every time.
//
//   dart run tool/arch_check.dart
//
// Exit code 1 means a rule was broken, and the output says which file, which
// line, and why.
//
// Deliberately a plain script over `dart:io` rather than a `custom_lint`
// plugin. A lint plugin keeps three packages version-locked against the
// analyzer, and an analyzer bump that silently disables the rules is worse
// than no rules — you keep the green tick and lose the guarantee.
//
// That failure mode is not hypothetical here. The first version of this file
// stripped string literals from every line before matching, so that a rule
// about the `double` type would not fire on the word "double" in its own
// error message. Six of the twelve rules match patterns that live INSIDE a
// literal — every import path, every URL, every user-visible string — and all
// six were silently inert while the script printed "12 rules, no violations".
//
// So every rule now carries its own fixtures: lines it must flag, and lines it
// must not. They run before the tree is scanned, and a rule that cannot fire
// fails the build instead of passing it.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final broken = _selfTest();
  if (broken.isNotEmpty) {
    stderr.writeln(
      'arch_check: ${broken.length} rule(s) do not work.\n\n'
      'A rule that cannot fire is worse than no rule: it keeps the green '
      'tick and loses the guarantee.\n',
    );
    for (final failure in broken) {
      stderr.writeln('  $failure');
    }
    exit(1);
  }

  final violations = <Violation>[];
  for (final rule in rules) {
    violations.addAll(rule.run());
  }

  if (violations.isEmpty) {
    final exemptions = _exemptions();
    stdout.writeln(
      'arch_check: ${rules.length} rules, self-tested, no violations, '
      '${exemptions.length} written exemption(s).',
    );
    for (final e in exemptions) {
      stdout.writeln('  exempt: $e');
    }
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

/// Checks that every rule flags what it claims to and permits what it must.
///
/// Two halves, and both matter. A rule that cannot fire keeps the green tick
/// and loses the guarantee; a rule broad enough to fire on ordinary code is a
/// rule everybody turns off.
List<String> _selfTest() {
  final failures = <String>[];
  for (final rule in rules) {
    if (rule.mustFlag.isEmpty) {
      failures.add('${rule.name}: has no fixture proving it can fire.');
      continue;
    }
    for (final line in rule.mustFlag) {
      if (!rule.matches(line)) {
        failures.add('${rule.name}: fails to flag  $line');
      }
    }
    for (final line in rule.mustAllow) {
      if (rule.matches(line)) {
        failures.add('${rule.name}: wrongly flags  $line');
      }
    }
  }

  // And against real, wrapped code rather than one-liners. `tool/fixtures/`
  // holds a file every rule must find something in and a file no rule may
  // touch, both formatted the way `dart format` would actually leave them.
  final bad = File('tool/fixtures/wrapped_text.dart.txt');
  final good = File('tool/fixtures/wrapped_ok.dart.txt');
  if (!bad.existsSync() || !good.existsSync()) {
    failures.add('tool/fixtures: the wrapped-code fixtures are missing.');
    return failures;
  }

  final badSource = bad.readAsStringSync();
  final goodSource = good.readAsStringSync();
  const wrapped = {
    'ui_cannot_reach_the_database': false,
    'no_hardcoded_user_string': true,
    'no_hardcoded_colour': true,
    'every_icon_button_is_labelled': true,
    'one_write_path': true,
    'no_raw_dml': true,
    'no_payment_integration': true,
    'no_qr_payload_construction': true,
    'no_floating_point_money': true,
  };
  for (final rule in rules) {
    if (wrapped[rule.name] != true) continue;
    if (!rule.matches(badSource)) {
      failures.add(
        '${rule.name}: cannot see wrapped code — it would miss every call '
        '`dart format` broke across lines.',
      );
    }
    if (rule.matches(goodSource)) {
      failures.add('${rule.name}: fires on ordinary wrapped code.');
    }
  }
  return failures;
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
  /// The line exactly as written, literals included. The right choice for
  /// every rule whose subject IS a literal: an import path, a URL, a sentence
  /// shown to a shopkeeper.
  raw,

  /// Code with the contents of string literals blanked out. For rules about
  /// the language rather than the text — a rule about the `double` type must
  /// not fire on the word "double" in its own error message.
  code,

  /// String literals with `${...}` interpolations removed, so a rule about
  /// untranslated prose does not fire on `Text('$count')`.
  prose,

  /// The line as written, comments included.
  ///
  /// Every other mode blanks comments before matching, which is right for a
  /// rule about the language: one about `double` must not fire on the word
  /// "double" in the sentence explaining why doubles are refused. But a rule
  /// whose subject IS the prose — a citation of a mechanism that does not
  /// exist, a legal claim with no statute behind it — needs to read them, and
  /// with the others it would pass while being unable to see its own subject.
  everything;

  String apply(String line) => switch (this) {
    Reads.raw || Reads.everything => line,
    Reads.code =>
      line
          .replaceAll(RegExp(r"'[^']*'"), "''")
          .replaceAll(RegExp(r'"[^"]*"'), '""'),
    Reads.prose =>
      line
          .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
          .replaceAll(RegExp(r'\$\w+'), ''),
  };
}

/// One rule: which files it looks at, and what it refuses to find in them.
final class Rule {
  const Rule({
    required this.name,
    required this.why,
    required this.include,
    required this.forbid,
    required this.mustFlag,
    this.mustAllow = const [],
    this.exclude = const [],
    this.reads = Reads.code,
    this.allowLines,
  });

  final String name;

  /// Written for whoever trips over it at 2am, not for whoever wrote it.
  final String why;

  /// Path prefixes this rule applies to, relative to the repository root.
  final List<String> include;

  /// Path fragments exempt from it, each justified in the rule's own `why`.
  final List<String> exclude;

  final List<RegExp> forbid;

  /// Lines this rule MUST flag. Without one, the rule does not run at all.
  final List<String> mustFlag;

  /// Lines this rule must NOT flag. Guards against a pattern so broad that it
  /// stops anyone writing ordinary code.
  final List<String> mustAllow;

  final Reads reads;

  /// A last-resort escape hatch for a line that legitimately matches.
  final bool Function(String line)? allowLines;

  /// Whether this rule flags [source], which may be one line or a whole file.
  bool matches(String source) => _matchesIn(_prepare(source)).isNotEmpty;

  /// Blanks out what the rule must not see, keeping every character position
  /// so a match can still be turned back into a line number.
  ///
  /// Comments go first: a rule about the `double` type must not fire on the
  /// word "double" in the sentence explaining why doubles are refused. An
  /// `arch_check: allow` note blanks its own line.
  String _prepare(String source) {
    final buffer = StringBuffer();
    for (final line in const LineSplitter().convert(source)) {
      final trimmed = line.trimLeft();
      final suppressed =
          (trimmed.startsWith('//') && reads != Reads.everything) ||
          _isExemptFrom(line, name);
      if (suppressed || (allowLines != null && allowLines!(line))) {
        buffer.writeln(' ' * line.length);
      } else {
        buffer.writeln(reads.apply(line));
      }
    }
    return buffer.toString();
  }

  List<Match> _matchesIn(String prepared) => [
    for (final p in forbid) ...p.allMatches(prepared),
  ];

  List<Violation> run() {
    final found = <Violation>[];
    for (final path in include) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalised = entity.path.replaceAll(Platform.pathSeparator, '/');
        if (normalised.contains('/build/')) continue;
        if (normalised.contains('/.dart_tool/')) continue;
        if (normalised.endsWith('.g.dart')) continue;
        if (normalised.endsWith('.drift.dart')) continue;
        if (exclude.any(normalised.contains)) continue;

        // The whole file at once, because real code wraps. Every rule used to
        // read one line at a time and every fixture was a synthetic
        // one-liner, so the three lines `dart format` turns a long `Text(...)`
        // call into were invisible to the rule written to catch it. Fifty-four
        // call sites in this app are wrapped that way.
        final source = entity.readAsStringSync();
        final prepared = _prepare(source);
        final lines = const LineSplitter().convert(source);

        final seen = <int>{};
        for (final match in _matchesIn(prepared)) {
          final before = prepared.substring(0, match.start);
          final line = '\n'.allMatches(before).length + 1;
          if (!seen.add(line)) continue;
          found.add(
            Violation(
              rule: name,
              file: normalised,
              line: line,
              source: line <= lines.length ? lines[line - 1] : '',
            ),
          );
        }
      }
    }
    return found;
  }
}

final rules = <Rule>[
  // ---------------------------------------------------------------------------
  // Layering
  // ---------------------------------------------------------------------------
  Rule(
    name: 'ui_cannot_reach_the_database',
    why:
        'The app package does not list pk_data or drift in its pubspec, so '
        'this is already a resolution error. The rule exists so that adding '
        'the dependency "just for one screen" fails here, loudly, rather '
        'than passing review because the import looked harmless.',
    include: ['lib'],
    reads: Reads.raw,
    forbid: [
      RegExp('''^\\s*import\\s+['"]package:drift'''),
      RegExp('''^\\s*import\\s+['"]package:pk_data'''),
      RegExp('''^\\s*import\\s+['"]package:sqlite3'''),
    ],
    mustFlag: [
      "import 'package:drift/drift.dart';",
      'import "package:pk_data/pk_data.dart";',
      "import 'package:sqlite3/open.dart';",
    ],
    mustAllow: [
      "import 'package:pk_bootstrap/pk_bootstrap.dart';",
      "import 'package:flutter/material.dart';",
      "// import 'package:drift/drift.dart';",
    ],
  ),

  Rule(
    name: 'domain_is_pure',
    why:
        'pk_domain holds the posting rules. It knows nothing about SQL, '
        'Flutter, files or the network, which is what lets every rule in it '
        'be tested exhaustively without a database, and what keeps a UI '
        'concern from quietly becoming an accounting one.',
    include: ['packages/pk_domain/lib', 'packages/pk_money/lib'],
    reads: Reads.raw,
    forbid: [
      RegExp('''^\\s*import\\s+['"]package:drift'''),
      RegExp('''^\\s*import\\s+['"]package:flutter'''),
      RegExp('''^\\s*import\\s+['"]package:pk_data'''),
      RegExp('''^\\s*import\\s+['"]dart:io'''),
      RegExp('''^\\s*import\\s+['"]dart:ui'''),
    ],
    mustFlag: [
      "import 'package:flutter/material.dart';",
      "import 'dart:io';",
      "import 'package:drift/drift.dart';",
    ],
    mustAllow: [
      "import 'dart:convert';",
      "import 'package:pk_money/pk_money.dart';",
    ],
  ),

  Rule(
    name: 'reports_hold_no_sql',
    why:
        'A report is a pure builder over rows a ReportSource reads, and an '
        'export is a pure encoding of the finished table. The SQL lives in '
        'pk_data behind the port, so every total on every report can be '
        'tested without a database, and no screen can add a figure up itself.',
    include: ['packages/pk_reports/lib', 'packages/pk_export/lib'],
    reads: Reads.raw,
    forbid: [
      RegExp('''^\\s*import\\s+['"]package:drift'''),
      RegExp('''^\\s*import\\s+['"]package:flutter'''),
      RegExp('''^\\s*import\\s+['"]package:pk_data'''),
      RegExp('''^\\s*import\\s+['"]dart:io'''),
      RegExp(r'\bSELECT\b.*\bFROM\b'),
    ],
    mustFlag: [
      "import 'package:pk_data/pk_data.dart';",
      "import 'package:flutter/material.dart';",
      "  final rows = await db.select('SELECT id FROM items');",
    ],
    mustAllow: [
      "import 'package:pk_domain/pk_domain.dart';",
      "import 'dart:convert';",
    ],
  ),

  Rule(
    name: 'money_has_no_dependencies',
    why:
        'pk_money is the bottom of the stack. Everything else may depend on '
        'it; it depends on nothing, so there is no version of this codebase '
        'in which the definition of a rupee is affected by a package bump.',
    include: ['packages/pk_money/lib'],
    reads: Reads.raw,
    forbid: [RegExp('''^\\s*import\\s+['"]package:(?!pk_money)''')],
    mustFlag: [
      "import 'package:collection/collection.dart';",
      "import 'package:meta/meta.dart';",
    ],
    mustAllow: [
      "import 'dart:math';",
      "import 'package:pk_money/src/money.dart';",
      "import 'money.dart';",
    ],
  ),

  Rule(
    name: 'application_layer_holds_no_sql',
    why:
        'Use cases orchestrate ports. A use case that writes SQL is one that '
        'cannot be tested against a fake in four lines, and the first thing '
        'that happens then is that it stops being tested.',
    include: ['packages/pk_application/lib'],
    reads: Reads.raw,
    forbid: [
      RegExp('''^\\s*import\\s+['"]package:drift'''),
      RegExp('''^\\s*import\\s+['"]package:pk_data'''),
      RegExp(r'\bSELECT\b.*\bFROM\b'),
      RegExp(r'\bINSERT\s+INTO\b'),
    ],
    mustFlag: [
      "import 'package:pk_data/pk_data.dart';",
      "  final rows = await db.select('SELECT id FROM items');",
      "  await db.customStatement('INSERT INTO items (id) VALUES (?)');",
    ],
    mustAllow: [
      "import 'package:pk_domain/pk_domain.dart';",
      '  final selected = lines.where((l) => l.isFreeItem);',
    ],
  ),

  // ---------------------------------------------------------------------------
  // Money
  // ---------------------------------------------------------------------------
  Rule(
    name: 'no_floating_point_money',
    why:
        'Money is whole paisa, quantity is thousandths of a base unit, and a '
        'rate is milli-paisa per base unit. A double anywhere in this stack '
        'is a rounding error waiting for a large enough invoice. The old '
        'ledger carried a hardcoded 0.01 tolerance to hide exactly this.',
    include: [
      'packages/pk_money/lib',
      'packages/pk_domain/lib',
      'packages/pk_application/lib',
      'packages/pk_data/lib',
      'packages/pk_reports/lib',
      'packages/pk_export/lib',
    ],
    reads: Reads.code,
    forbid: [
      RegExp(r'\bdouble\b'),
      RegExp(r'\.toDouble\(\)'),
      RegExp(r'\bnum\b\s+\w'),
      // A decimal literal IS a double, whatever it is assigned to.
      RegExp(r'(?<![\w.])\d+\.\d'),
      // `/` on two ints returns a double in Dart. Integer division is `~/`,
      // and every rounding decision goes through `divideRounded` with an
      // explicit mode.
      RegExp(r'[\w)\]]\s*(?<!~)/\s*[\w(]'),
    ],
    mustFlag: [
      '  final double total = 0;',
      '  return amount.toDouble();',
      '  num quantity = 1;',
      '  final share = 0.5;',
      '  final each = total / count;',
    ],
    mustAllow: [
      "      'a double here would be money represented as a float',",
      '  final int total = 0;',
      '  final each = total ~/ count;',
      '  final rate = divideRounded(a, b, mode);',
    ],
  ),

  // ---------------------------------------------------------------------------
  // The single write path
  // ---------------------------------------------------------------------------
  Rule(
    name: 'one_write_path',
    why:
        'Every mutation goes through TxRunner, which writes change_log and '
        'audit_log inside the same transaction and asserts the books balance '
        'before commit. A write that goes round it produces a row nobody can '
        'attribute, that no other counter will ever see, and that no '
        "integrity check will ever look at. Drift's typed API counts: "
        '`into(x).insert(...)` skips exactly the same guarantees as raw SQL '
        'and reads more innocently. FirstRunSeeder is one exception and '
        'says so in its own doc comment: at first run there is no actor yet '
        'for the envelope to name. DriftSyncStore is the other: it writes '
        'only rows another device already wrote through its own TxRunner, '
        'with that envelope intact, and keeps the outbox entry they came in.',
    include: ['packages/pk_data/lib', 'packages/pk_bootstrap/lib'],
    exclude: [
      'pk_data/lib/src/write/tx_runner.dart',
      'pk_data/lib/src/write/first_run.dart',
      'pk_data/lib/src/db/app_database.dart',
      'pk_data/lib/src/sync/drift_sync_store.dart',
    ],
    reads: Reads.code,
    forbid: [
      RegExp(r'\.customStatement\('),
      RegExp(r'\.customInsert\('),
      RegExp(r'\.customUpdate\('),
      RegExp(r'\.customDelete\('),
      RegExp(r'\binto\s*\([\w.]+\)\s*\.\s*insert'),
      RegExp(r'\bupdate\s*\([\w.]+\)\s*\.\s*write'),
      RegExp(r'\bdelete\s*\([\w.]+\)\s*\.\s*go'),
      RegExp(r'\.batch\('),
    ],
    mustFlag: [
      '    await db.customStatement(sql, args);',
      '    await db.into(db.items).insert(companion);',
      '    await db.update(db.payments).write(companion);',
      '    await db.delete(db.items).go();',
      '    await db.batch((b) => b.insertAll(db.items, rows));',
    ],
    mustAllow: [
      '    await tx.insert(table, values);',
      '    final rows = await tx.select(sql, args);',
      '    await db.customSelect(sql).get();',
    ],
  ),

  Rule(
    name: 'no_raw_dml',
    why:
        'The same rule, for SQL written as text. Kept separate because it '
        'has to read inside string literals, and a rule that reads literals '
        'cannot also be the rule that ignores its own error messages. Rows '
        'are tombstoned, never destroyed: six-year retention under s.24 STA '
        'and s.174(3) ITO is a legal obligation, and a shopkeeper who deletes '
        'a bill by accident on a Tuesday wants it back on the Wednesday.',
    include: ['packages/pk_data/lib', 'packages/pk_bootstrap/lib', 'lib'],
    exclude: [
      'pk_data/lib/src/write/tx_runner.dart',
      'pk_data/lib/src/write/first_run.dart',
      // Merges rows other devices wrote; see one_write_path.
      'pk_data/lib/src/sync/drift_sync_store.dart',
    ],
    reads: Reads.raw,
    forbid: [
      RegExp(r'\bINSERT\s+INTO\b'),
      RegExp(r'\bUPDATE\s+\w+\s+SET\b'),
      RegExp(r'\bDELETE\s+FROM\b'),
      RegExp(r'\bDROP\s+(TABLE|INDEX|TRIGGER)\b'),
      RegExp(r'\bTRUNCATE\s+TABLE\b'),
    ],
    mustFlag: [
      "        'INSERT INTO items (id) VALUES (?)',",
      "        'UPDATE payments SET amount_paisa = ?',",
      "        'DELETE FROM documents WHERE id = ?',",
      "        'DROP TABLE items',",
    ],
    mustAllow: [
      "        'SELECT * FROM items WHERE firm_id = ?',",
      '      RoundingMode.truncate => 0,',
    ],
  ),

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------
  Rule(
    name: 'no_qr_payload_construction',
    why:
        'SBP Interoperable QR Standard 8.1(a): the scheme identifier in a QR '
        'payload is issued by the State Bank only to authorised PSO/PSPs. '
        'Breaching an SBP instruction is an offence under s.56 of the PS&EFT '
        'Act 2007 — up to three years or PKR 3 million. The previous build '
        'minted merchant QRs with an invented pk.raast identifier and a '
        'hardcoded IBAN, and shipped it to every user. We print the '
        "merchant's own alias and IBAN as text, and we re-render a QR image "
        'their own bank gave them. We never build a payload. Tests are '
        'exempt because the assertions proving we do NOT mint one have to '
        'name the thing they are refusing.',
    include: ['lib', 'packages'],
    exclude: ['/test/'],
    reads: Reads.raw,
    forbid: [
      RegExp('pk.raast', caseSensitive: false),
      RegExp('A000000736'),
      RegExp(r'\bformatTag\b'),
      RegExp(r'\bemvco\b', caseSensitive: false),
      RegExp(r'\bcrc16\b', caseSensitive: false),
      RegExp('''['"]PK\\d{2}[A-Z]{4}\\d'''),
    ],
    mustFlag: [
      "  const guid = 'pk.raast';",
      "  const scheme = 'A000000736';",
      "  final tag = formatTag('26', payload);",
      "  const iban = 'PK36MEZN0001234567890101';",
    ],
    mustAllow: [
      '  final alias = firm.raastAlias;',
      '  Text(s.settingsRaastAlias),',
    ],
  ),

  Rule(
    name: 'no_payment_integration',
    why:
        'This product records the money; it never moves it. Routing, '
        'switching, settling or holding funds triggers PSO/PSP licensing '
        'under Rule 2(p) — PKR 200 million paid-up capital, and six licensed '
        'operators in the country. A payment mode here is a label on a '
        'ledger row, exactly like the mode column in a paper cash book, and '
        'that is what keeps this outside the perimeter.',
    include: ['lib', 'packages'],
    reads: Reads.raw,
    forbid: [
      RegExp(
        '''https?://[^'"\\s]*(jazzcash|easypaisa|hbl|meezan|1link|nift|raast)''',
        caseSensitive: false,
      ),
    ],
    mustFlag: [
      "  const endpoint = 'https://api.jazzcash.com.pk/v1/pay';",
      '  const url = "http://sandbox.easypaisa.com.pk/token";',
    ],
    mustAllow: [
      "  'jazzcash': (label: s.tenderModeJazzCash, icon: Icons.smartphone),",
      "  const raastAlias = '03001234567';",
    ],
  ),

  // ---------------------------------------------------------------------------
  // The interface
  // ---------------------------------------------------------------------------
  Rule(
    name: 'no_hardcoded_colour',
    why:
        'Colour, type, spacing, radius and motion come from BlTokens. The '
        'previous build had 154 hardcoded Colors.* references against a '
        'ColorScheme nobody used, and shipped a dark mode with white text on '
        'white cards. Tokens are the only place a colour is written down.',
    include: ['lib'],
    exclude: ['lib/design/tokens.dart'],
    reads: Reads.code,
    forbid: [
      RegExp(r'\bColors\.'),
      RegExp(r'\bColor\(0[xX]'),
      RegExp(r'\bColor\.from(ARGB|RGBO)\('),
    ],
    mustFlag: [
      '  color: Colors.white,',
      '  color: const Color(0xFF112233),',
      '  color: const Color(0XFF112233),',
      '  color: Color.fromARGB(255, 1, 2, 3),',
      '  color: Color.fromRGBO(1, 2, 3, 1),',
    ],
    mustAllow: [
      '  color: t.ink,',
      '  final Color colour;',
      '  color: context.bl.accent,',
    ],
  ),

  Rule(
    name: 'no_hardcoded_user_string',
    why:
        'Roman Urdu is the default locale and English is a switch. A literal '
        'in a Text widget is a sentence one of the two audiences cannot '
        'read. Strings come from AppStrings, generated from the ARB files, so '
        'a missing translation is a compile error rather than a blank label.',
    include: ['lib'],
    reads: Reads.prose,
    forbid: [
      RegExp('''\\bText\\(\\s*'[^']*[A-Za-z]{2}[^']*'\\s*[,)]'''),
      RegExp('''\\bText\\(\\s*"[^"]*[A-Za-z]{2}[^"]*"\\s*[,)]'''),
      RegExp(
        '''\\b(hintText|tooltip|labelText|semanticLabel):\\s*'[^']*[A-Za-z]{2}''',
      ),
    ],
    mustFlag: [
      "        child: Text('Add customer'),",
      '        child: Text("Add customer"),',
      "        hintText: 'Type a name',",
      "        tooltip: 'Close the bill',",
    ],
    mustAllow: [
      '        child: Text(s.partiesAdd),',
      r"        child: Text('$count'),",
      r"        child: Text('${u.name} (${u.code})'),",
      "        child: Text('NTN'),",
    ],
    allowLines: _isLabelledException,
  ),

  Rule(
    name: 'every_icon_button_is_labelled',
    why:
        'The previous build had zero Semantics in the entire codebase and '
        'used icon-only buttons as its primary navigation. BlIconButton takes '
        'a required label; a bare IconButton does not.',
    include: ['lib'],
    exclude: ['lib/design/components.dart'],
    reads: Reads.code,
    forbid: [RegExp(r'(?<!Bl)\bIconButton(\.\w+)?\s*\(')],
    mustFlag: [
      '            child: IconButton(',
      '            child: IconButton.filled(',
      '            child: IconButton.outlined(',
    ],
    mustAllow: [
      '            child: BlIconButton(',
      '  final Widget? trailing;',
    ],
  ),

  Rule(
    name: 'no_phantom_gate',
    why:
        'A package called pk_lints was two empty directories for weeks. Two '
        'source files cited its rules as build-time guarantees, and the melos '
        'step that claimed to run it matched no package and exited zero. '
        'Nothing was enforced and three things said it was. This rule exists '
        'so that name, and the tool it pretended to use, cannot be typed back '
        'in without somebody building the thing first.',
    include: ['lib', 'packages', 'tool'],
    exclude: ['tool/arch_check.dart'],
    reads: Reads.everything,
    forbid: [
      RegExp(r'\bpk_lints\b'),
      RegExp(r'\bcustom_lint\b'),
      RegExp(r'\bno_db_write_outside_uow\b'),
      RegExp(r'\bno_hardcoded_color\b'),
    ],
    mustFlag: [
      '/// no_db_write_outside_uow in pk_lints makes this a build failure.',
      '  custom_lint: ^0.6.0',
      '/// The no_hardcoded_color rule forbids a literal.',
    ],
    mustAllow: [
      '/// The `one_write_path` rule in `tool/arch_check.dart` forbids this.',
      '/// The `no_hardcoded_colour` rule makes a literal a build failure.',
    ],
  ),
];

/// Whether a line carries a written exemption from a particular rule.
///
/// The marker has to name the rule and give a reason: `arch_check: allow
/// no_raw_dml — derived cache`. A bare `arch_check: allow` used to silence
/// every rule on the line, for nobody's stated reason, and nothing counted
/// them — which is how a suppression list becomes the real architecture.
bool _isExemptFrom(String line, String rule) {
  final match = _exemption.firstMatch(line);
  if (match == null) return false;
  return match.group(1) == rule;
}

final RegExp _exemption = RegExp(r'arch_check:\s*allow\s+(\w+)\s*[—-]\s*\S');

/// Every written exemption in the tree, so they cannot pile up unnoticed.
List<String> _exemptions() {
  final found = <String>[];
  for (final path in const ['lib', 'packages', 'tool']) {
    final dir = Directory(path);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalised = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (normalised.contains('/build/')) continue;
      if (normalised.contains('/.dart_tool/')) continue;
      if (normalised.endsWith('arch_check.dart')) continue;
      final lines = const LineSplitter().convert(entity.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        if (_exemption.hasMatch(lines[i])) {
          found.add('$normalised:${i + 1}');
        }
      }
    }
  }
  return found;
}

/// Lines that legitimately match a pattern.
///
/// One case only, and it is visible in the source: an acronym that is the same
/// word in Roman Urdu and English. Deliberately checks EVERY literal on the
/// line rather than the first, so `Text('NTN'), Text('Add customer')` is not
/// whitelisted wholesale by its opening word.
bool _isLabelledException(String line) {
  const sameInBothLanguages = {'NTN', 'STRN', 'IBAN', 'CNIC', 'PDF', 'QR'};
  final literals = RegExp(r"'([^']*)'")
      .allMatches(line)
      .map((m) => m.group(1)!)
      .where((l) => RegExp('[A-Za-z]{2}').hasMatch(l))
      .toList();
  if (literals.isEmpty) return false;
  return literals.every(sameInBothLanguages.contains);
}
