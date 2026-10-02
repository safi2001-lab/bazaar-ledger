/// Putting right the opening balance a party was entered with (M31).
///
/// The opening balance is what a customer already owed on the day their
/// khata moved into this app, typed once from the old register. Until M31 it
/// could not be changed afterwards at all — the editor dropped the field the
/// moment a party was saved, on the grounds that changing it silently
/// restates the whole khata. That was right about "silently" and wrong about
/// "never": a Rs 45,000 typed as Rs 4,500 was then wrong for ever, and the
/// only way out was to add the customer again under a second name.
///
/// So it is corrected the way everything else in the books is. The opening
/// entry that put the old figure on the books is mirrored, dated today; a new
/// opening entry puts the right figure on; the party's own column follows,
/// because the khata reads its opening line from there. Nothing written is
/// rewritten, and the pair of entries says exactly when the figure changed
/// and from what.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'reversal.dart';

/// An opening entry that is still standing in the books.
final class OpeningEntrySnapshot {
  const OpeningEntrySnapshot({required this.entryId, required this.entry});

  final String entryId;
  final JournalEntryPosting entry;
}

/// A party's opening balance as the books hold it now.
final class OpeningSnapshot {
  const OpeningSnapshot({
    required this.partyId,
    required this.partyName,
    required this.opening,
    required this.entries,
  });

  final String partyId;
  final String partyName;

  /// What the party row says they started owing. Negative is money the shop
  /// was holding for them.
  final Money opening;

  /// The opening entries not yet reversed — one, normally; none for a party
  /// entered owing nothing.
  final List<OpeningEntrySnapshot> entries;
}

/// One entry undone by a correction, and the mirror that undoes it.
final class OpeningReversal {
  const OpeningReversal({required this.reversesEntryId, required this.journal});

  final String reversesEntryId;
  final JournalEntryPosting journal;
}

/// Everything correcting one opening balance writes, bar the new opening
/// entry itself, which is posted by the same code that posted the first one
/// so there is only ever one definition of what an opening entry is.
final class OpeningCorrectionPosting {
  const OpeningCorrectionPosting({
    required this.partyId,
    required this.partyName,
    required this.was,
    required this.now,
    required this.reason,
    required this.reversals,
    required this.auditSummary,
  });

  final String partyId;
  final String partyName;
  final Money was;
  final Money now;
  final String reason;
  final List<OpeningReversal> reversals;
  final String auditSummary;

  void assertBalanced() {
    for (final r in reversals) {
      final debit = Money.sum([for (final l in r.journal.lines) l.debit]);
      final credit = Money.sum([for (final l in r.journal.lines) l.credit]);
      if (debit != credit) {
        throw StateError(
          'Correcting the opening balance of $partyName would post an '
          'unbalanced entry: debits ${debit.amountOnly}, credits '
          '${credit.amountOnly}.',
        );
      }
    }
  }
}

/// Builds the correction of an opening balance, or refuses it in words.
final class OpeningCorrectionBuilder {
  const OpeningCorrectionBuilder();

  /// [journalNumbers] holds one number for each entry in
  /// [OpeningSnapshot.entries], in the same order.
  OpeningCorrectionPosting build({
    required ActorContext actor,
    required OpeningSnapshot snapshot,
    required Money opening,
    required String reason,
    required List<AllocatedNumber> journalNumbers,
  }) {
    final why = reason.trim();
    if (why.isEmpty) {
      throw const VoidRefused('A correction has to say why.');
    }
    if (opening == snapshot.opening) {
      throw VoidRefused(
        "${snapshot.partyName}'s opening balance is already "
        '${opening.amountOnly}. There is nothing to correct.',
      );
    }
    if (journalNumbers.length != snapshot.entries.length) {
      throw ArgumentError.value(
        journalNumbers.length,
        'journalNumbers',
        'one number is needed for each of the ${snapshot.entries.length} '
            'opening entries being reversed',
      );
    }

    final posting = OpeningCorrectionPosting(
      partyId: snapshot.partyId,
      partyName: snapshot.partyName,
      was: snapshot.opening,
      now: opening,
      reason: why,
      reversals: [
        for (var i = 0; i < snapshot.entries.length; i++)
          OpeningReversal(
            reversesEntryId: snapshot.entries[i].entryId,
            journal: reverseEntry(
              snapshot.entries[i].entry,
              actor: actor,
              number: journalNumbers[i],
              reason: 'opening balance of ${snapshot.partyName} — $why',
            ),
          ),
      ],
      auditSummary:
          'Opening balance of ${snapshot.partyName} corrected from '
          '${snapshot.opening.amountOnly} to ${opening.amountOnly}: $why',
    );
    posting.assertBalanced();
    return posting;
  }
}
