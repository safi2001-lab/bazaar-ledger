part of 'app_services.dart';

/// Repeating bills: keeping them, saying which are due, and making them.
///
/// ## Who may do what
///
/// A repeating bill is a bill rung ahead of time, so everything here takes
/// the counter's permission (`sell`): making one from a bill, changing it,
/// pausing it, ending it, and making its bills. The bills themselves go
/// through the one sale path, so every check the counter makes is made again
/// below every screen: the discount ceiling of whoever is signed in (M22), a
/// shelf set to block (M53), a loose line on a shop that reports to FBR
/// (M37). What the counter only ASKS — a customer past their credit limit, a
/// bounced cheque still owed, a shelf set to warn — is asked here too:
/// a bill made by itself is held and listed for the cashier's word, never
/// made past the question.
///
/// ## The day the books say
///
/// Every bill is dated the day it is made. A bill for a day the app was not
/// opened is made today, for that day, and its history says both. That is
/// also M42's answer for books closed since: today is never inside books
/// the owner has closed unless the day itself was closed, and then the
/// counter could not ring it either.
final class RecurringServices {
  RecurringServices._(this._app);

  final AppServices _app;

  AppQueries get _queries => _app.queries;

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('No shop is set up on this phone yet.');
    return id.firmId;
  }

  /// Today, by the shop's clock.
  BusinessDate get today => BusinessDate.now(_app.clock);

  /// Whether whoever is signed in may keep and make repeating bills.
  bool get mayUse => _app.can(Permission.sell);

  /// A fresh id for a new repeating bill.
  String newId() => _app.ids.next();

  // -------------------------------------------------------------------------
  // Reading
  // -------------------------------------------------------------------------

  /// Every repeating bill the shop keeps, ended ones too, by customer.
  Future<List<RecurringBill>> all() async {
    _app.require(Permission.sell);
    final rows = await _app.database
        .customSelect(
          'SELECT setting_key, setting_value FROM settings '
          "WHERE firm_id = ? AND setting_key LIKE 'recurring.sale.%' "
          'AND deleted_at_utc IS NULL',
          variables: [Variable<String>(_firmId)],
        )
        .get();
    final out = <RecurringBill>[
      for (final r in rows)
        ?RecurringBill.fromJson(
          r
              .read<String>('setting_key')
              .substring(recurringBillSettingPrefix.length),
          r.read<String>('setting_value'),
        ),
    ];
    out.sort((a, b) {
      final byName = a.partyName.toLowerCase().compareTo(
        b.partyName.toLowerCase(),
      );
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return out;
  }

  /// One repeating bill, or null when it is not kept.
  Future<RecurringBill?> byId(String id) async {
    _app.require(Permission.sell);
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(_firmId),
            Variable<String>(recurringBillSettingKey(id)),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : RecurringBill.fromJson(id, row.read<String>('setting_value'));
  }

  /// A customer's repeating bills.
  Future<List<RecurringBill>> forParty(String partyId) async => [
    for (final b in await all())
      if (b.partyId == partyId) b,
  ];

  /// The names of [bill]'s items that are no longer kept. Flagged on the
  /// screen, never crashed on: the template still says what it was.
  Future<List<String>> goneItems(RecurringBill bill) async {
    final firmId = _firmId;
    return [
      for (final l in bill.lines)
        if (l.itemId case final id?)
          if (await _queries.itemById(firmId, id) == null) l.name,
    ];
  }

  /// The repeating bills whose day has come, oldest day first.
  ///
  /// Read when the home screen is drawn: on opening the app, on coming back
  /// to it, after every write. There is nothing else that would wake it.
  Future<List<RecurringDue>> due() async {
    final now = today;
    final out = <RecurringDue>[];
    for (final bill in await all()) {
      final dates = bill.dueOn(now);
      if (dates.isEmpty) continue;
      out.add(
        RecurringDue(bill: bill, dates: dates, gone: await goneItems(bill)),
      );
    }
    out.sort((a, b) {
      final byDay = a.earliest.value.compareTo(b.earliest.value);
      return byDay != 0
          ? byDay
          : a.bill.partyName.toLowerCase().compareTo(
              b.bill.partyName.toLowerCase(),
            );
    });
    return out;
  }

  /// The bills [id] made, newest day first, cancelled ones marked.
  Future<List<RecurringMade>> history(String id) async {
    _app.require(Permission.sell);
    final rows = await _app.database
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.status, d.total_paisa, d.doc_date_local,
                 json_extract(a.after_json, '\$.for') AS for_date,
                 json_extract(a.after_json, '\$.auto') AS by_itself
          FROM audit_log a
          JOIN documents d ON d.id = a.entity_id AND d.firm_id = a.firm_id
          WHERE a.firm_id = ? AND a.action_code = ?
            AND json_extract(a.after_json, '\$.template') = ?
          ORDER BY for_date DESC, d.doc_date_local DESC, d.doc_no DESC
          ''',
          variables: [
            Variable<String>(_firmId),
            const Variable<String>(recurringBillMadeAction),
            Variable<String>(id),
          ],
        )
        .get();
    return [
      for (final r in rows)
        RecurringMade(
          documentId: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          forDate: BusinessDate(
            r.readNullable<String>('for_date') ??
                r.read<String>('doc_date_local'),
          ),
          madeOn: BusinessDate(r.read<String>('doc_date_local')),
          total: Money.paisa(r.read<int>('total_paisa')),
          isVoid: r.read<String>('status') == 'void',
          byItself: (r.readNullable<int>('by_itself') ?? 0) == 1,
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // Starting one
  // -------------------------------------------------------------------------

  /// A new repeating bill copied from the bill [documentId], not yet kept:
  /// its customer and goods, every week on the bill's own weekday, starting
  /// tomorrow, at today's prices, reminding only.
  ///
  /// Refused for a walk-in's bill: a repeating bill goes on a khata. Free
  /// lines, serial pieces and items hidden since are left off and said.
  Future<
    ({RecurringBill bill, List<({String name, RecurringLeftOut why})> leftOut})
  >
  startFromBill(String documentId) async {
    _app.require(Permission.sell);
    final firmId = _firmId;
    final copy = await _queries.billCopy(firmId, documentId);
    if (copy == null) {
      throw const RecurringRefused(RecurringProblem.noLines);
    }
    final partyId = copy.partyId;
    final party = partyId == null
        ? null
        : await _queries.partyById(firmId, partyId);
    if (party == null) {
      throw const RecurringRefused(RecurringProblem.noCustomer);
    }
    final serial = <String>{};
    final gone = <String>{};
    for (final l in copy.lines) {
      final id = l.itemId;
      if (id == null || l.isFree) continue;
      final item = await _queries.itemById(firmId, id);
      if (item == null) gone.add(id);
      if (item?.tracksSerial ?? false) serial.add(id);
    }
    final taken = recurringLinesOf(
      copy,
      serialItemIds: serial,
      goneItemIds: gone,
    );
    final now = today;
    return (
      bill: RecurringBill(
        id: newId(),
        partyId: party.id,
        partyName: party.name,
        lines: taken.lines,
        every: RepeatEvery.weekly(weekdayOf(now)),
        startOn: now.addDays(1),
        billDiscount: taken.billDiscount,
        fromDocNo: copy.docNo,
      ),
      leftOut: taken.leftOut,
    );
  }

  /// A new repeating bill for [partyId], from their last bill when they
  /// have one, and with no goods yet when they do not.
  Future<
    ({RecurringBill bill, List<({String name, RecurringLeftOut why})> leftOut})
  >
  startForParty(String partyId) async {
    _app.require(Permission.sell);
    final firmId = _firmId;
    final last = await _queries.lastBillFor(firmId, partyId);
    if (last != null) return startFromBill(last.id);
    final party = await _queries.partyById(firmId, partyId);
    if (party == null) {
      throw const RecurringRefused(RecurringProblem.noCustomer);
    }
    final now = today;
    return (
      bill: RecurringBill(
        id: newId(),
        partyId: party.id,
        partyName: party.name,
        lines: const [],
        every: RepeatEvery.weekly(weekdayOf(now)),
        startOn: now.addDays(1),
      ),
      leftOut: const <({String name, RecurringLeftOut why})>[],
    );
  }

  // -------------------------------------------------------------------------
  // Keeping
  // -------------------------------------------------------------------------

  /// Keeps [bill], new or changed, refused with [RecurringRefused] when it
  /// makes no sense.
  ///
  /// What the books say of one already kept is never taken back by a save
  /// ([RecurringBill.keepingStateOf]): a template changed on one screen
  /// while its bill was being made, or it was paused, on another keeps the
  /// bill it made and the pause.
  Future<void> save(RecurringBill bill) async {
    _app.require(Permission.sell);
    bill.check();
    await _write(
      bill.id,
      (was) => was == null ? bill : bill.keepingStateOf(was),
      action: (was) =>
          was == null ? 'RECURRING_BILL_SET' : 'RECURRING_BILL_CHANGED',
      summary: (now) =>
          '${now.partyName}: ${now.lines.length} item(s), '
          '${_everyWords(now.every)} from ${now.startOn.value}'
          '${now.byItself ? ', made by itself' : ''}',
      mayBeNew: true,
      checkParty: true,
    );
  }

  /// Stops [id] coming due until it is resumed.
  Future<void> pause(String id) async {
    _app.require(Permission.sell);
    await _write(
      id,
      (was) => was!.copyWith(paused: true),
      action: (_) => 'RECURRING_BILL_PAUSED',
      summary: (now) => '${now.partyName}: repeating bill paused',
    );
  }

  /// Lets [id] come due again from today. The days it was paused through
  /// are not owed: the customer was not sent goods those days.
  Future<void> resume(String id) async {
    _app.require(Permission.sell);
    final yesterday = today.addDays(-1);
    await _write(
      id,
      (was) => was!.copyWith(paused: false).handledThrough(yesterday),
      action: (_) => 'RECURRING_BILL_RESUMED',
      summary: (now) => '${now.partyName}: repeating bill resumed',
    );
  }

  /// Ends [id] today. It is kept, with the bills it made, and never comes
  /// due again.
  Future<void> end(String id) async {
    _app.require(Permission.sell);
    final now = today;
    await _write(
      id,
      (was) => was!.copyWith(endedOn: now),
      action: (_) => 'RECURRING_BILL_ENDED',
      summary: (b) => '${b.partyName}: repeating bill ended',
    );
  }

  /// Lets every day of [id] up to and including [through] go without a
  /// bill: the shopkeeper's answer for days the app was not opened.
  Future<void> letGo(String id, BusinessDate through) async {
    _app.require(Permission.sell);
    await _write(
      id,
      (was) => was!.handledThrough(through),
      action: (_) => 'RECURRING_BILL_SKIPPED',
      summary: (b) =>
          '${b.partyName}: no bill for the days up to ${through.value}',
    );
  }

  /// Reads [id] inside a transaction, hands it to [change] and writes what
  /// comes back, with an audit row: the one way a template is written.
  Future<void> _write(
    String id,
    RecurringBill Function(RecurringBill? was) change, {
    required String Function(RecurringBill? was) action,
    required String Function(RecurringBill now) summary,
    bool mayBeNew = false,
    bool checkParty = false,
  }) async {
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final key = recurringBillSettingKey(id);
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, key],
      );
      final before = held?.read<String>('setting_value');
      final was = before == null ? null : RecurringBill.fromJson(id, before);
      if (was == null && !mayBeNew) {
        throw const RecurringRefused(RecurringProblem.notKept);
      }
      final now = change(was);
      if (checkParty) {
        final party = await tx.selectOne(
          'SELECT id FROM parties WHERE id = ? AND firm_id = ? '
          'AND deleted_at_utc IS NULL',
          [now.partyId, actor.firmId],
        );
        if (party == null) {
          throw const RecurringRefused(RecurringProblem.customerGone);
        }
      }
      final value = now.toJson();
      if (held == null) {
        await tx.insert('settings', {
          'setting_key': key,
          'setting_value': value,
          'value_type': 'json',
        }, id: recurringBillRowId(id));
      } else if (before != value) {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': value,
        });
      } else {
        return;
      }
      tx.audit(
        action: action(was),
        entityTable: 'settings',
        entityId: id,
        summary: summary(now),
        before: {'template': before},
        after: {'template': value},
      );
    });
  }

  static String _everyWords(RepeatEvery every) => switch (every.kind) {
    RepeatKind.daily => 'every day',
    RepeatKind.weekly => 'every week on day ${every.day}',
    RepeatKind.monthly => 'every month on the ${every.day}',
    RepeatKind.everyDays => 'every ${every.days} days',
  };

  // -------------------------------------------------------------------------
  // Making
  // -------------------------------------------------------------------------

  /// The sale path for the bill on the counter: [mark] links it to its
  /// template in the sale's own commit; with none, the ordinary sale path.
  PostSaleUseCase postSaleFor(RecurringMark? mark) => mark == null
      ? _app.postSale
      : _app._postSaleThrough(_RecurringSaleWriter(_app, mark, false));

  /// Makes [bill]'s bill for [forDate] by itself, on udhaar, at the prices
  /// it is kept at (see [recurringSaleDraft]), dated today.
  ///
  /// Asked first, as the counter asks — unless [confirmed], the cashier's
  /// "make it anyway" — a customer past their credit limit, a bounced
  /// cheque still owed, or a shelf set to warn: such a bill is held. Never
  /// throws for a bill that cannot be made; it says why.
  Future<RecurringOutcome> make(
    RecurringBill bill,
    BusinessDate forDate, {
    bool confirmed = false,
  }) async {
    _app.require(Permission.sell);
    final firmId = _firmId;
    try {
      final party = await _queries.partyById(firmId, bill.partyId);
      if (party == null) {
        throw const RecurringRefused(RecurringProblem.customerGone);
      }
      final items = <String, ItemSummary>{};
      for (final id in {for (final l in bill.lines) ?l.itemId}) {
        if (await _queries.itemById(firmId, id) case final item?) {
          items[id] = item;
        }
      }
      final firm = await _queries.currentFirm();
      final location = await _app.counterLocation();
      final draft = recurringSaleDraft(
        bill,
        items: items,
        tier: party.priceTier,
        standingBp: party.defaultDiscountBp,
        book: await _app.schemeBook(),
        units: UnitConverter(await _queries.unitConversions(firmId)),
        roundToRupee: firm?.roundInvoiceToRupee ?? true,
        partyName: party.name,
        locationCode: location,
      );

      if (!confirmed) {
        final context = await _queries.taxContextFor(firmId, party.id);
        final total = AppServices.taxCalculator.calculate(draft, context).total;
        final limit = party.creditLimit;
        final after = party.balance + total;
        final overLimit = limit != null && after > limit
            ? (limit: limit, after: after)
            : null;
        final wanted = shelfWanted(draft.lines);
        final short = [
          for (final s in shelfShortfalls(
            wanted,
            await _app.shelf.atCounter(wanted.keys, locationCode: location),
          ))
            if (s.rule == NegativeStock.warn) s,
        ];
        if (overLimit != null || party.hasUnsettledBounce || short.isNotEmpty) {
          return RecurringOutcome.held(
            bill,
            forDate,
            overLimit: overLimit,
            bounced: party.hasUnsettledBounce,
            short: short,
          );
        }
      }

      final posted = await _app._postSaleThrough(
        _RecurringSaleWriter(_app, _markOf(bill, forDate), true),
      )(_app.actorNow(), draft);
      // Waiting for FBR, when the shop reports (M19), as the counter's
      // bills do; sending is the caller's, once the batch is through.
      await _app.fbr.afterSale(posted.documentId);
      return RecurringOutcome.made(bill, forDate, posted);
    } on Object catch (refusal) {
      // The discount ceiling, a shelf set to block, an item hidden since,
      // the day already made elsewhere: said for this one bill, and the
      // next is tried. A role that may not sell at all was refused above,
      // before anything was tried.
      return RecurringOutcome.refused(bill, forDate, refusal);
    }
  }

  /// Makes each of [wanted] in turn, each its own transaction: one refused
  /// stops only itself.
  Future<List<RecurringOutcome>> makeEach(
    List<({RecurringBill bill, BusinessDate forDate})> wanted, {
    bool confirmed = false,
  }) async {
    final out = <RecurringOutcome>[];
    for (final w in wanted) {
      // Read again: the one before may have been this template's own day.
      final bill = await byId(w.bill.id) ?? w.bill;
      out.add(await make(bill, w.forDate, confirmed: confirmed));
    }
    return out;
  }

  static RecurringMark _markOf(RecurringBill bill, BusinessDate forDate) =>
      RecurringMark(
        billId: bill.id,
        forDate: forDate,
        partyId: bill.partyId,
        partyName: bill.partyName,
      );
}

/// The sale writer for a repeating bill's bill (M63): the ordinary drift
/// sale, and in the same commit the template moved on to the day it was for
/// and an audit row naming both.
///
/// Refused inside the transaction, so nothing of the bill is written, when
/// that day's bill is already made — a second phone that made it while
/// this one was apart, a double tap, a counter left open on yesterday's.
/// A bill rung for another customer than the template's is the cashier's
/// own bill and goes through unlinked.
final class _RecurringSaleWriter implements SaleWriter {
  _RecurringSaleWriter(this._app, this._mark, this._byItself);

  final AppServices _app;
  final RecurringMark _mark;
  final bool _byItself;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _app._runner.run(
    actor,
    (tx) =>
        body(_RecurringSaleContext(tx, saleContextOn(tx), _mark, _byItself)),
  );
}

final class _RecurringSaleContext implements SaleWriteContext {
  _RecurringSaleContext(this._tx, this._inner, this._mark, this._byItself);

  final Tx _tx;
  final SaleWriteContext _inner;
  final RecurringMark _mark;
  final bool _byItself;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) =>
      _inner.taxContextFor(partyId);

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) =>
      _inner.averageCostFor(itemIds);

  @override
  Future<Map<String, String>> ledgerAccountsFor(
    Iterable<String> paymentAccountIds,
  ) => _inner.ledgerAccountsFor(paymentAccountIds);

  @override
  Future<ChallanGoods?> deliveredOn(String documentId) =>
      _inner.deliveredOn(documentId);

  @override
  Future<PostedSale> apply(SalePosting posting) async {
    final id = _mark.billId;
    final held = await _tx.selectOne(
      'SELECT id, setting_value FROM settings WHERE firm_id = ? '
      'AND setting_key = ? AND deleted_at_utc IS NULL',
      [actor.firmId, recurringBillSettingKey(id)],
    );
    final template = held == null
        ? null
        : RecurringBill.fromJson(id, held.read<String>('setting_value'));
    if (template == null || posting.document.partyId != template.partyId) {
      return _inner.apply(posting);
    }
    final done = template.doneThrough;
    if (done != null && done.value.compareTo(_mark.forDate.value) >= 0) {
      final made = await _tx.selectOne(
        'SELECT d.doc_no FROM audit_log a '
        'JOIN documents d ON d.id = a.entity_id '
        'WHERE a.firm_id = ? AND a.action_code = ? '
        "  AND json_extract(a.after_json, '\$.template') = ? "
        "  AND json_extract(a.after_json, '\$.for') = ? "
        'ORDER BY a.at_utc DESC LIMIT 1',
        [actor.firmId, recurringBillMadeAction, id, _mark.forDate.value],
      );
      throw RecurringRefused(
        RecurringProblem.alreadyMade,
        docNo: made?.read<String>('doc_no'),
      );
    }

    final posted = await _inner.apply(posting);
    await _tx.update('settings', held!.read<String>('id'), {
      'setting_value': template.handledThrough(_mark.forDate).toJson(),
    });
    _tx.audit(
      action: recurringBillMadeAction,
      entityTable: 'documents',
      entityId: posted.documentId,
      summary:
          '${posted.docNo}: ${template.partyName}\'s repeating bill for '
          '${_mark.forDate.value}${_byItself ? ', made by itself' : ''}',
      amountPaisa: posted.total.inPaisa,
      after: {
        'template': id,
        'for': _mark.forDate.value,
        'auto': _byItself ? 1 : 0,
      },
    );
    return posted;
  }
}
