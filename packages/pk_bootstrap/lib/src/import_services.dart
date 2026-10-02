part of 'app_services.dart';

/// What an import brought in.
final class ImportResult {
  const ImportResult({
    required this.added,
    required this.skipped,
    this.updated = 0,
    this.partial = const [],
  });

  final int added;

  /// Rows already in the shop and brought up to date from the sheet.
  final int updated;

  /// Rows left out, and why.
  final List<ImportProblem> skipped;

  /// Rows brought in with something left out, and what: a supplier's
  /// balance, an oversold shelf, a barcode Excel mangled.
  final List<ImportProblem> partial;
}

/// What to do with a row the shop already has.
enum DuplicateChoice {
  /// Leave the shop's own as it is, and say so.
  skip,

  /// Bring it up to date from the sheet: prices from the sheet, codes only
  /// where the shop has none. Stock on the shelf and money in the khata are
  /// never touched, since both are facts with a history behind them.
  update,
}

/// How a sheet's row was found to be something the shop already has.
enum MatchedBy { barcode, code, phone, name }

/// One row of a sheet that is already in the shop.
final class ImportMatch {
  const ImportMatch({
    required this.line,
    required this.name,
    required this.existingId,
    required this.existingName,
    required this.by,
  });

  final int line;

  /// As the sheet writes it.
  final String name;
  final String existingId;

  /// As the shop already has it.
  final String existingName;
  final MatchedBy by;
}

/// What the shop already has that a sheet would touch — shown before
/// anything is written, so nothing is doubled and nothing is a surprise.
final class ImportReview {
  const ImportReview({
    this.matches = const [],
    this.unknownUnits = const {},
    this.secondaryUnits = const {},
  });

  /// Rows the shop already has, by line.
  final List<ImportMatch> matches;

  /// A unit word in the sheet the shop has no unit for, and how many rows
  /// carry it. Those items are counted in pieces, prices and stock as the
  /// sheet has them.
  final Map<String, int> unknownUnits;

  /// Second units the shop cannot keep for an item ("1 BOX = 10 pcs"), and
  /// how many rows carry each. The item comes in by its first unit only.
  final Map<String, int> secondaryUnits;
}

/// Every item the shop has, found by what a sheet can name it by.
final class _ItemIndex {
  final byBarcode = <String, ItemSummary>{};
  final byCode = <String, ItemSummary>{};
  final byName = <String, ItemSummary>{};

  void add(ItemSummary item) {
    if (item.barcode case final b?) byBarcode[b.trim()] = item;
    if (item.code case final c?) byCode[c.trim().toLowerCase()] = item;
    byName[ItemDraft(
          name: item.name,
          baseUnitId: '',
          saleRate: Rate.zero,
        ).searchKey] =
        item;
  }

  (ItemSummary, MatchedBy)? find(ItemRow row) {
    if (row.barcode case final b? when byBarcode[b.trim()] != null) {
      return (byBarcode[b.trim()]!, MatchedBy.barcode);
    }
    if (row.code case final c? when byCode[c.trim().toLowerCase()] != null) {
      return (byCode[c.trim().toLowerCase()]!, MatchedBy.code);
    }
    final key = ItemDraft(
      name: row.name,
      baseUnitId: '',
      saleRate: Rate.zero,
    ).searchKey;
    final named = byName[key];
    return named == null ? null : (named, MatchedBy.name);
  }
}

/// Every customer and supplier the shop has, by mobile and by name.
final class _PartyIndex {
  final byMobile = <String, PartySummary>{};
  final byName = <String, PartySummary>{};

  void add(PartySummary party) {
    if (whatsappNumber(party.phone) case final m?) byMobile[m] = party;
    byName[PartyDraft(name: party.name).searchKey] = party;
  }

  (PartySummary, MatchedBy)? find(PartyRow row) {
    // A mobile is one pocket however it is written; it is the better
    // witness than a name, which two customers can share.
    if (whatsappNumber(row.phone) case final m? when byMobile[m] != null) {
      return (byMobile[m]!, MatchedBy.phone);
    }
    final named = byName[PartyDraft(name: row.name).searchKey];
    return named == null ? null : (named, MatchedBy.name);
  }
}

