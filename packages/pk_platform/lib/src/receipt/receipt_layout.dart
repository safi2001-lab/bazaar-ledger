import 'package:pk_domain/pk_domain.dart';

/// Lays a receipt out as fixed-width text.
///
/// Kept separate from the byte encoding so the layout can be golden-tested as
/// readable strings and shown on screen as a print preview. What the shopkeeper
/// sees in the preview is the same string the printer is handed.
///
/// The column arithmetic matters more than it looks. 80 mm Font A is exactly
/// 48 columns and 58 mm is 32; a layout that assumes 48 and is sent to a 58 mm
/// printer wraps every money line and produces a receipt nobody can read. The
/// design mock this was built from claimed 48 columns and was actually 36,
/// with every amount overhanging by one character, so the numbers below are
/// the printer's and not the mock's.
final class ReceiptLayout {
  const ReceiptLayout({this.paper = ReceiptPaper.mm80});

  final ReceiptPaper paper;

  int get width => paper.columns;

  List<String> render(ReceiptData d) {
    final out = <String>[];

    void rule([String ch = '-']) => out.add(ch * width);
    void centred(String s) {
      for (final part in _wrap(s, width)) {
        out.add(_centre(part));
      }
    }

    // --- Head ------------------------------------------------------------
    centred(d.shop.name.toUpperCase());
    final where = [d.shop.addressLine1, d.shop.city]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    if (where.isNotEmpty) centred(where);
    if (_has(d.shop.phone)) centred(d.shop.phone!);
    // Printed only when the shop holds one. Most kiryana stores do not, and a
    // blank "NTN:" line on every receipt is worse than no line.
    if (_has(d.shop.ntn)) centred('NTN ${d.shop.ntn}');
    if (_has(d.shop.strn)) centred('STRN ${d.shop.strn}');

    rule('=');
    if (d.isReprint) {
      centred('** REPRINT **');
      rule('-');
    }

    // --- Invoice ---------------------------------------------------------
    out.add(_row('Bill No', d.docNo));
    out.add(_row('Date', d.dateTimeLabel));
    out.add(_row('Cashier', _clip(d.cashierName, width - 10)));
    if (_has(d.customerName)) {
      out.add(_row('Customer', _clip(d.customerName!, width - 11)));
    }
    if (_has(d.customerPhone)) {
      out.add(_row('Phone', d.customerPhone!));
    }

    rule('-');
    out.add(_row('Item', 'Amount'));
    rule('-');

    // --- Lines -----------------------------------------------------------
    //
    // Two lines per item: the name on its own, then quantity and rate on the
    // left with the amount hard against the right margin. Trying to fit all
    // four fields on one row is what makes 58 mm receipts illegible, and item
    // names in this market are long.
    for (final line in d.lines) {
      for (final part in _wrap(line.name, width)) {
        out.add(part);
      }
      // Quantity, unit and rate on the left; the amount hard against the
      // right margin. `_row` clips the left when they collide, which is right
      // for an item name and wrong for a number: at 32 columns with a
      // shop-created unit code like `bori-50kg`, the rate was the thing that
      // got cut, and "x 12,4" on a receipt the customer keeps is worse than
      // no rate at all. So the whole rate is dropped rather than truncated.
      final full =
          '  ${line.qtyDisplay} ${line.unitCode} x ${line.rate.amountOnly}';
      final amount = line.amount.amountOnly;
      final room = width - amount.length - 1;
      final detail = full.length <= room
          ? full
          : '  ${line.qtyDisplay} ${line.unitCode}';
      out.add(_row(detail, amount));
      if (line.discount.isPositive) {
        out.add(_row('    less discount', '-${line.discount.amountOnly}'));
      }
      if (line.isFreeItem) {
        out.add('    (free)');
      }
    }

    rule('-');

    // --- Totals ----------------------------------------------------------
    out.add(_row('Subtotal', d.subtotal.amountOnly));
    if (d.discount.isPositive) {
      out.add(_row('Discount', '-${d.discount.amountOnly}'));
    }
    if (d.tax.isPositive) out.add(_row('Sales Tax', d.tax.amountOnly));
    if (d.furtherTax.isPositive) {
      out.add(_row('Further Tax', d.furtherTax.amountOnly));
    }
    if (d.withholding.isPositive) {
      // Deducted, so it prints as a deduction. Without this line the printed
      // components did not reconcile to the printed total and nothing on the
      // paper said why.
      out.add(_row('Withholding', '-${d.withholding.amountOnly}'));
    }
    if (d.extraCharges.isPositive) {
      out.add(_row('Other Charges', d.extraCharges.amountOnly));
    }
    if (!d.roundOff.isZero) {
      out.add(_row('Round Off', d.roundOff.signed.replaceAll('Rs ', '')));
    }
    rule('=');
    out.add(_row('TOTAL', 'Rs ${d.total.amountOnly}'));
    rule('=');

    // --- Tenders ---------------------------------------------------------
    for (final tender in d.tenders) {
      out.add(_row(tender.label, tender.amount.amountOnly));
      if (_has(tender.reference)) {
        out.add('   Ref: ${_clip(tender.reference!, width - 8)}');
      }
    }
    if (d.change.isPositive) {
      out.add(_row('Change', d.change.amountOnly));
    }
    if (d.balance.isPositive) {
      rule('-');
      out.add(_row('BAQAYA (udhaar)', d.balance.amountOnly));
      if (d.previousBalance != null && d.previousBalance!.isPositive) {
        out.add(_row('Purana baqaya', d.previousBalance!.amountOnly));
        out.add(_row('Total baqaya', d.runningBalance.amountOnly));
      }
    }

    // --- How to pay ------------------------------------------------------
    //
    // The shop's own alias and IBAN, as text. Nothing here is a QR payload:
    // the scheme identifier is issued by the State Bank to licensed PSO/PSPs
    // only, and minting one is an offence under s.56 PS&EFT Act. A QR the
    // merchant's bank gave them is printed as an image, never generated.
    final payTo = <String>[
      if (_has(d.shop.raastAlias)) 'Raast: ${d.shop.raastAlias}',
      if (_has(d.shop.bankAccountTitle) && _has(d.shop.bankIban))
        '${d.shop.bankName ?? 'Bank'}: ${d.shop.bankIban}',
      if (_has(d.shop.bankAccountTitle)) 'Title: ${d.shop.bankAccountTitle}',
    ];
    if (payTo.isNotEmpty) {
      rule('-');
      centred('Payment ke liye');
      for (final l in payTo) {
        for (final part in _wrap(l, width)) {
          out.add(_centre(part));
        }
      }
    }

    rule('=');
    out.add(_centre('${d.itemCount} item(s)'));
    for (final footer in d.footerLines) {
      for (final part in _wrap(footer, width)) {
        out.add(_centre(part));
      }
    }

    return out;
  }

  /// `left` flush left, `right` flush right, padded to [width].
  ///
  /// When they will not both fit, the left is clipped — an amount that lost
  /// its last digit is a wrong receipt, an item name that lost its last word
  /// is a legible one.
  String _row(String left, String right) {
    // The right side is clipped too. `padLeft` is a no-op when the string is
    // already longer than the width, so a right-hand value that overran —
    // a customer's phone number is free text, and the one field never clipped
    // by its caller — produced a line longer than the paper, silently.
    final r = _clip(right, width);
    final available = width - r.length - 1;
    if (available < 1) return r.padLeft(width);
    final l = _clip(left, available);
    return '$l${' ' * (width - l.length - r.length)}$r';
  }

  String _centre(String s) {
    if (s.length >= width) return s.substring(0, width);
    final pad = (width - s.length) ~/ 2;
    return '${' ' * pad}$s';
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  /// Wraps on word boundaries, breaking a word only when it is longer than the
  /// paper.
  static List<String> _wrap(String s, int width) {
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
}
