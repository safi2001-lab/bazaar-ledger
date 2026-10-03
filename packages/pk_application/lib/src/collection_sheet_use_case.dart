import 'package:pk_domain/pk_domain.dart';

import 'record_receipt_use_case.dart';

/// What saving a round's marks wrote (M55).
final class SettledRound {
  const SettledRound({required this.sheet, required this.receipts});

  /// The sheet as it now stands, every mark on it with its receipt or
  /// promise.
  final CollectionSheet sheet;

  /// The receipts taken, in line order.
  final List<RecordedReceipt> receipts;
}

/// The recovery man's round: a numbered sheet made from the chase list, and
/// what he brought back written on the khatas in one go (M55).
///
/// The same shape as every use case here: one transaction, the rows read
/// inside it, pure rules deciding what is written, and what was written
/// handed back.
///
/// A sheet is made from the khatas as they stand inside its transaction, so
/// what the man is told to collect is what the books say at that moment,
/// not what a list on screen said a minute before.
///
/// Settling it takes each payment as an ordinary receipt —
/// [RecordReceiptUseCase.recordOn] on this same transaction, oldest bill
/// first, so a round's receipt is exactly the receipt the khata's own
/// Receive would have written — writes each promise as M38 keeps one, and
/// closes the sheet; if any of it fails, none of it is written, so a round
/// is never half on the khatas.
///
/// Who may do which is decided at the service boundary, where the role is
/// known.
final class CollectionSheetUseCase {
  const CollectionSheetUseCase({required this.writer});

  final CollectionWriter writer;

  /// Makes a numbered sheet for [draft]'s customers, in the order given.
  Future<CollectionSheet> make(ActorContext actor, SheetDraft draft) =>
      writer.inTransaction(actor, (write) async {
        if (draft.problem case final problem?) {
          throw CollectionRefused(problem);
        }
        final lines = <SheetLine>[];
        for (final partyId in draft.partyIds) {
          final party = await write.party(partyId);
          if (party == null) {
            throw const CollectionRefused(
              'A customer on the sheet is not in this khata.',
            );
          }
          // Read now, inside the transaction: a customer who paid at the
          // counter since the list was drawn owes nothing, and a man sent to
          // collect from them is sent to annoy them.
          if (!party.balance.isPositive) {
            throw CollectionRefused(
              '${party.name} owes nothing now. Take them off the sheet.',
            );
          }
          final bills = await write.payments.openBillsFor(partyId);
          lines.add(
            SheetLine(
              lineNo: lines.length + 1,
              partyId: party.id,
              partyName: party.name,
              phone: party.phone,
              group: party.group,
              due: party.balance,
              unpriced: await write.unpricedLines(partyId),
              bills: [
                for (final b in bills)
                  SheetBill(
                    documentId: b.documentId,
                    docNo: b.docNo,
                    dateLocal: b.dateLocal,
                    outstanding: b.outstanding,
                  ),
              ],
            ),
          );
        }
        final number = await write.nextNumber(collectionSheetDocType);
        final sheet = CollectionSheet(
          id: '',
          sheetNo: number.formatted,
          dateLocal: actor.businessDate.value,
          collector: draft.collector.trim(),
          collectorUserId: draft.collectorUserId,
          madeBy: await write.actorName(),
          title: (draft.title ?? '').trim().isEmpty
              ? null
              : draft.title!.trim(),
          lines: lines,
        );
        return sheet.withId(await write.addSheet(sheet));
      });

  /// Writes the man's return: [marks] by line number. A line with no mark
  /// was not reached and writes nothing.
  Future<SettledRound> settle(
    ActorContext actor,
    String sheetId,
    Map<int, SheetMark> marks,
  ) => writer.inTransaction(actor, (write) async {
    final sheet = await write.sheet(sheetId);
    if (sheet == null) {
      throw const CollectionRefused('There is no such sheet.');
    }
    // Once. A round recorded twice is every payment on it taken twice.
    if (sheet.isSettled) {
      throw CollectionRefused(
        '${sheet.sheetNo} was already recorded on ${sheet.settledOn}.',
      );
    }
    final today = actor.businessDate.value;
    final byNo = {for (final l in sheet.lines) l.lineNo: l};
    for (final MapEntry(key: no, value: mark) in marks.entries) {
      final line = byNo[no];
      if (line == null) {
        throw CollectionRefused('${sheet.sheetNo} has no line $no.');
      }
      if (mark.problemFor(line, today) case final problem?) {
        throw CollectionRefused(problem);
      }
    }

    final receipts = <RecordedReceipt>[];
    final lines = <SheetLine>[];
    for (final line in sheet.lines) {
      final mark = marks[line.lineNo];
      if (mark == null) {
        lines.add(line.withResult(null));
        continue;
      }
      var result = mark.resultFor(line);
      switch (mark.outcome) {
        case CollectionOutcome.paid || CollectionOutcome.partial:
          final taken = await RecordReceiptUseCase.recordOn(
            write.payments,
            actor,
            ReceiptDraft(
              partyId: line.partyId,
              amount: result.amount!,
              mode: mark.mode,
              paymentAccountId: mark.paymentAccountId!,
              // The man is named on the receipt itself, so the khata's
              // payment page says who brought it, from which round.
              notes: [
                'Wasooli ${sheet.sheetNo} · ${sheet.collector}',
                if ((mark.note ?? '').trim().isNotEmpty) mark.note!.trim(),
              ].join(' · '),
              // M54: a cheque handed to the man is the khata's cheque (M6):
              // its number, bank and day go on the receipt, which waits in
              // Cheques in Hand to be banked, on this same transaction.
              chequeNo: mark.mode == 'cheque' ? result.chequeNo : null,
              chequeBank: mark.mode == 'cheque' ? result.chequeBank : null,
              chequeDateUtcMillis: mark.mode == 'cheque'
                  ? mark.chequeDateUtcMillis
                  : null,
            ),
          );
          receipts.add(taken);
          result = result.written(paymentNo: taken.paymentNo);
        case CollectionOutcome.promise:
          final id = await write.addPromise(
            PromiseDraft(
              partyId: line.partyId,
              promisedFor: mark.promisedFor!,
              amount: mark.amount,
              note: [
                '${sheet.collector} (${sheet.sheetNo})',
                if ((mark.note ?? '').trim().isNotEmpty) mark.note!.trim(),
              ].join(': '),
            ),
            partyName: line.partyName,
          );
          result = result.written(promiseId: id);
        case CollectionOutcome.shopClosed || CollectionOutcome.refused:
          break;
      }
      lines.add(line.withResult(result));
    }

    final settled = sheet.settled(
      on: today,
      by: await write.actorName(),
      lines: lines,
    );
    await write.putSheet(
      settled,
      action: 'COLLECTION_SHEET_SETTLED',
      summary:
          '${sheet.sheetNo}: ${sheet.collector} brought '
          '${settled.collected.amountOnly} of '
          '${settled.expected.amountOnly}',
      amount: settled.collected,
    );
    return SettledRound(sheet: settled, receipts: receipts);
  });
}
