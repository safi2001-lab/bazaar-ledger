part of 'app_services.dart';

/// Credit control and days that lock themselves (M68).
///
/// The rules are settings rows, written through the one write path with an
/// audit row each, and kept where every counter reads them: credit rules in
/// `credit.defaults` and `credit.party.<id>`, the closing rule in
/// `books.auto_lock`. No schema change.
///
/// Credit control is kept beneath every screen, by a gate on the sale path
/// ([_ControlSales]) that judges each bill inside its own transaction,
/// against the books as that transaction sees them. The counter asks
/// [CreditServices.atCounter] first so the payment sheet can say which rule
/// bites before anybody taps Save; the gate is what makes the answer true.
final class CreditServices {
  CreditServices._(this._app);

  final AppServices _app;

  DriftControlReads get _reads => DriftControlReads(_app.database);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('This device has no shop yet.');
    return id.firmId;
  }

  /// Whether whoever is signed in may change the rules: the shop's settings
  /// permission, which only the owner holds in the roles the app ships.
  bool get mayChange => _app.can(Permission.settings);

  /// The shop's own rules.
  Future<CreditDefaults> defaults() async =>
      CreditDefaults.fromJson(await _value(_firmId, creditDefaultsSetting));

  Future<void> setDefaults(CreditDefaults rules) async {
    _app.require(Permission.settings);
    _validate(maxBills: rules.maxOpenBills, maxDays: rules.maxDays);
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final was = CreditDefaults.fromJson(
        await _valueIn(tx, creditDefaultsSetting),
      );
      if (was == rules) return;
      final id = await _keepSetting(tx, creditDefaultsSetting, rules.toJson());
      tx.audit(
        action: creditDefaultsSetAction,
        entityTable: 'settings',
        entityId: id,
        summary: 'The shop\'s credit rules changed',
        before: {'rules': was.toJson()},
        after: {'rules': rules.toJson()},
      );
    });
  }

  /// [partyId]'s own rules; [PartyCreditRules.none] when they have none.
  Future<PartyCreditRules> rulesOf(String partyId) async =>
      PartyCreditRules.fromJson(
        await _value(_firmId, '$partyCreditKeyPrefix$partyId'),
      );

  /// Keeps [rules] as [partyId]'s own. A temporary limit needs its day, and
  /// that day may not have passed.
  Future<void> setRules(String partyId, PartyCreditRules rules) async {
    _app.require(Permission.settings);
    _validate(maxBills: rules.maxOpenBills, maxDays: rules.maxDays);
    final temp = rules.tempLimit;
    if ((temp == null) != (rules.tempUntil == null)) {
      throw const PermissionDenied(
        Permission.settings,
        'A temporary limit needs both an amount and the last day it stands.',
      );
    }
    if (temp != null && temp.isNegative) {
      throw const PermissionDenied(
        Permission.settings,
        'A limit cannot be less than nothing.',
      );
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final party = await tx.selectOne(
        'SELECT name FROM parties WHERE id = ? AND firm_id = ? '
        'AND deleted_at_utc IS NULL',
        [partyId, actor.firmId],
      );
      if (party == null) throw StateError('No such customer in this shop.');
      final key = '$partyCreditKeyPrefix$partyId';
      final was = PartyCreditRules.fromJson(await _valueIn(tx, key));
      if (was == rules) return;
      final id = await _keepSetting(tx, key, rules.toJson());
      final name = party.read<String>('name');
      tx.audit(
        action: partyCreditSetAction,
        entityTable: 'parties',
        entityId: partyId,
        summary: rules.tempLimit == null
            ? 'Credit rules for $name changed'
            : 'Credit rules for $name changed: Rs '
                  '${rules.tempLimit!.amountOnly} till '
                  '${rules.tempUntil!.value}',
        before: {'rules': was.toJson()},
        after: {'rules': rules.toJson(), 'setting': id},
      );
    });
  }

  /// Zoho's "raise limit and save": [partyId]'s limit taken to [limit] for
  /// today only, as a temporary limit that lapses tonight. The owner's.
  Future<void> raiseForToday(String partyId, Money limit) async {
    final own = await rulesOf(partyId);
    final today = BusinessDate.now(_app.clock);
    await setRules(
      partyId,
      PartyCreditRules(
        limitMode: own.limitMode,
        maxOpenBills: own.maxOpenBills,
        billsMode: own.billsMode,
        maxDays: own.maxDays,
        daysMode: own.daysMode,
        bounceMode: own.bounceMode,
        noBillsRule: own.noBillsRule,
        noDaysRule: own.noDaysRule,
        tempLimit: limit,
        tempUntil: today,
      ),
    );
  }

  /// The rules binding [partyId] on [today].
  Future<CreditPolicy> policyFor(String partyId, {BusinessDate? today}) =>
      _policy(_firmId, partyId, today ?? BusinessDate.now(_app.clock));

  /// What the books say about [partyId] now.
  Future<CreditStanding> standingOf(String partyId) =>
      _standing(_firmId, partyId);

  /// What the counter says before a bill for [partyId] leaving [owed] on
  /// the khata ([byCheque]: paid by a cheque). The same judgement the sale
  /// path makes beneath the screen, on the books as they stand now.
  Future<CreditVerdict> atCounter({
    required String partyId,
    required Money owed,
    bool byCheque = false,
  }) async {
    final firmId = _firmId;
    final today = BusinessDate.now(_app.clock);
    final before = await _standing(firmId, partyId);
    return judgeCredit(
      policy: await _policy(firmId, partyId, today),
      before: before,
      after: before.withBill(owed, today),
      today: today,
      givesCredit: owed.isPositive,
      byCheque: byCheque,
    );
  }

  // -------------------------------------------------------------------------

  Future<CreditPolicy> _policy(
    String firmId,
    String partyId,
    BusinessDate today,
  ) async {
    final party = await _app.queries.partyById(firmId, partyId);
    return CreditPolicy.of(
      partyLimit: party?.creditLimit,
      own: PartyCreditRules.fromJson(
        await _value(firmId, '$partyCreditKeyPrefix$partyId'),
      ),
      shop: CreditDefaults.fromJson(
        await _value(firmId, creditDefaultsSetting),
      ),
      today: today,
    );
  }

  /// Read through the database, so inside a sale's transaction it sees the
  /// bill that transaction has just written.
  Future<CreditStanding> _standing(String firmId, String partyId) async {
    final party = await _app.queries.partyById(firmId, partyId);
    final open = await _reads.openBills(firmId, partyId);
    return CreditStanding(
      balance: party?.balance ?? Money.zero,
      openBills: open.count,
      oldestOpenBill: open.oldest,
      bouncedCheques: party?.bouncedCheques ?? 0,
    );
  }

  Future<String?> _value(String firmId, String key) async {
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId), Variable<String>(key)],
        )
        .getSingleOrNull();
    return row?.read<String>('setting_value');
  }

  static void _validate({int? maxBills, int? maxDays}) {
    if (maxBills != null && (maxBills < 0 || maxBills > 999)) {
      throw const PermissionDenied(
        Permission.settings,
        'The most bills on udhaar is a number from 0 to 999.',
      );
    }
    if (maxDays != null && (maxDays < 0 || maxDays > 3650)) {
      throw const PermissionDenied(
        Permission.settings,
        'The most days a bill may wait is a number from 0 to 3650.',
      );
    }
  }
}

