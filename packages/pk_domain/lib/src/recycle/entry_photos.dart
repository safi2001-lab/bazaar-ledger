/// A photograph of the paper that went with an entry (M60).
///
/// Every shop this is built for runs on paper as well as on the phone. The
/// supplier's carbon-copy bill, the bijli bill, the bank's deposit slip, a
/// cheque, a challan the customer signed, a customer's CNIC copy: each is the
/// evidence for an entry, and each lives today in a drawer, a shoebox or the
/// owner's WhatsApp gallery, which is exactly where it is not when the
/// supplier says "I sent forty bags, not thirty". Khatabook puts attachments
/// on entries; Business Khata puts photo notes on them; shopkeepers on the
/// research's forums ask to "photograph the parchi onto the entry". Here it
/// goes onto the entry itself, and stays there.
///
/// Kept inline in the books, like an item's photograph, so a backup is one
/// file and a restore never comes back without them. That only holds while
/// each picture stays small, which is what [EntryPhoto.maxBytes] is for.
library;

import 'dart:typed_data';

/// What an entry photograph is of, as the schema's closed set of kinds
/// names it.
///
/// No new kind was needed, and none could be added without a schema change:
/// the paper behind a bill, an expense or a payment is a `receipt_photo`, a
/// cheque is a `cheque_image`, and the papers on a customer or supplier —
/// usually a CNIC copy — are `other`. Where a photograph hangs (the entry's
/// table and id) says the rest.
enum EntryPhotoKind {
  /// A supplier's bill, a bijli bill, a deposit slip, a signed challan.
  receipt('receipt_photo'),

  /// A cheque, front or back.
  cheque('cheque_image'),

  /// A party's papers: a CNIC copy, a shop's card.
  papers('other');

  const EntryPhotoKind(this.code);

  /// As the `attachments.kind` column holds it.
  final String code;
}

/// The rows a photograph can hang off, as `attachments.owner_table` holds
/// them. Anything else is refused: a photograph pointing at a table nothing
/// reads would be one nobody ever sees again.
const entryPhotoOwners = {'documents', 'payments', 'parties'};

/// One photograph on an entry, as the entry's page shows it.
final class EntryPhoto {
  const EntryPhoto({
    required this.id,
    required this.ownerTable,
    required this.ownerId,
    required this.kind,
    required this.bytes,
    required this.width,
    required this.height,
    required this.addedAtUtc,
    required this.addedBy,
    this.fromEarlierEntry = false,
  });

  final String id;
  final String ownerTable;
  final String ownerId;

  /// The schema's kind code: `receipt_photo`, `cheque_image` or `other`.
  final String kind;

  /// The JPEG itself, already reduced to fit [maxBytes].
  final Uint8List bytes;
  final int width;
  final int height;
  final DateTime addedAtUtc;

  /// The name of whoever added it.
  final String addedBy;

  /// True when the photograph hangs off the entry this one corrected (M31,
  /// M36). A receipt keyed in as Rs 5,000 for Rs 500 and put right is a new
  /// entry with a new number; the deposit slip photographed onto the first
  /// is still the slip for the second, and a page that lost it on the
  /// correction would read as the photograph having been deleted.
  final bool fromEarlierEntry;

  /// The longest edge a paper's photograph is kept at.
  ///
  /// Larger than an item's 512 on purpose. An item's photograph is for
  /// recognising a packet; this one is for reading a handwritten line on a
  /// carbon copy when the supplier disputes it. At 1280 pixels an A5 parchi
  /// keeps about six pixels to the millimetre, which is a 4 mm handwritten
  /// figure two dozen pixels tall — readable, zoomed, on the phone it was
  /// taken on.
  static const maxEdge = 1280;

  /// And the ceiling on each one, encoded.
  ///
  /// About two hundred kilobytes: a thousand parchis — three a working day
  /// for a year — come to under two hundred megabytes of a backup, which is
  /// still a file a shop can keep on Drive or send over WhatsApp. A picture
  /// over it is refused rather than stored, as an item's is.
  static const maxBytes = 192 * 1024;

  /// How many photographs one entry keeps.
  ///
  /// Eight is a supplier's bill of several pages, both sides of a cheque and
  /// the slip. More than that is a file, not a parchi, and a ceiling keeps a
  /// stuck button or a gallery picked whole from turning one entry into a
  /// hundred megabytes of the shop's only backup.
  static const maxPerEntry = 8;
}

/// A photograph somebody took off an entry, waiting in the recycle bin.
final class RemovedPhoto {
  const RemovedPhoto({
    required this.id,
    required this.ownerTable,
    required this.ownerId,
    required this.ownerLabel,
    required this.kind,
    required this.bytes,
    required this.removedAtUtc,
    required this.removedBy,
  });

  final String id;
  final String ownerTable;
  final String ownerId;

  /// What it was on, as the shop knows it: a bill's or a payment's number,
  /// a customer's name, an item's. Empty when the row it hung off is gone.
  final String ownerLabel;

  final String kind;
  final Uint8List bytes;
  final DateTime removedAtUtc;
  final String removedBy;
}

/// A photograph refused, in words a shopkeeper can act on.
final class PhotoRefused implements Exception {
  const PhotoRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
