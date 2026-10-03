/// The buyer's name on a big bill (M59).
///
/// FBR requires a retailer's invoice to carry the buyer's name when one
/// invoice is over Rs 100,000 (reported by ProPakistani, 9 August 2021, from
/// FBR's own instructions to integrated retailers). A named customer already
/// has a name on the bill; the rule bites on the walk-in, who has none. So a
/// walk-in bill over the line asks for the name — and, if the customer will
/// give it, the CNIC — before the money is taken, and both go on the bill's
/// own party snapshot, where an invoice keeps who it was to.
///
/// For a shop registered for sales tax it is a requirement, and the sale
/// path refuses the bill without it, beneath every screen. For any other
/// shop it is a warning only: the rule is FBR's, about registered persons'
/// invoices, and an unregistered kiryana is not asked by anyone.
///
/// Kept apart from s.21(s)'s Rs 200,000 cash flag, which is about how a big
/// bill is paid, not who it is to; both can apply to one bill.
///
/// The CNIC goes into `party_ntn_snapshot`: for an individual FBR has used
/// the CNIC as the tax number since 2019, and Digital Invoicing's buyer
/// field takes either (`buyerNTNCNIC`). There is no other place on a bill
/// for it, and the schema is not changed for one field.
library;

import 'package:pk_money/pk_money.dart';

/// Over this, one invoice has to name its buyer.
const buyerNameThreshold = Money.rupees(100000);

/// Whether a bill for [total] has to ask for the buyer's name: over the
/// line, to nobody in the khata ([partyId] null), and no name given yet.
bool buyerNameNeeded({
  required Money total,
  required String? partyId,
  required String? buyerName,
}) =>
    total > buyerNameThreshold &&
    partyId == null &&
    (buyerName ?? '').trim().isEmpty;

/// A CNIC as it is written, `35202-1234567-1`, from thirteen digits typed
/// with or without the dashes; null for anything else.
String? tidyCnic(String? typed) {
  final digits = (typed ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^\d{13}$').hasMatch(digits)) return null;
  return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-'
      '${digits.substring(12)}';
}

/// A bill the sale path will not write without its buyer's name.
final class BuyerNameRequired implements Exception {
  const BuyerNameRequired(this.total);

  final Money total;

  @override
  String toString() =>
      'This bill is Rs ${total.amountOnly}. FBR wants the buyer\'s name on '
      'a single bill over Rs ${buyerNameThreshold.amountOnly}: write their '
      'name on the bill, or pick them from the khata.';
}
