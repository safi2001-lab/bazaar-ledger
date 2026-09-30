/// A sale as FBR's Digital Invoicing gateway wants it (M19).
///
/// A registered shop reports each sale to FBR through PRAL, and FBR answers
/// with its own invoice number, which goes on the bill with a QR code. This
/// is the shape the gateway reads (DI API v1.12, as the plan document sets
/// it out) and the rules it refuses on, checked here before anything is
/// sent. Amounts are written as decimals straight from paisa — never through
/// a floating-point number — so what FBR receives is exactly the bill.
library;

import 'package:pk_money/pk_money.dart';

/// One line of a sale, for FBR.
final class FbrLine {
  const FbrLine({
    required this.description,
    required this.hsCode,
    required this.qty,
    required this.unit,
    required this.unitPrice,
    required this.value,
    required this.salesTaxBp,
    required this.salesTax,
    required this.furtherTax,
    required this.discount,
    required this.total,
    this.itemCode,
    this.furtherTaxBp = 0,
  });

  final String? itemCode;
  final String description;
  final String? hsCode;
  final Qty qty;
  final String unit;

  /// Per unit, before tax.
  final Money unitPrice;

  /// The taxable value of the line.
  final Money value;
  final int salesTaxBp;
  final Money salesTax;
  final int furtherTaxBp;
  final Money furtherTax;
  final Money discount;

  /// Value plus taxes: what the line adds to the bill.
  final Money total;
}

/// A whole sale, for FBR.
final class FbrSale {
  const FbrSale({
    required this.invoiceRef,
    required this.dateUtc,
    required this.sellerNtn,
    required this.sellerStrn,
    required this.lines,
    this.buyerNtn,
    this.buyerName,
    this.buyerRegistered = false,
  });

  /// The shop's own bill number.
  final String invoiceRef;
  final DateTime dateUtc;
  final String? sellerNtn;
  final String? sellerStrn;
  final String? buyerNtn;
  final String? buyerName;
  final bool buyerRegistered;
  final List<FbrLine> lines;

  Qty get totalQty => lines.fold(
    Qty.zero,
    (sum, l) => Qty.raw(sum.inThousandths + l.qty.inThousandths),
  );
  Money get totalValue => Money.sum([for (final l in lines) l.value]);
  Money get totalSalesTax => Money.sum([for (final l in lines) l.salesTax]);
  Money get totalFurtherTax => Money.sum([for (final l in lines) l.furtherTax]);
  Money get total => Money.sum([for (final l in lines) l.total]);
}

final _ntn = RegExp(r'^\d{7}-?\d$');
final _hs = RegExp(r'^\d{4}\.\d{4}$');

const _sellerNtnProblem =
    "1001: the shop's NTN is missing or not 7 digits and a check digit "
    '(Settings, Shop details)';

/// What FBR would refuse this sale for, in words, before it is sent. Empty
/// when it can go. The codes are the gateway's own, so a shopkeeper who
/// rings their accountant can quote them.
List<String> fbrProblems(FbrSale sale) => [
  if (sale.sellerNtn == null || !_ntn.hasMatch(sale.sellerNtn!.trim()))
    _sellerNtnProblem,
  if (sale.buyerRegistered &&
      (sale.buyerNtn == null || !_ntn.hasMatch(sale.buyerNtn!.trim())))
    '1001: the buyer is registered but their NTN is missing or wrong',
  for (final l in sale.lines)
    if (l.hsCode == null || !_hs.hasMatch(l.hsCode!.trim()))
      '1002: ${l.description} has no 8-digit HS code (like 1512.1900)',
  if (sale.lines.isEmpty) 'The bill has no lines.',
];

