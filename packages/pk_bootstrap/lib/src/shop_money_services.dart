part of 'app_services.dart';

/// The shop's money and the home's kept apart, other income in the books,
/// and the monthly bills remembered (M47).
///
/// ## Who may do what
///
/// Recording the shop's spending and its other income takes the expense
/// book's permission: the owner, a manager, the accountant. Putting either
/// right takes M31's: the owner, a manager, the accountant — never a
/// cashier.
///
/// The home's spending — ghar ka kharcha, in money or in goods off the
/// shelf — is the owner's drawings, and takes the journal permission as
/// well: the owner and the accountant. Not a manager, and never a cashier.
/// It is the owner's own money leaving the business, and the accountant
/// already holds the power to post exactly this by hand as a journal
/// voucher, so the rule adds no power to anybody and takes none from the
/// people who keep the books. It is checked below every screen — on the
/// expense writer, on the correction path, and on the monthly bills — so
/// a manager cannot post one, edit an expense into one, or cancel one.
///
/// Changing the heads changes the chart, so it takes the journal
/// permission, as adding an account in M26 does.
final class ShopMoneyServices {
  ShopMoneyServices._(this._app);

  final AppServices _app;

  DriftShopMoneyReads get _reads => DriftShopMoneyReads(_app.database);
  DriftShopMoneyWriter get _writer =>
      DriftShopMoneyWriter(runner: _app._runner);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('No shop is set up on this phone yet.');
    return id.firmId;
  }

  BusinessDate get _today => BusinessDate.now(_app.clock);

  // -------------------------------------------------------------------------
  // The home's spending
  // -------------------------------------------------------------------------

  /// Whether whoever is signed in may enter ghar ka kharcha.
  bool get canSpendForHome =>
      _app.can(Permission.expenses) && _app.can(Permission.journal);

  /// Throws unless whoever is signed in may enter or correct the home's
  /// spending.
  void requireHome() {
    _app.require(Permission.expenses);
    _app._requireHome();
  }

  /// Takes goods off the shelf for the home, at what they cost.
  Future<RecordedExpense> takeGoodsHome(GoodsTakenHomeDraft draft) async {
    requireHome();
    return _writer.takeGoodsHome(_app.actorNow(), draft);
  }

  // -------------------------------------------------------------------------
  // The expense book
  // -------------------------------------------------------------------------

  /// Standing expenses, the shop's and the home's, newest first.
  Future<List<ExpenseBookRow>> expenseBook() async {
    _app.require(Permission.expenses);
    return _reads.expenseBook(_firmId);
  }

  /// Whose money one expense was, its head and the bill it paid.
  Future<ExpenseFacts?> expenseFacts(String documentId) async {
    _app.require(Permission.expenses);
    return _reads.expenseFacts(_firmId, documentId);
  }

  /// This month's spending, the shop's and the home's apart.
  Future<MonthSplit> thisMonth() async {
    _app.require(Permission.expenses);
    final (from, to) = monthSpan(_today);
    return _reads.monthSplit(_firmId, from, to);
  }

  /// Records an expense, and when [remindOnDay] is given keeps it as a
  /// monthly bill due on that day, this month's counted as paid by it.
  ///
  /// The expense goes first and the reminder after it, two writes: a
  /// reminder that failed to save leaves an expense that stands on its own,
  /// where the other order could leave a reminder for money never paid.
  Future<RecordedExpense> recordExpense(
    ExpenseDraft draft, {
    int? remindOnDay,
  }) async {
    final billId = remindOnDay == null ? null : _app.ids.next();
    final tagged = billId == null
        ? draft
        : ExpenseDraft(
            accountSystemKey: draft.accountSystemKey,
            amount: draft.amount,
            note: draft.note,
            paymentAccountId: draft.paymentAccountId,
            partyId: draft.partyId,
            forHome: draft.forHome,
            tag: recurringTag(billId),
          );
    if (billId != null) {
      // Checked before the money is written, so a refused reminder never
      // leaves an expense half of an act behind it.
      checkMonthlyBill(_billFrom(billId, tagged, remindOnDay!));
    }
    final recorded = await _app.recordExpense(_app.actorNow(), tagged);
    if (billId != null) {
      await _writer.saveMonthlyBill(
        _app.actorNow(),
        _billFrom(billId, tagged, remindOnDay!),
      );
    }
    return recorded;
  }

  static MonthlyBill _billFrom(String id, ExpenseDraft draft, int day) =>
      MonthlyBill(
        id: id,
        headKey: draft.forHome ? ownerDrawingsKey : draft.accountSystemKey,
        amount: draft.amount,
        note: draft.note.trim(),
        day: day,
        forHome: draft.forHome,
        paymentAccountId: draft.paymentAccountId,
      );

  // -------------------------------------------------------------------------
  // Heads
  // -------------------------------------------------------------------------

  /// Every head of expense, hidden ones included.
  Future<List<ExpenseHead>> expenseHeads() async {
    _app.require(Permission.expenses);
    return _reads.shopExpenseHeads(_firmId);
  }

  /// Adds a head of expense of the shop's own. Returns its account id.
  Future<String> addExpenseHead({
    required String name,
    required bool isDirect,
  }) async {
    _app.require(Permission.journal);
    return _writer.addExpenseHead(
      _app.actorNow(),
      name: name,
      isDirect: isDirect,
    );
  }

  Future<void> renameExpenseHead(String accountId, String name) async {
    _app.require(Permission.journal);
    return _writer.renameExpenseHead(
      _app.actorNow(),
      accountId: accountId,
      name: name,
    );
  }

  Future<void> setExpenseHeadDirect(String accountId, bool isDirect) async {
    _app.require(Permission.journal);
    return _writer.setExpenseHeadDirect(
      _app.actorNow(),
      accountId: accountId,
      isDirect: isDirect,
    );
  }

  Future<void> setExpenseHeadHidden(String accountId, bool hidden) async {
    _app.require(Permission.journal);
    return _writer.setExpenseHeadHidden(
      _app.actorNow(),
      accountId: accountId,
      hidden: hidden,
    );
  }

  /// Every head of other income, hidden ones included.
  Future<List<IncomeHead>> incomeHeads() async {
    _app.require(Permission.expenses);
    return _reads.incomeHeads(_firmId);
  }

  /// Adds a head of other income of the shop's own. Returns its key.
  Future<String> addIncomeHead(String name) async {
    _app.require(Permission.journal);
    final key = 'own_${_app.ids.next().toLowerCase()}';
    await _writer.addIncomeHead(_app.actorNow(), key: key, name: name);
    return key;
  }

  Future<void> renameIncomeHead(String key, String name) async {
    _app.require(Permission.journal);
    return _writer.renameIncomeHead(_app.actorNow(), key: key, name: name);
  }

  Future<void> setIncomeHeadHidden(String key, bool hidden) async {
    _app.require(Permission.journal);
    return _writer.setIncomeHeadHidden(
      _app.actorNow(),
      key: key,
      hidden: hidden,
    );
  }

  // -------------------------------------------------------------------------
  // Other income
  // -------------------------------------------------------------------------

  OtherIncomeUseCase get _income =>
      OtherIncomeUseCase(writer: DriftOtherIncomeWriter(runner: _app._runner));

  /// Records money the shop earned that is not a sale.
  Future<RecordedOtherIncome> recordOtherIncome(OtherIncomeDraft draft) async {
    _app.require(Permission.expenses);
    return _income.record(_app.actorNow(), draft);
  }

  /// Cancels an entry of other income, saying why (M31's permission).
  Future<VoidedDocument> cancelOtherIncome({
    required String documentId,
    required String reason,
  }) async {
    _app.require(Permission.correctEntries);
    return _income.cancel(
      _app.actorNow(),
      documentId: documentId,
      reason: reason,
    );
  }

  /// Replaces an entry of other income with [draft], as one act.
  Future<CorrectedEntry> editOtherIncome({
    required String documentId,
    required OtherIncomeDraft draft,
    required String reason,
  }) async {
    _app.require(Permission.correctEntries);
    return _income.edit(
      _app.actorNow(),
      documentId: documentId,
      draft: draft,
      reason: reason,
    );
  }

  /// The shop's standing other income, newest first.
  Future<List<OtherIncomeRow>> otherIncomes() async {
    _app.require(Permission.expenses);
    return _reads.otherIncomes(_firmId);
  }

  /// This month's other income, by head.
  Future<Map<String, Money>> incomeThisMonth() async {
    _app.require(Permission.expenses);
    final (from, to) = monthSpan(_today);
    return _reads.incomeByHead(_firmId, from, to);
  }

  /// One entry of other income, standing or cancelled.
  Future<OtherIncomeDetail?> otherIncome(String documentId) async {
    _app.require(Permission.expenses);
    return _reads.otherIncome(_firmId, documentId);
  }

  // -------------------------------------------------------------------------
  // Monthly bills
  // -------------------------------------------------------------------------

  /// A fresh id for a new monthly bill.
  String newMonthlyBillId() => _app.ids.next();

  /// Every monthly bill, by its day.
  Future<List<MonthlyBill>> monthlyBills() async {
    _app.require(Permission.expenses);
    return _reads.monthlyBills(_firmId);
  }

  /// The bills whose day has come this month and which are not paid. The
  /// home's are left out for a role that may not pay them.
  Future<List<DueBill>> billsDueNow() async {
    _app.require(Permission.expenses);
    final today = _today;
    final (from, to) = monthSpan(today);
    final bills = await _reads.monthlyBills(_firmId);
    return billsDue(
      bills: [
        for (final b in bills)
          if (!b.forHome || canSpendForHome) b,
      ],
      paidTags: await _reads.paidTags(_firmId, from, to),
      today: today,
    );
  }

  /// Keeps [bill], new or changed. A bill for the home's spending is the
  /// owner's or the accountant's to keep.
  Future<void> saveMonthlyBill(MonthlyBill bill) async {
    _app.require(Permission.expenses);
    if (bill.forHome) _app._requireHome();
    return _writer.saveMonthlyBill(_app.actorNow(), bill);
  }

  /// Stops reminding about [bill].
  Future<void> removeMonthlyBill(MonthlyBill bill) async {
    _app.require(Permission.expenses);
    if (bill.forHome) _app._requireHome();
    return _writer.removeMonthlyBill(_app.actorNow(), bill.id);
  }

  /// Does not remind about [bill] again this month.
  Future<void> skipThisMonth(MonthlyBill bill) async {
    _app.require(Permission.expenses);
    if (bill.forHome) _app._requireHome();
    return _writer.skipMonthlyBill(
      _app.actorNow(),
      id: bill.id,
      month: monthOf(_today),
    );
  }
}

