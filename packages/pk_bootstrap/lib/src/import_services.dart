part of 'app_services.dart';

/// What an import brought in.
final class ImportResult {
  const ImportResult({required this.added, required this.skipped});

  final int added;

  /// Rows left out, or brought in with something left out, and why.
  final List<ImportProblem> skipped;
}

/// Bringing a shop's existing item list and khata in from a spreadsheet.
///
/// Every row goes in through the same writers the item and party screens
/// use, one at a time, so an opening stock or an opening balance is posted
/// to the books exactly as if it had been typed. A row that cannot go in —
/// a name the shop already has, a barcode another item carries — is left
/// out and said, and the rest still go in.
final class ImportServices {
  ImportServices._(this._app);

  final AppServices _app;

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  Future<ImportResult> items(ImportPlan<ItemRow> plan) async {
    _app.require(Permission.settings);
    final firm = (await _app.queries.currentFirm())!;
    final units = await _app.queries.units(firm.id);
    final pieces = units.firstWhere(
      (u) => u.code == 'pcs',
      orElse: () => units.first,
    );
    var added = 0;
    final skipped = <ImportProblem>[];
    for (final (line, row) in plan.rows) {
      final wanted = row.unit == null ? null : _squash(row.unit!);
      final unit = wanted == null
          ? pieces
          : units
                    .where(
                      (u) =>
                          _squash(u.code) == wanted ||
                          _squash(u.name) == wanted,
                    )
                    .firstOrNull ??
                pieces;
      final same = await _app.queries.searchItems(
        firm.id,
        query: row.name,
        limit: 10,
      );
      if (same.any((i) => i.name.toLowerCase() == row.name.toLowerCase())) {
        skipped.add(ImportProblem(line, '${row.name} is already an item'));
        continue;
      }
      final cost = row.purchasePrice;
      try {
        await _app.catalogue.addItem(
          _app.actorNow(),
          ItemDraft(
            name: row.name,
            baseUnitId: unit.id,
            saleRate: Rate.raw(row.salePrice.inPaisa * 1000),
            purchaseRate: cost == null ? null : Rate.raw(cost.inPaisa * 1000),
            code: row.code,
            barcode: row.barcode,
            category: row.category,
            hsCode: row.hsCode,
            minStock: row.minStock,
            openingStock: row.openingStock,
            openingRate: Rate.raw((cost ?? row.salePrice).inPaisa * 1000),
          ),
        );
        added++;
      } on Object catch (e) {
        skipped.add(ImportProblem(line, '${row.name}: $e'));
      }
    }
    return ImportResult(added: added, skipped: skipped);
  }

  Future<ImportResult> parties(ImportPlan<PartyRow> plan) async {
    _app.require(Permission.settings);
    final firm = (await _app.queries.currentFirm())!;
    var added = 0;
    final skipped = <ImportProblem>[];
    for (final (line, row) in plan.rows) {
      final same = await _app.queries.searchParties(
        firm.id,
        query: row.name,
        limit: 10,
      );
      if (same.any((p) => p.name.toLowerCase() == row.name.toLowerCase())) {
        skipped.add(ImportProblem(line, '${row.name} is already in the khata'));
        continue;
      }
      // A supplier's balance is what the shop owes them, which the books
      // keep as purchase bills. Brought in without it, and said.
      final carried = row.isSupplier ? Money.zero : row.balance;
      try {
        await _app.catalogue.addParty(
          _app.actorNow(),
          PartyDraft(
            name: row.name,
            partyType: row.isSupplier ? 'supplier' : 'customer',
            phone: row.phone,
            city: row.city,
            openingBalance: carried,
          ),
        );
        added++;
        if (row.isSupplier && !row.balance.isZero) {
          skipped.add(
            ImportProblem(
              line,
              '${row.name} was added without the ${row.balance.abs} owed; '
              'enter it as a purchase bill',
            ),
          );
        }
      } on Object catch (e) {
        skipped.add(ImportProblem(line, '${row.name}: $e'));
      }
    }
    return ImportResult(added: added, skipped: skipped);
  }
}
