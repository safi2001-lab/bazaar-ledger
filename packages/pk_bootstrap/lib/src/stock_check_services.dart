part of 'app_services.dart';

/// The random stock check (M68): a few items named each day, counted by
/// whoever is at the counter, and the differences put into the books on the
/// owner's word. See `stock_check.dart` in the domain for the pick and why
/// counting writes nothing to the books.
///
/// Each check is one settings row (`stockcheck.check.<id>`), written through
/// the one write path with an audit row at every step, so a count half
/// done survives the app being killed and reaches the other counters.
final class StockCheckServices {
  StockCheckServices._(this._app);

  final AppServices _app;

  DriftControlReads get _reads => DriftControlReads(_app.database);

  /// Whether whoever is signed in may count: anybody at the counter.
  bool get mayCount =>
      _app.can(Permission.sell) || _app.can(Permission.purchases);

  /// Whether whoever is signed in sees what a difference is worth.
  bool get seesValue => _app.can(Permission.seeCosts);

  /// The shop's rule.
  Future<StockCheckRule> rule() async {
    final id = _app._identity;
    if (id == null) return StockCheckRule.standard;
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(id.firmId),
            const Variable<String>(stockCheckSettingsKey),
          ],
        )
        .getSingleOrNull();
    return StockCheckRule.fromJson(row?.read<String>('setting_value'));
  }

  Future<void> setRule(StockCheckRule rule) async {
    _app.require(Permission.settings);
    if (rule.size < 1 || rule.size > maxStockCheckSize) {
      throw const PermissionDenied(
        Permission.settings,
        'A check names from 1 to 50 items.',
      );
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final was = StockCheckRule.fromJson(
        await _valueIn(tx, stockCheckSettingsKey),
      );
      if (was == rule) return;
      final id = await _keepSetting(tx, stockCheckSettingsKey, rule.toJson());
      tx.audit(
        action: 'STOCK_CHECK_RULE_SET',
        entityTable: 'settings',
        entityId: id,
        summary: rule.daily
            ? 'A random check of ${rule.size} items each day'
            : 'A random check of ${rule.size} items when asked',
        before: {'rule': was.toJson()},
        after: {'rule': rule.toJson()},
      );
    });
  }

  /// Every check kept, newest first.
  Future<List<StockCheck>> history() async {
    final id = _app._identity;
    if (id == null) return const [];
    final out = [
      for (final raw in await _reads.settingsUnder(
        id.firmId,
        stockCheckKeyPrefix,
      ))
        ?StockCheck.fromJson(raw),
    ];
    out.sort((a, b) {
      final byDate = b.date.value.compareTo(a.date.value);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return out;
  }

  /// Today's check still to finish, or null. With the shop's rule set to
  /// daily and no check yet today, one is picked now.
  Future<StockCheck?> today() async {
    final id = _app._identity;
    if (id == null) return null;
    final day = BusinessDate.now(_app.clock);
    final all = await history();
    final open = all.where((c) => c.isOpen).firstOrNull;
    if (open != null) return open;
    final rule = await this.rule();
    if (rule.daily && mayCount && !all.any((c) => c.date.value == day.value)) {
      return pick();
    }
    return null;
  }

  /// Picks a check now: [StockCheckRule.size] items, weighted to fast
  /// movers and dear stock, none named on yesterday's check or an earlier
  /// one today.
  Future<StockCheck> pick() async {
    if (!mayCount) {
      throw const PermissionDenied(
        Permission.sell,
        'Counting the shelf is for whoever works the counter.',
      );
    }
    final rule = await this.rule();
    final location = await _app.counterLocation();
    final actor = _app.actorNow();
    final day = actor.businessDate;
    final firmId = actor.firmId;
    final all = await history();
    final recent = [
      for (final c in all)
        if (c.date.value == day.value || c.date.value == day.addDays(-1).value)
          c,
    ];
    final exclude = {
      for (final c in recent)
        for (final l in c.lines) l.itemId,
    };
    final turn = all.where((c) => c.date.value == day.value).length;
    final picked = pickForCheck(
      candidates: await _reads.stockCheckCandidates(
        firmId,
        location: location,
        today: day,
      ),
      exclude: exclude,
      size: rule.size,
      seed: stockCheckSeed(firmId, day, turn),
    );
    if (picked.isEmpty) {
      throw const PermissionDenied(
        Permission.sell,
        'There is nothing on the shelf to count that was not counted '
        'yesterday.',
      );
    }
    final check = StockCheck(
      id: _app.ids.next(),
      date: day,
      location: location,
      pickedBy: actor.userId,
      lines: [
        for (final c in picked)
          StockCheckLine(itemId: c.itemId, name: c.name, unitCode: c.unitCode),
      ],
    );
    await _app._runner.run(actor, (tx) async {
      final settingId = await _keepSetting(
        tx,
        '$stockCheckKeyPrefix${check.id}',
        check.toJson(),
      );
      tx.audit(
        action: stockCheckPickedAction,
        entityTable: 'settings',
        entityId: settingId,
        summary:
            'Random check of ${day.value}: '
            '${[for (final l in check.lines) l.name].join(', ')}',
      );
    });
    return check;
  }

  /// Keeps what was on the shelf of [itemId] for check [checkId], against
  /// what the books say at this moment -- read in the same transaction, so
  /// a sale rung a second before is in both.
  Future<StockCheck> count(String checkId, String itemId, Qty shelf) async {
    if (!mayCount) {
      throw const PermissionDenied(
        Permission.sell,
        'Counting the shelf is for whoever works the counter.',
      );
    }
    if (shelf.isNegative) {
      throw const PermissionDenied(
        Permission.sell,
        'A shelf cannot hold less than nothing.',
      );
    }
    final actor = _app.actorNow();
    return _app._runner.run(actor, (tx) async {
      final (settingId, check) = await _checkIn(tx, checkId);
      if (!check.isOpen) {
        throw const PermissionDenied(Permission.sell, 'That check is closed.');
      }
      final books = (await _reads.onHand(actor.firmId, [
        itemId,
      ], location: check.location))[itemId]!;
      var found = false;
      final lines = [
        for (final l in check.lines)
          if (l.itemId == itemId)
            () {
              found = true;
              return l.countedAs(shelf, books: books, by: actor.userId);
            }()
          else
            l,
      ];
      if (!found) throw StateError('That item is not on this check.');
      final next = check.copyWith(
        lines: lines,
        status: lines.every((l) => l.isCounted)
            ? StockCheckStatus.counted
            : StockCheckStatus.open,
      );
      await tx.update('settings', settingId, {'setting_value': next.toJson()});
      final line = lines.firstWhere((l) => l.itemId == itemId);
      tx.audit(
        action: stockCheckCountedAction,
        entityTable: 'settings',
        entityId: settingId,
        summary:
            '${line.name}: ${shelf.display} on the shelf, the books said '
            '${books.display}',
      );
      return next;
    });
  }

  /// Puts check [checkId]'s differences into the books: each item's shelf
  /// moved by what the count found, as a stock adjustment with the reason
  /// "Random check", through the one stock-correction path (M1), all in one
  /// commit with the check marked posted.
  ///
  /// The owner's word: signed in as the owner, it is theirs; anybody else
  /// is asked for the owner's PIN and a reason, beneath the screen.
  Future<StockCheck> post(String checkId) async {
    if (!mayCount) {
      throw const PermissionDenied(
        Permission.sell,
        'Counting the shelf is for whoever works the counter.',
      );
    }
    final actor = _app.actorNow();
    final byOwner = _app.audit.isOwner;
    return _app._runner.run(actor, (tx) async {
      final (settingId, check) = await _checkIn(tx, checkId);
      if (check.status == StockCheckStatus.posted) return check;
      if (!check.isOpen || !check.allCounted) {
        throw const PermissionDenied(
          Permission.sell,
          'Every item on the check has to be counted first.',
        );
      }
      final differing = check.differing;
      Approval? given;
      if (!byOwner) {
        given = tx.approvedFor(
          ApprovalNeeded.owner(
            what:
                'Random check of ${check.date.value}: '
                '${differing.length} item(s) differ from the books',
            actorUserId: actor.userId,
            detail: check,
          ),
        );
      }
      final lines = <StockCheckLine>[];
      for (final l in check.lines) {
        final diff = l.difference!;
        if (diff.isZero) {
          lines.add(l);
          continue;
        }
        final now = (await _reads.onHand(actor.firmId, [
          l.itemId,
        ], location: check.location))[l.itemId]!;
        final ledgerId = await adjustStockOn(
          tx,
          StockAdjustmentDraft.counted(
            itemId: l.itemId,
            counted: Qty.raw(now.inThousandths + diff.inThousandths),
            reason: stockCheckReason,
            locationCode: check.location,
          ),
        );
        final row = await tx.selectOne(
          'SELECT qty_delta_thousandths, value_delta_paisa FROM stock_ledger '
          'WHERE id = ?',
          [ledgerId],
        );
        lines.add(
          l.postedAs(
            Qty.raw(row!.read<int>('qty_delta_thousandths')),
            Money.paisa(row.read<int>('value_delta_paisa')),
          ),
        );
      }
      final me = _app.currentUser;
      final posted = check.copyWith(
        lines: lines,
        status: StockCheckStatus.posted,
        postedOn: actor.businessDate,
        approvedBy: given?.userId ?? actor.userId,
        approvedByName: given?.userName ?? me?.name,
        note: given?.reason,
      );
      await tx.update('settings', settingId, {
        'setting_value': posted.toJson(),
      });
      tx.audit(
        action: stockCheckPostedAction,
        entityTable: 'settings',
        entityId: settingId,
        summary:
            'Random check of ${check.date.value} posted: '
            '${differing.length} item(s) differed, Rs '
            '${posted.shortValue.amountOnly} short, Rs '
            '${posted.overValue.amountOnly} over'
            '${given == null ? '' : ', approved by ${given.userName}: '
                      '${given.reason ?? ''}'}',
        amountPaisa: (posted.overValue - posted.shortValue).inPaisa,
        after: {
          'short_paisa': posted.shortValue.inPaisa,
          'over_paisa': posted.overValue.inPaisa,
          'approved_by': ?given?.userId,
          'approved_by_name': ?given?.userName,
          'reason': ?given?.reason,
        },
      );
      return posted;
    });
  }

  /// Sets check [checkId] aside without posting anything. Data Lock asks a
  /// PIN first: a check set aside is what it found, unsaid.
  Future<void> drop(String checkId, String reason) async {
    if (!mayCount) {
      throw const PermissionDenied(
        Permission.sell,
        'Counting the shelf is for whoever works the counter.',
      );
    }
    final why = reason.trim();
    if (why.isEmpty) {
      throw const PermissionDenied(
        Permission.sell,
        'Say why the check is set aside.',
      );
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final (settingId, check) = await _checkIn(tx, checkId);
      if (!check.isOpen) return;
      await tx.update('settings', settingId, {
        'setting_value': check
            .copyWith(status: StockCheckStatus.dropped, note: why)
            .toJson(),
      });
      tx.audit(
        action: stockCheckDroppedAction,
        entityTable: 'settings',
        entityId: settingId,
        summary: 'Random check of ${check.date.value} set aside: $why',
      );
    });
  }

  /// What each difference [check] found is worth at the item's average
  /// cost now, negative for what is missing: what the owner approves. For
  /// whoever may see costs only.
  Future<Map<String, Money>> differenceValues(StockCheck check) async {
    _app.require(Permission.seeCosts);
    final id = _app._identity;
    if (id == null) return const {};
    final differing = check.differing;
    final costs = await _reads.averageCosts(id.firmId, [
      for (final l in differing) l.itemId,
    ]);
    return {
      for (final l in differing)
        l.itemId: () {
          final diff = l.difference!;
          final value = (costs[l.itemId] ?? Rate.zero).amountFor(
            Qty.raw(diff.inThousandths.abs()),
          );
          return diff.isNegative ? -value : value;
        }(),
    };
  }

  /// What the posted checks found, month by month, newest first.
  Future<List<Shrinkage>> shrinkage() async =>
      shrinkageByMonth(await history());

  Future<(String, StockCheck)> _checkIn(Tx tx, String checkId) async {
    final row = await tx.selectOne(
      'SELECT id, setting_value FROM settings WHERE firm_id = ? '
      'AND setting_key = ? AND deleted_at_utc IS NULL',
      [tx.actor.firmId, '$stockCheckKeyPrefix$checkId'],
    );
    final check = StockCheck.fromJson(row?.read<String>('setting_value'));
    if (row == null || check == null) {
      throw StateError('No such stock check.');
    }
    return (row.read<String>('id'), check);
  }
}
