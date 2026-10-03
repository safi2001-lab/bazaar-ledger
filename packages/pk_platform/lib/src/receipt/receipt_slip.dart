import 'package:pk_domain/pk_domain.dart';

import 'receipt_layout.dart';

/// The till roll as the shop's slip asks for it (M70): as it has printed
/// since M2, tight, or with the total printed large.
///
/// ## Built on the standard layout, not beside it
///
/// Both variants start from the very lines [ReceiptLayout] renders and
/// change only what they are for. "Compact" joins a line to the line under
/// it where the two fit as one, and drops what only spaces the paper out;
/// "Big total" lifts the total and what is owed out of their rows onto
/// lines of their own. Anything this file does not recognise — a line a
/// later milestone adds, a row laid out some other way — is printed exactly
/// as the standard layout printed it. So a new line on the bill reaches
/// every slip without this file knowing it exists, and the worst a change
/// elsewhere can do here is leave a bill one line longer.
///
/// ## The width rule holds
///
/// No line is ever longer than the paper. A joined line is made only when
/// the whole of both fits on one; a large line is at most half the paper,
/// because each of its letters takes two columns.
///
/// ## What a large line looks like on screen
///
/// The printer gets the words and the command to print them twice the
/// size. The preview, the picture sent on WhatsApp and the tests get the
/// same line with its letters spaced out, centred — the two columns each
/// letter takes on the paper — so the preview is still the paper's shape.
final class SlipLine {
  const SlipLine(this.text, {this.big = false});

  /// What the printer is handed. For a large line, at most half the
  /// paper's columns.
  final String text;

  /// Printed twice the width and twice the height.
  final bool big;

  /// The line as the preview shows it on [width] columns.
  String shown(int width) {
    if (!big) return text;
    final spaced = text.split('').join(' ');
    final pad = (width - spaced.length) ~/ 2;
    return '${' ' * (pad < 0 ? 0 : pad)}$spaced';
  }
}

/// [data] on [paper], as its slip lays it out.
List<SlipLine> slipLines(ReceiptData data, ReceiptPaper paper) {
  final standard = ReceiptLayout(paper: paper).render(data);
  final width = paper.columns;
  return switch (data.slip) {
    ReceiptSlip.standard => [for (final l in standard) SlipLine(l)],
    ReceiptSlip.compact => [
      for (final l in _compact(data, standard, width)) SlipLine(l),
    ],
    ReceiptSlip.bigTotal => _bigTotal(data, standard, width),
  };
}

/// The slip as the preview shows it: one string per printed line.
List<String> slipPreview(ReceiptData data, ReceiptPaper paper) => [
  for (final line in slipLines(data, paper)) line.shown(paper.columns),
];

// --- Compact ----------------------------------------------------------------

List<String> _compact(ReceiptData d, List<String> standard, int width) {
  final out = [...standard];
  final rule = '-' * width;

  // The number and the date on one row, where both fit whole — the date
  // with one space where the layout gives it two, which is what lets the
  // pair fit a 58 mm roll.
  final numberRow = _row(d.docLabel, d.docNo, width);
  final dateRow = _row('Date', d.dateTimeLabel, width);
  final date = d.dateTimeLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
  final n = out.indexOf(numberRow);
  if (n >= 0 &&
      n + 1 < out.length &&
      out[n + 1] == dateRow &&
      d.docNo.length + 1 + date.length <= width) {
    out
      ..[n] = _row(d.docNo, date, width)
      ..removeAt(n + 1);
  }

  // No column heads: "Item ... Amount" between two rules says what every
  // line already shows. One rule stays, between who and what.
  final head = _row('Item', d.showsMoney ? 'Amount' : 'Qty', width);
  final h = out.indexOf(head);
  if (h > 0 && h + 1 < out.length && out[h - 1] == rule && out[h + 1] == rule) {
    out.removeRange(h, h + 2);
  }

  // One line an item, where the name and the row under it fit as one. The
  // name is matched whole and the row exactly as the layout made it; a
  // line laid out any other way keeps its two.
  var from = 0;
  for (final line in d.lines) {
    final name = _wrap(line.name, width);
    if (name.length != 1) continue;
    for (var i = from; i + 1 < out.length; i++) {
      if (out[i] != name.single) continue;
      final joined = _joined(line, out[i + 1], d.showsMoney, width);
      if (joined == null) break;
      out
        ..[i] = joined
        ..removeAt(i + 1);
      from = i + 1;
      break;
    }
  }

  // A Subtotal that is the total says it twice, with a rule between.
  final nothingBetween =
      d.discount.isZero &&
      d.tax.isZero &&
      d.furtherTax.isZero &&
      d.withholding.isZero &&
      d.extraCharges.isZero &&
      d.roundOff.isZero &&
      d.subtotal == d.total;
  final subtotal = _row('Subtotal', d.subtotal.amountOnly, width);
  final s = out.indexOf(subtotal);
  if (nothingBetween && s > 0 && out[s - 1] == rule) {
    out.removeRange(s - 1, s + 1);
  }
  return out;
}