/// Days that lock themselves (M68): the rule, and the closing date moved on
/// to where it says.
final class AutoLockServices {
  AutoLockServices._(this._app);

  final AppServices _app;

  /// The audit code for the rule changed.
  static const setAction = 'AUTO_LOCK_SET';

  /// The owner's rule.
  Future<AutoLock> rule() async {
    final id = _app._identity;
    if (id == null) return AutoLock.off;
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(id.firmId),
            const Variable<String>(autoLockSetting),
          ],
        )
        .getSingleOrNull();
    return AutoLock.fromJson(row?.read<String>('setting_value'));
  }

  /// The last day the rule closes today, or null.
  Future<BusinessDate?> closedThroughToday() async {
    final id = _app._identity;
    if (id == null) return null;
    final rule = await this.rule();
    if (!rule.isOn) return null;
    final counted = rule.mode == AutoLockMode.atDayClose
        ? await DriftRecordHistory(_app.database).lastDayClosed(id.firmId)
        : null;
    return rule.closedThroughOn(
      BusinessDate.now(_app.clock),
      lastDayClosed: counted == null ? null : BusinessDate(counted),
    );
  }

  /// Sets the rule. The owner's alone, as closing the books is (M42). The
  /// date kept is moved on at once.
  Future<void> setRule(AutoLock rule) async {
    _app.audit._requireOwner();
    if (rule.days < 0 || rule.days > maxAutoLockDays) {
      throw const PermissionDenied(
        Permission.settings,
        'Days kept open is a number from 0 to 366.',
      );
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, autoLockSetting],
      );
      final was = AutoLock.fromJson(
        held?.readNullable<String>('setting_value'),
      );
      if (was == rule) return;
      final id = await _app.audit._setting(tx, autoLockSetting, rule.toJson());
      tx.audit(
        action: setAction,
        entityTable: 'settings',
        entityId: id,
        summary: switch (rule.mode) {
          AutoLockMode.off => 'Days no longer close by themselves',
          AutoLockMode.olderThan =>
            'Days older than ${rule.days} day(s) close by themselves',
          AutoLockMode.atDayClose =>
            'Each day closes by itself when the drawer is counted',
        },
        before: {'rule': was.toJson()},
        after: {'rule': rule.toJson()},
      );
    });
    await keep();
  }

  /// Moves the closing date kept in settings on to where the rule has
  /// reached, with a `BOOKS_CLOSED` row saying it moved by itself. Called
  /// when the app opens and when the rule is set; the write path works the
  /// date out for itself in between. Returns the date as it now stands.
  Future<BusinessDate?> keep() async {
    final id = _app._identity;
    if (id == null) return null;
    final reached = await closedThroughToday();
    if (reached == null) return null;
    final actor = ActorContext(
      firmId: id.firmId,
      userId: id.userId,
      deviceId: id.deviceId,
      startedAtUtc: _app.clock.nowUtc(),
    );
    return _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, booksClosedThroughSetting],
      );
      final kept = BusinessDate.tryParse(
        held?.readNullable<String>('setting_value') ?? '',
      );
      if (kept != null && kept.value.compareTo(reached.value) >= 0) {
        return kept;
      }
      final settingId = await _app.audit._setting(
        tx,
        booksClosedThroughSetting,
        reached.value,
      );
      tx.audit(
        action: booksClosedAction,
        entityTable: 'settings',
        entityId: settingId,
        summary: 'Books closed up to ${reached.value} by themselves',
        before: {'closed_through': kept?.value},
        after: {'closed_through': reached.value, 'by_itself': true},
      );
      return reached;
    });
  }
}

