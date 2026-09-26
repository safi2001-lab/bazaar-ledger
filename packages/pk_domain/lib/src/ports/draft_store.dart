/// Somewhere to leave a half-finished bill.
///
/// Deliberately the narrowest possible port: a slot name and a string. It
/// knows nothing about carts, money or items, so nothing about the counter's
/// state can leak into a platform adapter, and the adapter can be swapped for
/// an in-memory one in a test without pretending to be a database.
///
/// This is NOT the ledger. A draft is not a document, has no invoice number,
/// no journal entry, no audit row and no place in the sync outbox — it is a
/// scrap of paper under the till. It must never be written through
/// `TxRunner`, and keeping it behind its own port is what makes that
/// structural rather than a rule someone has to remember.
///
/// Why it exists at all: Transsion ROMs — Infinix, Tecno, itel, about 44% of
/// the Pakistani market at the bottom end — ship "Phone Master" with a Boost
/// button that force-stops backgrounded apps. A cashier who builds a fifteen
/// line bill, switches to WhatsApp to check a price, and comes back to an
/// empty cart has to re-scan the lot with the customer standing there.
///
/// Flutter's own state restoration cannot cover this. It rides on Android's
/// `savedInstanceState`, which is tied to the task record, and a force-stop —
/// or swiping the app off Recents, or a reboot — takes the task record with
/// it. Restoration survives a low-memory reclaim and nothing else, which is
/// the one case a shopkeeper is least likely to notice.
abstract interface class DraftStore {
  /// What is in [slot], or null if nothing is.
  ///
  /// Never throws for a missing, empty or unreadable slot. A draft that
  /// cannot be read is a draft that is not there; refusing to start the app
  /// over a scrap of paper would be a worse failure than losing it.
  Future<String?> read(String slot);

  /// Replaces [slot] atomically.
  ///
  /// Atomically because the alternative is a half-written draft, and a cart
  /// restored with half its lines is worse than one restored with none: the
  /// cashier cannot tell by looking, and the missing stock walks out of the
  /// shop.
  Future<void> write(String slot, String contents);

  /// Empties [slot]. A slot that was already empty is not an error.
  Future<void> clear(String slot);
}

/// The slot the counter's live bill lives in.
///
/// A named constant rather than a literal at each call site, because the
/// counter writes it and the bootstrap reads it and a typo between the two is
/// a cart that is saved perfectly and never restored.
const String cartDraftSlot = 'cart';

/// The slot that remembers which firm this phone last had open, when it
/// keeps the books of more than one.
const activeFirmSlot = 'active_firm';