/// [line]'s name and [row], the layout's own row under it, as one line —
/// or null when they do not fit whole on [width].
String? _joined(ReceiptLine line, String row, bool money, int width) {
  final name = line.name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (!money) {
    final figure = '${line.qtyDisplay} ${line.unitCode}'.trim();
    final words = line.qtyWords;
    final qty = words == null ? figure : '$figure ($words)';
    if (row != _row('', qty, width)) return null;
    if (name.length + 1 + qty.length > width) return null;
    return _row(name, qty, width);
  }
  final amount = line.amount.amountOnly;
  final short = '  ${line.qtyDisplay} ${line.unitCode}';
  final full = '$short x ${line.rate.amountOnly}';
  final words = line.qtyWords;
  final counted = words == null
      ? null
      : '$short ($words) x ${line.rate.amountOnly}';
  for (final left in [?counted, full, short]) {
    if (row != _row(left, amount, width)) continue;
    final one = '$name ${left.trim()}';
    if (one.length + 1 + amount.length > width) return null;
    return _row(one, amount, width);
  }
  return null;
}

// --- Big total ---------------------------------------------------------------

List<SlipLine> _bigTotal(ReceiptData d, List<String> standard, int width) {
  final half = width ~/ 2;
  // The rows to lift, each to its label and its figure on lines of their
  // own; a figure too long for half the paper stays in its row.
  final lifts = <String, (String, String)>{};
  void lift(String label, Money amount, {required String rowFigure}) {
    final figure = 'Rs ${amount.amountOnly}';
    if (label.length > half || figure.length > half) return;
    lifts[_row(label, rowFigure, width)] = (label, figure);
  }

  if (d.showsMoney) {
    lift('TOTAL', d.total, rowFigure: 'Rs ${d.total.amountOnly}');
    final khata = d.khata;
    if (khata != null && !d.isCancelled) {
      lift('KUL BAQAYA', khata.after, rowFigure: khata.after.amountOnly);
    } else if (d.balance.isPositive) {
      lift('BAQAYA (udhaar)', d.balance, rowFigure: d.balance.amountOnly);
    }
  }
  return [
    for (final line in standard)
      if (lifts[line] case (final label, final figure)) ...[
        SlipLine(label, big: true),
        SlipLine(figure, big: true),
      ] else
        SlipLine(line),
  ];
}

// --- The layout's own arithmetic ---------------------------------------------
//
// The same as ReceiptLayout's, so a row made here is the very string the
// layout made, and can be found by it. Kept here rather than opened up
// there: the layout is every bill's, and this file is the two slips'.

String _row(String left, String right, int width) {
  final r = _clip(right, width);
  final available = width - r.length - 1;
  if (available < 1) return r.padLeft(width);
  final l = _clip(left, available);
  return '$l${' ' * (width - l.length - r.length)}$r';
}

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

List<String> _wrap(String s, int width) {
  final words = s.trim().split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (word.isEmpty) continue;
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
    while (current.length > width) {
      lines.add(current.substring(0, width));
      current = current.substring(width);
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [''] : lines;
}