/// Keeps [value] under [key], updating the row there is. Typed JSON.
Future<String> _keepSetting(Tx tx, String key, String value) async {
  final held = await tx.selectOne(
    'SELECT id FROM settings WHERE firm_id = ? AND setting_key = ? '
    'AND deleted_at_utc IS NULL',
    [tx.actor.firmId, key],
  );
  if (held == null) {
    return tx.insert('settings', {
      'setting_key': key,
      'setting_value': value,
      'value_type': 'json',
    });
  }
  final id = held.read<String>('id');
  await tx.update('settings', id, {'setting_value': value});
  return id;
}

Future<String?> _valueIn(Tx tx, String key) async {
  final row = await tx.selectOne(
    'SELECT setting_value FROM settings WHERE firm_id = ? '
    'AND setting_key = ? AND deleted_at_utc IS NULL',
    [tx.actor.firmId, key],
  );
  return row?.read<String>('setting_value');
}

// ---------------------------------------------------------------------------
// The sale path
// ---------------------------------------------------------------------------

/// Sales: credit control and cashier mode, beneath every screen (M68).
///
/// Judged inside the bill's own transaction:
///
///  * **Cashier mode.** A salesman's bill goes to the cashier as a held
///    bill; a sale posted as a salesman is refused here, whatever screen
///    tried. A bill made from a held bill is refused once that bill is paid
///    or set aside, and carries its salesman as the bill's salesperson.
///  * **Credit control.** The customer's standing is read before the bill
///    is written and again after, inside the transaction, so the figure a
///    second till has just changed is the figure judged. A rule set to warn
///    leaves an audit row; a rule set to block refuses the udhaar unless
///    the owner's PIN and reason stand behind this run, and then leaves one
///    naming them. A bill that leaves nothing owed answers to none of it,
///    except a cheque from a customer whose last one bounced.
final class _ControlSales implements SaleWriter {
  _ControlSales(this._inner, this._app);