/// The JSON body the gateway reads, written by hand so every amount is the
/// exact decimal of its paisa.
String fbrPayload(FbrSale sale) {
  final b = StringBuffer('{');
  var first = true;
  void field(String key, String rawJson) {
    if (!first) b.write(',');
    first = false;
    b
      ..write(_str(key))
      ..write(':')
      ..write(rawJson);
  }

  field('InvoiceType', _str('Sale Invoice'));
  field('InvoiceDate', _str(_isoSeconds(sale.dateUtc)));
  field('InvoiceRefNo', _str(sale.invoiceRef));
  field('SellerNTN', _str(sale.sellerNtn?.trim() ?? ''));
  field('SellerSTRN', _str(sale.sellerStrn?.trim() ?? ''));
  field('BuyerNTN', _str(sale.buyerNtn?.trim() ?? ''));
  field('BuyerName', _str(sale.buyerName ?? ''));
  field(
    'BuyerType',
    _str(sale.buyerRegistered ? 'Registered' : 'Unregistered'),
  );
  final items = [
    for (final l in sale.lines)
      '{${['${_str('ItemCode')}:${_str(l.itemCode ?? '')}', '${_str('ItemDescription')}:${_str(l.description)}', '${_str('HSCode')}:${_str(l.hsCode?.trim() ?? '')}', '${_str('Quantity')}:${_qty(l.qty)}', '${_str('UnitOfMeasurement')}:${_str(l.unit)}', '${_str('UnitPrice')}:${_money(l.unitPrice)}', '${_str('SalesTaxRate')}:${_bp(l.salesTaxBp)}', '${_str('SalesTaxAmount')}:${_money(l.salesTax)}', '${_str('FurtherTaxRate')}:${_bp(l.furtherTaxBp)}', '${_str('FurtherTaxAmount')}:${_money(l.furtherTax)}', '${_str('Discount')}:${_money(l.discount)}', '${_str('TotalAmount')}:${_money(l.total)}'].join(',')}}',
  ];
  field('InvoiceItems', '[${items.join(',')}]');
  field('TotalQuantity', _qty(sale.totalQty));
  field('TotalTaxableAmount', _money(sale.totalValue));
  field('TotalSalesTax', _money(sale.totalSalesTax));
  field('TotalFurtherTax', _money(sale.totalFurtherTax));
  field('TotalInvoiceAmount', _money(sale.total));
  b.write('}');
  return b.toString();
}

String _isoSeconds(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}T'
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// `12345` paisa is `123.45`.
String _money(Money m) {
  final p = m.inPaisa.abs();
  final sign = m.inPaisa < 0 ? '-' : '';
  return '$sign${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
}

/// `1500` thousandths is `1.500`.
String _qty(Qty q) {
  final t = q.inThousandths.abs();
  final sign = q.inThousandths < 0 ? '-' : '';
  return '$sign${t ~/ 1000}.${(t % 1000).toString().padLeft(3, '0')}';
}

/// `1800` basis points is `18.00`.
String _bp(int bp) => '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}';

String _str(String s) {
  final b = StringBuffer('"');
  for (final c in s.runes) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        if (c < 0x20) {
          b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
  return b.toString();
}

/// What the gateway said about one sale.
sealed class FbrOutcome {
  const FbrOutcome();
}

/// FBR accepted it and gave it this number.
final class FbrPosted extends FbrOutcome {
  const FbrPosted(this.fbrInvoiceNo);

  final String fbrInvoiceNo;
}

/// FBR refused it; sending it again unchanged will not help.
final class FbrRejected extends FbrOutcome {
  const FbrRejected(this.code, this.message);

  final String code;
  final String message;
}

/// FBR could not be reached or was down; try again later.
final class FbrTryLater extends FbrOutcome {
  const FbrTryLater(this.reason);

  final String reason;
}

/// Reads the gateway's answer. Accepts the plan document's shape and PRAL's
/// own (`validationResponse.statusCode`, "00" meaning valid).
FbrOutcome readFbrResponse(int httpStatus, Object? body) {
  if (httpStatus >= 500 || httpStatus == 408 || httpStatus == 429) {
    return FbrTryLater('FBR answered $httpStatus.');
  }
  final json = body is Map<String, Object?> ? body : const <String, Object?>{};
  final validation = json['validationResponse'];
  final v = validation is Map<String, Object?> ? validation : json;
  final code =
      '${v['statusCode'] ?? v['errorCode'] ?? v['ErrorCode'] ?? json['Code'] ?? ''}'
          .trim();
  final message =
      '${v['error'] ?? v['Error'] ?? v['message'] ?? v['Message'] ?? ''}'
          .trim();
  final number = '${json['invoiceNumber'] ?? json['InvoiceNumber'] ?? ''}'
      .trim();

  if (code == '5003') {
    return FbrTryLater(message.isEmpty ? 'FBR is down.' : message);
  }
  if (httpStatus == 401 || httpStatus == 403) {
    return FbrRejected(
      '$httpStatus',
      'FBR refused the token. Check it in Settings, Tax, FBR.',
    );
  }
  final ok = (code.isEmpty || code == '00' || code == '0') && httpStatus < 300;
  if (ok && number.isNotEmpty) return FbrPosted(number);
  if (ok) {
    return const FbrRejected('', 'FBR accepted the bill but gave no number.');
  }
  return FbrRejected(code, message.isEmpty ? 'FBR refused the bill.' : message);
}

/// What a code FBR refused with means for the shopkeeper.
String fbrAdvice(String code) => switch (code) {
  '1001' => "Check the NTN on the shop's details, or the buyer's.",
  '1002' => 'Give the item its 8-digit HS code.',
  '1005' => 'FBR already has this bill number.',
  '1010' => "The tax on a line does not match its rate; check the item's tax.",
  '1015' => 'Past the 72-hour window: issue a credit note instead.',
  _ => '',
};

/// Where a sale is sent: FBR's gateway, or a stand-in for it.
abstract interface class FbrGateway {
  Future<FbrOutcome> post(String payloadJson);
}
