/// Everything a shopkeeper can hide, and the one place it all comes back
/// from (M60, completing M5's "nothing hidden is lost").
///
/// M5 gave hidden items and customers a way back. Since then the shop has
/// learned to hide a good deal more — an expense head it stopped using
/// (M47), a head of other income, a member of staff who left (M9) — and
/// none of those had a way back from anywhere a shopkeeper would look. Nor
/// could a van that was sold, or a recipe the shop stopped making, be put
/// away at all: they could only sit in the list for ever. Each is now hidden
/// with one act and brought back with one tap, from one screen, which says
/// when it was hidden and by whom.
///
/// ## Kept for ever, not thirty days
///
/// Business Khata empties its trash after thirty days, and Vyapar sells its
/// Recycle Bin on the premium plan. Neither suits books that must be kept
/// six years (s.24 STA, s.174(3) ITO): a hidden customer still has every
/// bill they were ever sold pointing at them, a hidden item every line it
/// was sold on, a removed photograph was the evidence for an entry. Nothing
/// here is ever destroyed, so there is nothing to empty, and no clock that
/// would one day take back something a shopkeeper meant only to tidy away.
library;

/// When something was hidden, and by whom, read from the activity log that
/// the act itself wrote.
final class HiddenMark {
  const HiddenMark({required this.atUtc, required this.by});

  final DateTime atUtc;

  /// The name of whoever hid it.
  final String by;
}

/// A van the shop has put away.
final class HiddenVan {
  const HiddenVan({
    required this.id,
    required this.name,
    required this.locationCode,
  });

  final String id;
  final String name;
  final String locationCode;
}

/// A recipe the shop has stopped making, for now.
final class HiddenRecipe {
  const HiddenRecipe({
    required this.id,
    required this.name,
    required this.outputName,
  });

  final String id;
  final String name;

  /// What one batch of it makes.
  final String outputName;
}

/// The audit codes for putting a van away and bringing it back.
const vanHiddenAction = 'VAN_HIDDEN';
const vanRestoredAction = 'VAN_RESTORED';

/// The audit codes for putting a recipe away and bringing it back.
const recipeHiddenAction = 'RECIPE_HIDDEN';
const recipeRestoredAction = 'RECIPE_RESTORED';

/// The audit codes for a photograph put on an entry, taken off it, and
/// brought back from the bin. `ATTACHMENT_ADDED` and `ATTACHMENT_REMOVED`
/// are the codes an item's picture has always left (M2), kept so one search
/// of the activity log finds every picture.
const photoAddedAction = 'ATTACHMENT_ADDED';
const photoRemovedAction = 'ATTACHMENT_REMOVED';
const photoRestoredAction = 'ATTACHMENT_RESTORED';

/// Every audit code that puts something in the recycle bin, each beside the
/// table its row names. The bin reads who and when from the latest of them.
///
/// Every one of these is also in `undoingActions`, so with Data Lock on each
/// asks for a PIN first: the bin is where things go that somebody might
/// want to make disappear, which is the whole of what Data Lock is for.
const hidingActions = <String, String>{
  'ITEM_ARCHIVED': 'items',
  'PARTY_ARCHIVED': 'parties',
  'EXPENSE_HEAD_HIDDEN': 'accounts',
  'INCOME_HEAD_HIDDEN': 'settings',
  'USER_DEACTIVATED': 'users',
  vanHiddenAction: 'vans',
  recipeHiddenAction: 'boms',
  photoRemovedAction: 'attachments',
};

/// The settings key a recipe's being put away is kept under.
///
/// A setting rather than a column, as M47 keeps an expense head's: `boms`
/// has no column for it, and the schema is not changed for a milestone that
/// needs none (M49 holds the next version). The value is JSON,
/// `{"hidden": true}`, and is flipped in place rather than struck out,
/// because the key is unique among struck-out rows too.
String recipeSettingKey(String bomId) => 'recipe.$bomId';
