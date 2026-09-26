/// The notice a shop sends after a customer's cheque bounces.
///
/// A case under s.489-F of the Pakistan Penal Code, and a summary suit under
/// Order XXXVII of the Civil Procedure Code, both start from the same paper:
/// a written demand to the drawer naming the cheque, the bank, the amount
/// and the day it came back, and giving them a period to pay. Shops in the
/// wholesale markets have it typed up by a munshi outside the courts, from
/// the details on the cheque and the bank's return memo. Every one of those
/// details is already in the books, so the draft comes from there.
///
/// It is a draft. The wording is the ordinary form of such a notice and the
/// screen that shares it says to have an advocate look at it before it is
/// served; nothing here is legal advice, and nothing here is sent anywhere
/// by the app.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';
import 'cheque_dates.dart';
import 'cheque_lifecycle.dart';

/// How many days the drawer is given to pay once the notice reaches them.
const demandNoticePayWithinDays = 15;

/// Everything a demand notice for one bounced cheque says.
final class DemandNotice {
  const DemandNotice({
    required this.shopName,
    required this.partyName,
    required this.chequeNo,
    required this.amount,
    required this.bouncedOn,
    required this.issuedOn,
    this.shopAddress,
    this.shopCity,
    this.shopPhone,
    this.partyAddress,
    this.partyCity,
    this.partyPhone,
    this.partyCnic,
    this.bank,
    this.chequeDate,
    this.returnReason,
  });

  final String shopName;
  final String? shopAddress;
  final String? shopCity;
  final String? shopPhone;

  final String partyName;
  final String? partyAddress;
  final String? partyCity;
  final String? partyPhone;
  final String? partyCnic;

  final String chequeNo;
  final String? bank;

  /// The date written on the cheque. Null only for a cheque taken before M6,
  /// which asked for none.
  final BusinessDate? chequeDate;

  final Money amount;
  final BusinessDate bouncedOn;

  /// What the bank's return memo said, as the shop wrote it down.
  final String? returnReason;

  /// The day the notice is drawn up.
  final BusinessDate issuedOn;

  /// The last day to serve it.
  BusinessDate get serveBy => bouncedOn.addDays(noticeDaysAfterBounce);

  /// Whether the day to serve it has already gone.
  bool get isLate => daysUntil(issuedOn, serveBy) < 0;

  String get title => 'Demand notice, cheque $chequeNo';

  String get subject =>
      'LEGAL NOTICE FOR PAYMENT OF A DISHONOURED CHEQUE '
      '(SECTION 489-F PPC)';

  /// The addressee block, one line each, blanks left out.
  List<String> get to => [
    partyName,
    ?_blankToNull(partyAddress),
    ?_blankToNull(partyCity),
    if (_blankToNull(partyPhone) case final phone?) 'Phone: $phone',
    if (_blankToNull(partyCnic) case final cnic?) 'CNIC: $cnic',
  ];

  /// The sender block.
  List<String> get from => [
    shopName,
    ?_blankToNull(shopAddress),
    ?_blankToNull(shopCity),
    if (_blankToNull(shopPhone) case final phone?) 'Phone: $phone',
  ];

  /// The body, paragraph by paragraph.
  List<String> get paragraphs {
    final rupees = 'Rs. ${amount.amountOnly}/- (${rupeesInWords(amount)})';
    final dated = chequeDate == null
        ? ''
        : ' dated ${formatNoticeDate(chequeDate!)}';
    final drawnOn = _blankToNull(bank) == null
        ? ''
        : ' drawn on ${bank!.trim()}';
    final remarks = _blankToNull(returnReason) == null
        ? ''
        : ' with the remarks "${returnReason!.trim()}"';

    final issued =
        'That you issued cheque No. $chequeNo$dated$drawnOn for $rupees in '
        'favour of $shopName towards the discharge of your liability.';
    final returned =
        'That the said cheque was presented for payment and was returned '
        'unpaid by the bank on ${formatNoticeDate(bouncedOn)}$remarks.';
    const offence =
        'That dishonestly issuing a cheque which is dishonoured on '
        'presentation is an offence under Section 489-F of the Pakistan '
        'Penal Code.';
    final demand =
        'You are therefore called upon to pay the said amount of '
        'Rs. ${amount.amountOnly}/- within $demandNoticePayWithinDays days '
        'of receiving this notice, failing which proceedings will be '
        'initiated against you under Section 489-F PPC and Order XXXVII of '
        'the Code of Civil Procedure, at your risk as to costs and '
        'consequences.';
    return [issued, returned, offence, demand];
  }

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A date as a notice writes it: 11 October 2026.
String formatNoticeDate(BusinessDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

const _ones = [
  '',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];

const _tens = [
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];

String _belowHundred(int n) {
  if (n < 20) return _ones[n];
  final ten = _tens[n ~/ 10];
  final one = _ones[n % 10];
  return one.isEmpty ? ten : '$ten-$one';
}

String _belowThousand(int n) {
  final hundreds = n ~/ 100;
  final rest = n % 100;
  return [
    if (hundreds > 0) '${_ones[hundreds]} Hundred',
    if (rest > 0) _belowHundred(rest),
  ].join(' ');
}

/// A whole number of rupees in words, counted the way Pakistan counts:
/// thousand, lakh, crore — 45,00,000 is Forty-Five Lakh, not four and a half
/// million.
String _wholeInWords(int n) {
  if (n == 0) return 'Zero';
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final rest = n % 1000;
  return [
    // Above a hundred crore the crores are counted in the same words again:
    // 1,25,00,00,000 is One Hundred Twenty-Five Crore.
    if (crore > 0) '${_wholeInWords(crore)} Crore',
    if (lakh > 0) '${_belowHundred(lakh)} Lakh',
    if (thousand > 0) '${_belowHundred(thousand)} Thousand',
    if (rest > 0) _belowThousand(rest),
  ].join(' ');
}

/// An amount as a cheque or a notice writes it in words:
/// "Rupees Forty-Five Thousand only".
String rupeesInWords(Money amount) {
  final paisa = amount.abs.inPaisa;
  final rupees = paisa ~/ 100;
  final cents = paisa % 100;
  final words = StringBuffer('Rupees ${_wholeInWords(rupees)}');
  if (cents > 0) words.write(' and ${_belowHundred(cents)} Paisa');
  words.write(' only');
  return words.toString();
}
