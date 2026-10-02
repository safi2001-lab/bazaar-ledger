/// The document series a shop numbers its paperwork with.
///
/// One place, because a prefix that is invented at each call site is a prefix
/// that disagrees with itself: two code paths minting `PUR` and `PU` for the
/// same thing produce two series in one shop's books and no way to tell an
/// auditor which is which.
///
/// Pad width is per series rather than global. An invoice series runs to four
/// digits because a counter shop writes a few thousand a year; a journal
/// series runs to five because corrections, opening balances and year-end
/// entries pile up faster than anybody expects.
library;

/// A series definition: what its numbers look like before the counter.
final class DocumentSeries {
  const DocumentSeries({
    required this.docType,
    required this.prefix,
    required this.padWidth,
  });

  final String docType;

  /// `INV`, `RCV`, `JV`. Appears in the formatted number and is stored on the
  /// document separately so a report can group on it.
  final String prefix;

  final int padWidth;

  /// Every series this product knows how to number.
  ///
  /// A document type absent from here cannot be numbered, and that is
  /// deliberate: it is the difference between "the new financial year has not
  /// been opened yet", which the allocator now handles by itself, and "some
  /// code asked for a kind of document nobody has decided the numbering for",
  /// which is a programming error and has to surface as one.
  static const all = <DocumentSeries>[
    DocumentSeries(docType: 'sale_invoice', prefix: 'INV', padWidth: 4),
    DocumentSeries(docType: 'payment_in', prefix: 'RCV', padWidth: 4),
    DocumentSeries(docType: 'payment_out', prefix: 'PAY', padWidth: 4),
    DocumentSeries(docType: 'journal_entry', prefix: 'JV', padWidth: 5),
    DocumentSeries(docType: 'purchase_bill', prefix: 'PUR', padWidth: 4),
    DocumentSeries(docType: 'sale_return', prefix: 'SRN', padWidth: 4),
    DocumentSeries(docType: 'purchase_return', prefix: 'PRN', padWidth: 4),
    DocumentSeries(docType: 'expense', prefix: 'EXP', padWidth: 4),
    DocumentSeries(docType: 'other_income', prefix: 'INC', padWidth: 4),
    DocumentSeries(docType: 'quotation', prefix: 'QUO', padWidth: 4),
    DocumentSeries(docType: 'proforma', prefix: 'PRO', padWidth: 4),
    DocumentSeries(docType: 'delivery_challan', prefix: 'CHL', padWidth: 4),
    DocumentSeries(docType: 'sale_order', prefix: 'SO', padWidth: 4),
    DocumentSeries(docType: 'purchase_order', prefix: 'PO', padWidth: 4),
    DocumentSeries(docType: 'assembly', prefix: 'ASM', padWidth: 4),
    // Udhaar let go (M44): forgiven to settle, and written off. Numbered
    // apart from receipts so the khata, a reprinted bill and the activity
    // log say which it was.
    DocumentSeries(docType: 'settlement_discount', prefix: 'SD', padWidth: 4),
    DocumentSeries(docType: 'write_off', prefix: 'WO', padWidth: 4),
  ];

  static DocumentSeries? forType(String docType) {
    for (final series in all) {
      if (series.docType == docType) return series;
    }
    return null;
  }
}