// ---------------------------------------------------------------------------
// The home's spending, checked below every screen
// ---------------------------------------------------------------------------

extension _HomeRule on AppServices {
  /// Throws unless whoever is signed in may post the owner's drawings: the
  /// owner or the accountant, who hold the journal permission.
  void _requireHome() {
    if (_locked) {
      throw const PermissionDenied(Permission.journal, 'Sign in first.');
    }
    if (!can(Permission.journal)) {
      throw PermissionDenied(
        Permission.journal,
        "Ghar ka kharcha is the owner's own money leaving the shop, so only "
        'the owner or the accountant enters or changes it. '
        '${_signedIn?.name ?? 'This user'} is signed in as '
        '${_signedIn?.role.name ?? 'staff'}.',
      );
    }
  }
}

/// The expense writer, refusing the home's spending to a role that may not
/// post the owner's drawings.
final class _HomeGatedExpenses implements ExpenseWriter {
  _HomeGatedExpenses(this._inner, this._app);

  final ExpenseWriter _inner;
  final AppServices _app;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ExpenseWriteContext write) body,
  ) => _inner.inTransaction(
    actor,
    (w) => body(_HomeGatedExpenseContext(w, _app)),
  );
}

final class _HomeGatedExpenseContext implements ExpenseWriteContext {
  _HomeGatedExpenseContext(this._inner, this._app);

