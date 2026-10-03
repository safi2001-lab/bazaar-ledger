part of 'app_services.dart';

/// Cashier mode: the salesman makes the bill, the cashier takes the money
/// (M68). See `cashier_mode.dart` in the domain for why a held bill is a
/// proforma and moves nothing until it is paid.
///
/// The bill made from a held bill goes down the ordinary sale path from the
/// cashier's counter, which loads it as it loads a quotation; the gate on
/// that path ([_ControlSales]) refuses a salesman's own sale, refuses paying
/// one held bill twice, and writes the salesman onto the bill.
final class CashierServices {
  CashierServices._(this._app);

  final AppServices _app;

  DriftControlReads get _reads => DriftControlReads(_app.database);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('This device has no shop yet.');
    return id.firmId;
  }

  /// Whether the shop runs that way, and who its salesmen are.
  Future<CashierMode> mode() async {
    final id = _app._identity;
    if (id == null) return CashierMode.off;
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(id.firmId),
            const Variable<String>(cashierModeSetting),
          ],
        )
        .getSingleOrNull();
    return CashierMode.fromJson(row?.read<String>('setting_value'));
  }

  /// Turns cashier mode on or off and names its salesmen. The settings
  /// permission's; the owner cannot be named one -- somebody has to be able
  /// to take the money.
  Future<void> setMode(CashierMode mode) async {
    _app.require(Permission.settings);
    final everyone = await _app.staffStore.staff(_firmId);
    for (final id in mode.salesmen) {
      final member = everyone.where((m) => m.id == id).firstOrNull;
      if (member == null) {
        throw const PermissionDenied(
          Permission.settings,
          'Only the shop\'s own staff can be its salesmen.',
        );
      }
      if (member.role == Role.owner) {
        throw const PermissionDenied(
          Permission.settings,
          'The owner takes money; the owner cannot be a salesman.',
        );
      }
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final was = CashierMode.fromJson(await _valueIn(tx, cashierModeSetting));
      if (was == mode) return;
      final id = await _keepSetting(tx, cashierModeSetting, mode.toJson());
      tx.audit(
        action: cashierModeSetAction,
        entityTable: 'settings',
        entityId: id,
        summary: mode.on
            ? 'Cashier mode on: ${mode.salesmen.length} salesman(s) make '
                  'bills, the cashier takes the money'
            : 'Cashier mode off',
        before: {'mode': was.toJson()},
        after: {'mode': mode.toJson()},
      );
    });
  }

  /// Whether whoever is signed in makes bills for the cashier.
  Future<bool> isSalesman() async =>
      (await mode()).isSalesman(_app.currentUser?.id ?? _app._identity?.userId);

  /// Sends [draft] to the cashier: written as a held bill, in its own
  /// commit, before anything on the counter is cleared. Anybody who may
  /// sell may hold a bill; a salesman can do nothing else with one.
  Future<({String id, String docNo})> hold(SaleDraft draft) {
    _app.require(Permission.sell);
    final actor = _app.actorNow();
    return DriftHeldBillWriter(runner: _app._runner).inTransaction(actor, (
      write,
    ) async {
      if (draft.lines.isEmpty) {
        throw const HeldBillRefused('A bill for the cashier needs an item.');
      }
      final calculated = AppServices.taxCalculator.calculate(
        draft,
        await write.taxContextFor(draft.partyId),
      );
      final number = await write.nextNumber(heldBillDocType);
      final posting = heldBillPosting(
        actor: actor,
        draft: draft,
        calculated: calculated,
        number: number,
      );
      return (id: await write.apply(posting), docNo: number.formatted);
    });
  }

  /// The bills waiting at the cashier, oldest first.
  Future<List<HeldBill>> queue() async {
    final id = _app._identity;
    if (id == null) return const [];
    return _reads.heldBills(id.firmId);
  }

  /// Every bill held today, paid, waiting or set aside, newest first.
  Future<List<HeldBill>> heldToday() => _reads.heldBills(
    _firmId,
    waitingOnly: false,
    day: BusinessDate.now(_app.clock),
  );

  Future<HeldBill?> held(String id) => _reads.heldBill(_firmId, id);

  /// [id]'s lines, for the cashier's counter.
  Future<List<QuotedLine>> linesOf(String id) => _reads.heldLines(_firmId, id);

  /// Takes [id] out of the queue unpaid: the customer walked away. Whoever
  /// takes money may, with a reason; Data Lock asks a PIN first, since a
  /// cashier who pockets the money and drops the bill is what this mode is
  /// there to stop.
  Future<void> drop(String id, String reason) async {
    _app.require(Permission.takePayments);
    final why = reason.trim();
    if (why.isEmpty) {
      throw const HeldBillRefused('Say why the bill is set aside.');
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final held = await _reads.heldBill(actor.firmId, id);
      if (held == null) throw const HeldBillRefused('No such bill.');
      if (held.dropped) return;
      if (held.paidAs case final no?) {
        throw HeldBillRefused('${held.docNo} is already paid as $no.');
      }
      await tx.update('documents', id, {'status': 'void', 'void_reason': why});
      tx.audit(
        action: heldBillDroppedAction,
        entityTable: 'documents',
        entityId: id,
        summary: '${held.docNo} by ${held.madeByName} set aside unpaid: $why',
        amountPaisa: held.total.inPaisa,
        after: {'reason': why},
      );
    });
  }
}