  final SaleWriter _inner;
  final AppServices _app;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _inner.inTransaction(actor, (w) => body(_ControlSaleContext(w, _app)));
}

final class _ControlSaleContext implements SaleWriteContext {
  _ControlSaleContext(this._inner, this._app);

  final SaleWriteContext _inner;
  final AppServices _app;

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
    final firmId = actor.firmId;
    final doc = posting.document;

    // Cashier mode: the salesman makes the bill, the cashier takes the money.
    final mode = await _app.cashier.mode();
    if (mode.isSalesman(actor.userId)) {
      throw const PermissionDenied(
        Permission.sell,
        'The shop runs in cashier mode: a salesman sends the bill to the '
        'cashier, who takes the money.',
      );
    }
    final reads = DriftControlReads(_app.database);
    String? madeBy;
    String? heldNo;
    for (final sourceId in [?posting.convertedFromId, ...posting.alsoFromIds]) {
      final held = await reads.heldBill(firmId, sourceId);
      if (held == null) continue;
      if (held.dropped) {
        throw HeldBillRefused(
          '${held.docNo} was set aside and cannot be paid now.',
        );
      }
      if (held.paidAs case final no?) {
        throw HeldBillRefused('${held.docNo} is already paid as $no.');
      }
      madeBy = held.madeBy;
      heldNo = held.docNo;
    }

    final partyId = doc.partyId;
    final before = partyId == null
        ? null
        : await _app.credit._standing(firmId, partyId);

    final posted = await _inner.apply(posting);
    final tx = Tx.current;
    if (tx == null) {
      throw StateError('A bill is only ever written inside a transaction.');
    }

    if (heldNo != null && madeBy != null) {
      // Who made it, on the bill itself; who took the money is its writer.
      if (madeBy != actor.userId) {
        await tx.update('documents', posted.documentId, {
          'salesperson_id': madeBy,
        });
      }
      tx.audit(
        action: 'HELD_BILL_PAID',
        entityTable: 'documents',
        entityId: posted.documentId,
        summary: '${doc.docNo} paid for $heldNo',
        amountPaisa: doc.total.inPaisa,
        after: {'held': heldNo, 'made_by': madeBy},
      );
    }

    if (partyId != null && before != null) {
      final byCheque = posting.payments.any((p) => p.isCheque);
      final givesCredit = posted.balance.isPositive;
      if (givesCredit || byCheque) {
        final today = actor.businessDate;
        final verdict = judgeCredit(
          policy: await _app.credit._policy(firmId, partyId, today),
          before: before,
          after: await _app.credit._standing(firmId, partyId),
          today: today,
          givesCredit: givesCredit,
          byCheque: byCheque,
        );
        final who = doc.partyNameSnapshot ?? 'the customer';
        if (verdict.blocks) {
          final blocking = verdict.blocking;
          final given = tx.approvedFor(
            ApprovalNeeded.owner(
              what: '${doc.docNo} for $who: ${verdict.words(blocking)}',
              actorUserId: actor.userId,
              detail: verdict,
            ),
          );
          tx.audit(
            action: creditOverrideAction,
            entityTable: 'documents',
            entityId: posted.documentId,
            summary:
                '${doc.docNo} for $who let past ${verdict.words(blocking)} '
                'by ${given.userName}: ${given.reason ?? ''}',
            amountPaisa: posted.balance.inPaisa,
            after: {
              'rules': [for (final b in blocking) b.rule.name],
              'reason': given.reason,
              'approved_by': given.userId,
              'approved_by_name': given.userName,
            },
          );
        } else if (!verdict.isClear) {
          tx.audit(
            action: creditWarningPassedAction,
            entityTable: 'documents',
            entityId: posted.documentId,
            summary:
                '${doc.docNo} for $who given past a warning: '
                '${verdict.words()}',
            amountPaisa: posted.balance.inPaisa,
            after: {
              'rules': [for (final b in verdict.breaches) b.rule.name],
            },
          );
        }
      }
    }
    return posted;
  }
}