  final ExpenseWriteContext _inner;
  final AppServices _app;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<String?> ledgerAccountFor(String paymentAccountId) =>
      _inner.ledgerAccountFor(paymentAccountId);

  @override
  Future<RecordedExpense> apply(ExpensePosting posting) {
    if (posting.forHome) _app._requireHome();
    return _inner.apply(posting);
  }
}

/// The correction path, refusing to cancel or to write the home's spending
/// for a role that may not post the owner's drawings.
///
/// Which account is Owner's Drawings is read before the transaction opens:
/// a read through the database while the transaction is open would wait
/// for the transaction it is inside, for ever.
final class _HomeGatedCorrections implements CorrectionWriter {
  _HomeGatedCorrections(this._inner, this._app);

  final CorrectionWriter _inner;
  final AppServices _app;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(CorrectionWriteContext write) body,
  ) async {
    final drawings = await _app.database
        .customSelect(
          'SELECT id FROM accounts WHERE firm_id = ? AND system_key = ? '
          '  AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(actor.firmId),
            Variable<String>(ownerDrawingsKey),
          ],
        )
        .getSingleOrNull();
    final drawingsId = drawings?.read<String>('id');
    return _inner.inTransaction(
      actor,
      (w) => body(_HomeGatedCorrectionContext(w, _app, drawingsId)),
    );
  }
}