/// Bringing a shop's existing item list and khata in from a spreadsheet.
///
/// Every row goes in through the same writers the item and party screens
/// use, one at a time, so an opening stock or an opening balance is posted
/// to the books exactly as if it had been typed, audited, and queued for
/// the other counters. A row that cannot go in — a barcode another item
/// carries — is left out and said, and the rest still go in.
///
/// What the shop already has is found before anything is written (M52), by
/// barcode, code or name for an item and by mobile or name for a party, so
/// a list brought in twice, or one that overlaps what was typed by hand, is
/// never doubled. The shop chooses to leave those rows or bring them up to
/// date.
final class ImportServices {
  ImportServices._(this._app);

  final AppServices _app;

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static Rate _rate(Money m) => Rate.raw(m.inPaisa * 1000);

  /// `10`, `2.5`: a quantity said in a sentence, not printed on a bill.
  static String _plain(Qty q) {
    final t = q.inThousandths.abs();
    final whole = '${q.isNegative ? '-' : ''}${t ~/ 1000}';
    final frac = (t % 1000)
        .toString()
        .padLeft(3, '0')
        .replaceAll(RegExp(r'0+$'), '');
    return frac.isEmpty ? whole : '$whole.$frac';
  }

  /// The words of a refusal, rather than an exception's class name.
  static String _words(Object e) => switch (e) {
    StateError(:final message) => message,
    ArgumentError(:final message) => '$message',
    PermissionDenied(:final reason) => reason,
    _ => '$e',
  };

  /// A Pakistani mobile as the khata keeps it, `0300 1234567`, however the
  /// sheet wrote it — including the `3001234567` Excel leaves when it
  /// drops the leading nought off a number. Anything else as written.
  static String? _phone(String? raw) {
    final number = whatsappNumber(raw);
    if (number == null) return raw?.trim();
    final national = number.substring(2);
    return '0${national.substring(0, 3)} ${national.substring(3)}';
  }

  Future<_ItemIndex> _items(String firmId) async {
    final index = _ItemIndex();
    String? after;
    while (true) {
      final page = await _app.queries.searchItems(
        firmId,
        afterId: after,
        limit: 500,
      );
      page.forEach(index.add);
      if (page.length < 500) return index;
      after = page.last.id;
    }
  }

  Future<_PartyIndex> _parties(String firmId) async {
    final index = _PartyIndex();
    (await _app.queries.searchParties(
      firmId,
      limit: 1 << 30,
    )).forEach(index.add);
    return index;
  }

  /// The shop's unit for a sheet's unit word, or null when it has none.
  static ({String id, String code, String name, int decimals})? _unitFor(
    List<({String id, String code, String name, int decimals})> units,
    String word,
  ) {
    final wanted = _squash(word);
    return units
        .where((u) => _squash(u.code) == wanted || _squash(u.name) == wanted)
        .firstOrNull;
  }

  /// What a sheet of items would touch, for the preview.
  Future<ImportReview> reviewItems(ImportPlan<ItemRow> plan) async {
    final firm = (await _app.queries.currentFirm())!;
    final index = await _items(firm.id);
    final units = await _app.queries.units(firm.id);
    final edges = await _app.queries.unitConversions(firm.id);
    final matches = <ImportMatch>[];
    final unknown = <String, int>{};
    final second = <String, int>{};
    for (final (line, row) in plan.rows) {
      if (index.find(row) case (final item, final by)) {
        matches.add(
          ImportMatch(
            line: line,
            name: row.name,
            existingId: item.id,
            existingName: item.name,
            by: by,
          ),
        );
      }
      final base = row.unit == null ? null : _unitFor(units, row.unit!);
      if (row.unit != null && base == null) {
        unknown.update(row.unit!, (n) => n + 1, ifAbsent: () => 1);
      }
      if (row.secondaryUnit case final s?) {
        final other = _unitFor(units, s);
        // A second unit the shop already converts to the first, for every
        // item (grams of a kilo item, pieces of a dozen), is kept already.
        final converts =
            base != null &&
            other != null &&
            edges.any(
              (e) =>
                  e.itemId == null &&
                  {e.fromUnitId, e.toUnitId}.containsAll({base.id, other.id}),
            );
        if (!converts) {
          final n = row.conversion;
          final key =
              '1 ${row.unit ?? 'pcs'} = ${n == null ? '?' : _plain(n)} $s';
          second.update(key, (c) => c + 1, ifAbsent: () => 1);
        }
      }
    }
    return ImportReview(
      matches: matches,
      unknownUnits: unknown,
      secondaryUnits: second,
    );
  }

