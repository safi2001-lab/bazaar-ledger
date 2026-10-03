part of 'app_services.dart';

/// Goods on the khata now, priced later; and the recovery man's round on one
/// sheet (M55). Reached as `services.collections`.
///
/// Both halves are about the day a khata is settled. Goods given rate-later
/// are a delivery challan whose lines carry no rate (see `goods_given.dart`
/// for why that is the right document), so giving them is M25's challan
/// path and pricing them is M25's challan-to-bill path at the counter; this
/// only reads them back for the khata and the chase list. A sheet is made
/// from the chase list and recorded on the man's return.
///
/// Permissions. Handing goods over is selling (the challan path asks for
/// [Permission.sell]). The chase list asks nothing to be read, and
/// everything written from it — a reminder sent, a promise taken — takes
/// [Permission.takePayments]; so making a sheet, which sends a man out on
/// the chase list's behalf, takes that too. Recording what he brought back
/// takes receipts, and takes [Permission.takePayments] at its own door.
final class CollectionServices {
  CollectionServices._(this._app);

  final AppServices _app;

  /// The khata's and the chase list's reads.
  CollectionQueries get queries => DriftCollectionQueries(_app.database);

  CollectionSheetUseCase get _sheets => CollectionSheetUseCase(
    writer: DriftCollectionWriter(runner: _app._runner),
  );

  Future<String?> get _firmId async => (await _app.queries.currentFirm())?.id;

  // -------------------------------------------------------------------------
  // Goods given, rate later
  // -------------------------------------------------------------------------

  /// Every challan to [partyId] not yet billed, oldest first.
  Future<List<GoodsGiven>> goodsGivenTo(String partyId) async {
    final firm = await _firmId;
    if (firm == null) return const [];
    return queries.goodsGivenTo(firm, partyId);
  }

  /// Every customer holding goods with no rate on them yet.
  Future<List<UnpricedParty>> unpricedParties() async {
    final firm = await _firmId;
    if (firm == null) return const [];
    return queries.unpricedParties(firm);
  }

  /// Hands [draft]'s goods over with the rate to be agreed later: a
  /// delivery challan whose lines carry no rate. They leave the shelf at
  /// what they cost, and nothing is owed until the challan is billed.
  ///
  /// Through the challan's own use case, so the shelf is asked (M53), the
  /// customer is required, and a loose line is refused, exactly as for any
  /// challan.
  Future<({String id, String docNo})> giveRateLater(SaleDraft draft) =>
      _app.issueChallan(_app.actorNow(), rateLater(draft));

  // -------------------------------------------------------------------------
  // The recovery man's round
  // -------------------------------------------------------------------------

  /// Whether whoever is signed in may send a man out with a sheet.
  bool get mayMakeSheets => _app.can(Permission.takePayments);

  /// Whether whoever is signed in may record what he brought back.
  bool get mayRecordReturn => _app.can(Permission.takePayments);

  /// The shop's sheets, newest first.
  Future<List<CollectionSheet>> sheets() async {
    final firm = await _firmId;
    if (firm == null) return const [];
    return queries.sheets(firm);
  }

  Future<CollectionSheet?> sheet(String sheetId) async {
    final firm = await _firmId;
    if (firm == null) return null;
    return queries.sheet(firm, sheetId);
  }

  /// Makes a numbered sheet of [draft]'s customers for the man named in it.
  Future<CollectionSheet> makeSheet(SheetDraft draft) {
    _app.require(Permission.takePayments);
    return _sheets.make(_app.actorNow(), draft);
  }

  /// Writes the man's return on every khata at once: [marks] by line
  /// number, a line with no mark not reached.
  Future<SettledRound> recordReturn(String sheetId, Map<int, SheetMark> marks) {
    _app.require(Permission.takePayments);
    return _sheets.settle(_app.actorNow(), sheetId, marks);
  }
}