final class _HomeGatedCorrectionContext implements CorrectionWriteContext {
  _HomeGatedCorrectionContext(this._inner, this._app, this._drawingsId);

  final CorrectionWriteContext _inner;
  final AppServices _app;
  final String? _drawingsId;

  @override
  ActorContext get actor => _inner.actor;

  @override
  VoidWriteContext get documents =>
      _HomeGatedVoid(_inner.documents, _app, _drawingsId);

  @override
  PaymentWriteContext get payments => _inner.payments;

  @override
  ExpenseWriteContext get expenses =>
      _HomeGatedExpenseContext(_inner.expenses, _app);

  @override
  DebitNoteWriteContext get charges => _inner.charges;

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<PostedPaymentSnapshot?> paymentSnapshot(String paymentId) =>
      _inner.paymentSnapshot(paymentId);

  @override
  Future<VoidedPayment> applyPaymentVoid(PaymentVoidPosting posting) =>
      _inner.applyPaymentVoid(posting);

  @override
  Future<OpeningSnapshot?> openingOf(String partyId) =>
      _inner.openingOf(partyId);

  @override
  Future<void> applyOpeningCorrection(OpeningCorrectionPosting posting) =>
      _inner.applyOpeningCorrection(posting);

  @override
  void recordCorrection(CorrectionRecord record) =>
      _inner.recordCorrection(record);
}

final class _HomeGatedVoid implements VoidWriteContext {
  _HomeGatedVoid(this._inner, this._app, this._drawingsId);

  final VoidWriteContext _inner;
  final AppServices _app;
  final String? _drawingsId;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<PostedDocumentSnapshot?> snapshotOf(String documentId) async {
    final snapshot = await _inner.snapshotOf(documentId);
    final drawings = _drawingsId;
    if (snapshot != null &&
        drawings != null &&
        snapshot.entry.lines.any((l) => l.accountSystemKey == '#$drawings')) {
      _app._requireHome();
    }
    return snapshot;
  }

  @override
  Future<VoidedDocument> apply(VoidPosting posting) => _inner.apply(posting);
}