  /// What a khata sheet would touch, for the preview.
  Future<ImportReview> reviewParties(ImportPlan<PartyRow> plan) async {
    final firm = (await _app.queries.currentFirm())!;
    final index = await _parties(firm.id);
    return ImportReview(
      matches: [
        for (final (line, row) in plan.rows)
          if (index.find(row) case (final party, final by))
            ImportMatch(
              line: line,
              name: row.name,
              existingId: party.id,
              existingName: party.name,
              by: by,
            ),
      ],
    );
  }

  Future<ImportResult> items(
    ImportPlan<ItemRow> plan, {
    DuplicateChoice duplicates = DuplicateChoice.skip,
    void Function(int done, int total)? onProgress,
  }) async {
    _app.require(Permission.settings);
    final firm = (await _app.queries.currentFirm())!;
    final units = await _app.queries.units(firm.id);
    final pieces = units.firstWhere(
      (u) => u.code == 'pcs',
      orElse: () => units.first,
    );
    final index = await _items(firm.id);
    var added = 0;
    var updated = 0;
    final skipped = <ImportProblem>[];
    final through = <int>{};
    for (final (i, (line, row)) in plan.rows.indexed) {
      onProgress?.call(i, plan.rows.length);
      final unit =
          (row.unit == null ? null : _unitFor(units, row.unit!)) ?? pieces;
      final cost = row.purchasePrice;
      try {
        if (index.find(row) case (final item, _)) {
          if (duplicates == DuplicateChoice.skip) {
            skipped.add(
              ImportProblem.of(
                line,
                ImportIssue.alreadyItem,
                name: row.name,
                value: item.name,
              ),
            );
            continue;
          }
          // Prices from the sheet, since bringing them up to date is why a
          // shop imports a list twice. A code or barcode only where the
          // shop has none: the counter scans the ones it has. The shelf is
          // left as counted, whatever the sheet says is on it.
          await _app.catalogue.updateItem(
            _app.actorNow(),
            item.id,
            ItemDraft(
              name: item.name,
              baseUnitId: item.unitId,
              saleRate: _rate(row.salePrice),
              purchaseRate: cost == null ? item.purchaseRate : _rate(cost),
              wholesaleRate: row.wholesalePrice == null
                  ? item.wholesaleRate
                  : _rate(row.wholesalePrice!),
              vipRate: item.vipRate,
              mrp: row.mrp ?? item.mrp,
              code: item.code ?? row.code,
              barcode: item.barcode ?? row.barcode,
              category: item.category ?? row.category,
              description: item.description ?? row.description,
              hsCode: item.hsCode ?? row.hsCode,
              minStock: row.minStock.isZero ? item.minStock : row.minStock,
              tracksStock: item.tracksStock,
              tracksBatch: item.tracksBatch,
              tracksSerial: item.tracksSerial,
            ),
          );
          updated++;
          through.add(line);
          continue;
        }
        await _app.catalogue.addItem(
          _app.actorNow(),
          ItemDraft(
            name: row.name,
            baseUnitId: unit.id,
            saleRate: _rate(row.salePrice),
            purchaseRate: cost == null ? null : _rate(cost),
            wholesaleRate: row.wholesalePrice == null
                ? null
                : _rate(row.wholesalePrice!),
            mrp: row.mrp,
            code: row.code,
            barcode: row.barcode,
            category: row.category,
            description: row.description,
            hsCode: row.hsCode,
            minStock: row.minStock,
            tracksStock: row.tracksStock,
            openingStock: row.tracksStock ? row.openingStock : Qty.zero,
            openingRate: _rate(cost ?? row.salePrice),
          ),
        );
        // Not added to the index: the sheet has no name twice, and a code
        // or barcode twice is refused by the writer, in words.
        added++;
        through.add(line);
      } on Object catch (e) {
        skipped.add(
          ImportProblem.of(
            line,
            ImportIssue.other,
            name: row.name,
            value: _words(e),
          ),
        );
      }
    }
    onProgress?.call(plan.rows.length, plan.rows.length);
    return ImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      partial: [
        for (final c in plan.caveats)
          if (through.contains(c.line)) c,
      ],
    );
  }

  Future<ImportResult> parties(
    ImportPlan<PartyRow> plan, {
    DuplicateChoice duplicates = DuplicateChoice.skip,
    void Function(int done, int total)? onProgress,
  }) async {
    _app.require(Permission.settings);
    final firm = (await _app.queries.currentFirm())!;
    final index = await _parties(firm.id);
    var added = 0;
    var updated = 0;
    final skipped = <ImportProblem>[];
    final through = <int>{};
    for (final (i, (line, row)) in plan.rows.indexed) {
      onProgress?.call(i, plan.rows.length);
      try {
        if (index.find(row) case (final party, _)) {
          if (duplicates == DuplicateChoice.skip) {
            skipped.add(
              ImportProblem.of(
                line,
                ImportIssue.alreadyParty,
                name: row.name,
                value: party.name,
              ),
            );
            continue;
          }
          // What the khata is missing, from the sheet. What they owe is
          // left as the khata has it: it has bills and payments behind it,
          // and an opening balance is set once, when the khata is begun.
          final have = await _app.queries.partyDraft(firm.id, party.id);
          if (have == null) throw StateError('${party.name} is not here.');
          await _app.catalogue.updateParty(
            _app.actorNow(),
            party.id,
            PartyDraft(
              name: have.name,
              partyType: have.partyType,
              phone: have.phone ?? _phone(row.phone),
              whatsapp: have.whatsapp,
              addressLine1: have.addressLine1 ?? row.address,
              city: have.city ?? row.city,
              ntn: have.ntn,
              strn: have.strn,
              cnic: have.cnic,
              buyerRegistrationType: have.buyerRegistrationType,
              isOnAtl: have.isOnAtl,
              openingBalance: have.openingBalance,
              creditLimit: have.creditLimit ?? row.creditLimit,
              creditDays: have.creditDays,
              priceTier: have.priceTier,
              defaultDiscountBp: have.defaultDiscountBp,
            ),
          );
          updated++;
          continue;
        }
        // A supplier's balance is what the shop owes them, which the books
        // keep as purchase bills and the khata reads from them. Brought in
        // without it, and said — on the preview, before, and here.
        await _app.catalogue.addParty(
          _app.actorNow(),
          PartyDraft(
            name: row.name,
            partyType: row.isSupplier ? 'supplier' : 'customer',
            phone: _phone(row.phone),
            city: row.city,
            addressLine1: row.address,
            creditLimit: row.creditLimit,
            openingBalance: row.isSupplier ? Money.zero : row.balance,
          ),
        );
        added++;
        through.add(line);
      } on Object catch (e) {
        skipped.add(
          ImportProblem.of(
            line,
            ImportIssue.other,
            name: row.name,
            value: _words(e),
          ),
        );
      }
    }
    onProgress?.call(plan.rows.length, plan.rows.length);
    return ImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      partial: [
        for (final c in plan.caveats)
          if (through.contains(c.line)) c,
      ],
    );
  }
}
