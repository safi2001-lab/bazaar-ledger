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

    // A label and a free-text value (M51): one row when both fit, otherwise
    // the label on a line of its own and the value wrapped under it. Never
    // clipped — an address cut short is goods delivered to the wrong shop.
    void labelled(String label, String value) {
      final v = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (label.length + 1 + v.length <= width) {
        out.add(_row(label, v));
        return;
      }
      out.add(label);
      for (final part in _wrap(v, width - 2)) {
        out.add('  $part');
      }
    }

    // --- Head ------------------------------------------------------------
    centred(d.shop.name.toUpperCase());
    final where = [
      d.shop.addressLine1,
      d.shop.city,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    if (where.isNotEmpty) centred(where);
    if (_has(d.shop.phone)) centred(d.shop.phone!);
    // Printed only when the shop holds one. Most kiryana stores do not, and a
    // blank "NTN:" line on every receipt is worse than no line.
    if (_has(d.shop.ntn)) centred('NTN ${d.shop.ntn}');
    if (_has(d.shop.strn)) centred('STRN ${d.shop.strn}');

    rule('=');
    // Before anything else on the bill, so neither can be missed (M30). A
    // cancelled bill says so above its lines, where a customer reading what
    // they owe looks first; a copy says it is not the original.
    if (d.isCancelled) {
      centred('** CANCELLED / MANSOOKH **');
      rule('-');
    }
    // Which sheet this is (M51): the duplicate M30 marks on its own, or the
    // sheet somebody chose. The transporter's copy says, under its mark,
    // that the prices are missing on purpose — a driver handed a bill with
    // no amounts on it otherwise assumes the printer ran out of ink.
    final copy = d.copyMark;
    final money = d.showsMoney;
    if (copy != null) {
      centred('** ${copy.mark} **');
      if (!copy.showsMoney) centred('(qeemat ke baghair)');
      rule('-');
    }

    // --- Invoice ---------------------------------------------------------
    out.add(_row(d.docLabel, d.docNo));
    out.add(_row('Date', d.dateTimeLabel));
    out.add(_row('Cashier', _clip(d.cashierName, width - 10)));
    if (_has(d.customerName)) {
      // "Supplier" on a purchase bill shown back (M30); "Customer" on
      // everything the shop issues. The same width either way.
      out.add(_row(d.partyLabel, _clip(d.customerName!, width - 11)));
    }
    if (_has(d.customerPhone)) {
      out.add(_row('Phone', d.customerPhone!));
    }
    // Where the goods go, on the sheet that travels with them (M51). The
    // customer's own copy does not need their own address, and the till
    // roll stays the length it was.
    if (!money && _has(d.customerAddress)) {
      labelled('Address', d.customerAddress!);
    }

    // How the goods travel, whenever any of it is known (M51). A bilty
    // number on the buyer's own bill is how they collect at the other end.
    final t = d.transport;
    if (!t.isEmpty) {
      rule('-');
      if (_has(t.transporter)) labelled('Transporter', t.transporter!);
      if (_has(t.vehicleNo)) labelled('Gaari no', t.vehicleNo!);
      if (_has(t.biltyNo)) labelled('Bilty no', t.biltyNo!);
      if (_has(t.shipTo)) labelled('Ship to', t.shipTo!);
    }

    rule('-');
    out.add(_row('Item', money ? 'Amount' : 'Qty'));
    rule('-');

    if (!money) {
      // --- The transporter's copy -----------------------------------------
      //
      // What is in the sacks and how much of it, and nothing that is money:
      // no rate, no amount, no total, no tender, no khata, no payment
      // details, no FBR number. A sheet with a price on it is a sheet
      // photographed at the adda and passed to the shop next door.
      for (final line in d.lines) {
        for (final part in _wrap(line.name, width)) {
          out.add(part);
        }
        final figure = '${line.qtyDisplay} ${line.unitCode}'.trim();
        // In packs as well (M45): "53 pcs (2 ctn 5 pc)" is what a driver
        // counts off the lorry, carton by carton.
        final words = line.qtyWords;
        final qty = words == null ? figure : '$figure ($words)';
        if (qty.length + 2 <= width) {
          out.add(_row('', qty));
        } else {
          for (final part in _wrap(figure, width - 2)) {
            out.add('  $part');
          }
          if (words != null) _wordsLine(out, line);
        }
        if (line.isFreeItem) out.add('    (Bonus / muft)'); // M43
        _detailLines(out, line); // M50
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
      final amount = line.amount.amountOnly;
      final room = width - amount.length - 1;
      final short = '  ${line.qtyDisplay} ${line.unitCode}';
      final full = '$short x ${line.rate.amountOnly}';
      // M45: the count in packs beside the figure, "53 pcs (2 ctn 5 pc) x
      // 40.00", where the row has room for it. The figure stays first and
      // the rate stays per its unit, so the line still multiplies out.
      final words = line.qtyWords;
      final counted = words == null
          ? null
          : '$short ($words) x ${line.rate.amountOnly}';
      if (counted != null && counted.length <= room) {
        out.add(_row(counted, amount));
      } else if (full.length <= room) {
        out.add(_row(full, amount));
      } else if (short.length <= room) {
        out.add(_row(short, amount));
      } else {
        // Neither will the quantity and unit alone sit beside the amount.
        // `_row` clips the left, and a clipped unit code is not a shorter unit
        // code: `bori-50kg-special` cut to `bori-50kg` names a different pack
        // at a different price, and it reads as though it were the real unit.
        // `code` has no length cap in the schema because the shop invents its
        // own, so the only safe move is to give the detail its own line and
        // let the amount keep the row to itself.
        for (final part in _wrap(
          '${line.qtyDisplay} ${line.unitCode}',
          width - 2,
        )) {
          out.add('  $part');
        }
        out.add(_row('', amount));
      }
      if (counted != null && counted.length > room) _wordsLine(out, line);
      if (line.discount.isPositive) {
        out.add(_row('    less discount', '-${line.discount.amountOnly}'));
      }
      if (line.isFreeItem) {
        out.add('    (Bonus / muft)'); // M43
      }
      _detailLines(out, line); // M50
    }

    rule('-');

    // --- Totals ----------------------------------------------------------
    out.add(_row('Subtotal', d.subtotal.amountOnly));
    if (d.discount.isPositive) {
      out.add(_row('Discount', '-${d.discount.amountOnly}'));
    }
    // M59: the province's tax on services on lines of its own — "PRA 8%
    // (card)" — and sales tax as what is left, so the parts still add up.
    if (d.federalTax.isPositive) {
      out.add(_row('Sales Tax', d.federalTax.amountOnly));
    }
    for (final t in d.serviceTaxes) {
      out.add(_row(t.label, t.amount.amountOnly));
    }
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
      out.add(_row(d.extraChargesLabel, d.extraCharges.amountOnly)); // M50
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
    // The khata block (M51), in place of the bill's own udhaar line: "is
    // bill" IS that line, and printing both says the same thing twice. Not
    // on a cancelled bill, which asks for nothing.
    final khata = d.khata;
    if (khata != null && !d.isCancelled) {
      rule('-');
      out.add(_row('Pichhla baqaya', khata.before.amountOnly));
      out.add(_row('Is bill', khata.thisBill.amountOnly));
      out.add(_row('KUL BAQAYA', khata.after.amountOnly));
      // A second sheet, printed later, carries the figures of the day the
      // bill was made — said, so nobody reads them as today's khata.
      if (copy != null && copy != ReceiptCopy.original) {
        centred('(bill ke din ka hisaab)');
      }
    } else if (d.balance.isPositive) {
      rule('-');
      out.add(_row('BAQAYA (udhaar)', d.balance.amountOnly));
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

    // --- FBR (M19) --------------------------------------------------------
    // FBR's own number for the bill, once it has answered; the QR of it is
    // drawn under the text by the thermal renderer.
    if (d.fbrInvoiceNo != null) {
      rule('-');
      centred('FBR Invoice No');
      for (final part in _wrap(d.fbrInvoiceNo!, width)) {
        out.add(_centre(part));
      }
    } else if (d.fbrPending) {
      // Rule 150XC (M59): a bill FBR has not answered for was issued in
      // offline mode, and the paper says so until FBR has numbered it.
      rule('-');
      for (final mark in offlineInvoiceMark) {
        centred(mark);
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

  /// What the paper says under a line besides its money (M50): a phone's
  /// IMEIs, the day its warranty ends and its PTA standing, one to a row,
  /// wrapped and never clipped — a cut IMEI is a different phone.
  void _detailLines(List<String> out, ReceiptLine line) {
    for (final detail in line.details) {
      for (final part in _wrap(detail, width - 4)) {
        out.add('    $part');
      }
    }
  }

  /// A line's count in packs on a line of its own, under the figure, where
  /// it would not sit beside it (M45): "(2 ctn 5 pc)" is what a customer
  /// counts the cartons against, so it earns its line on a 58 mm roll.
  /// Wrapped, never clipped, like every other word on the paper.
  void _wordsLine(List<String> out, ReceiptLine line) {
    final words = line.qtyWords;
    if (words == null) return;
    for (final part in _wrap('($words)', width - 4)) {
      out.add('    $part');
    }
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
