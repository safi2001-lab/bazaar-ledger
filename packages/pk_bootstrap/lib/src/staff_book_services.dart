part of 'app_services.dart';

/// The staff book (M65): the shop's people, the day's register, advances
/// against wages, and each month's salary slip.
///
/// ## Who may do what
///
/// Decided, and checked here rather than by hiding buttons:
///
/// * The owner and the manager **keep** the staff book
///   ([Permission.keepStaff]): they add people, set what each is paid, mark
///   who has left, and put a man in the recycle bin.
/// * The owner, the manager and the accountant **pay** ([Permission.payStaff]):
///   they see what each man is paid, give advances and pay a month's wages,
///   cancel or correct either, and read the staff book's reports. The
///   accountant pays wages as he pays every other bill, without being the
///   one who hires.
/// * What anybody is paid is seen by those three and by nobody else.
/// * The register is marked by any of them, and by a cashier only when the
///   owner has switched that on in the staff book's rules; the cashier then
///   sees the register's names and marks, never a rupee.
/// * The rules themselves — how a day of a monthly salary is reckoned, and
///   whether a cashier may mark the register — are the owner's, as every
///   setting of the shop is ([Permission.settings]).
///
/// Every plan has the staff book. A khata app that charged for the boy's
/// attendance register would be charging for the one page DigiKhata gives
/// away.
final class StaffBookServices {
  StaffBookServices._(this._app);

  final AppServices _app;

  DriftStaffBookReads get _reads => DriftStaffBookReads(_app.database);
  DriftStaffBookWriter get _writer =>
      DriftStaffBookWriter(runner: _app._runner);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('This device has no shop yet.');
    return id.firmId;
  }

  BusinessDate get _today => BusinessDate.now(_app.clock);

  /// Whether whoever is signed in keeps the staff book.
  bool get mayKeep => _app.can(Permission.keepStaff);

  /// Whether whoever is signed in sees and pays wages.
  bool get mayPay => _app.can(Permission.payStaff);

  /// Whether whoever is signed in sets the staff book's rules.
  bool get maySetRules => _app.can(Permission.settings);

  void _requireKeep() {
    if (mayKeep) return;
    throw PermissionDenied(
      Permission.keepStaff,
      _app.isLocked
          ? 'Sign in first.'
          : 'Only the owner or a manager adds staff and sets their pay.',
    );
  }

  void _requirePay() {
    if (mayPay) return;
    throw PermissionDenied(
      Permission.payStaff,
      _app.isLocked
          ? 'Sign in first.'
          : 'Only the owner, a manager or the accountant sees and pays '
                'wages.',
    );
  }

  /// Whether whoever is signed in may mark the register: anybody who keeps
  /// or pays the staff, and a cashier when the owner allows it.
  Future<bool> mayMarkRegister() async {
    if (_app.isLocked || _app._identity == null) return false;
    if (mayKeep || mayPay) return true;
    return (await rules()).cashierMarksAttendance;
  }

  Future<void> _requireRegister() async {
    if (await mayMarkRegister()) return;
    throw PermissionDenied(
      Permission.payStaff,
      _app.isLocked
          ? 'Sign in first.'
          : 'The owner has not let the counter mark the staff register.',
    );
  }

  // ---------------------------------------------------------------------
  // The rules
  // ---------------------------------------------------------------------

  Future<StaffRules> rules() async {
    if (_app._identity == null) return const StaffRules();
    return _reads.rules(_firmId);
  }

  Future<void> setRules(StaffRules rules) async {
    _app.require(Permission.settings);
    await _writer.setRules(_app.actorNow(), rules);
  }

  // ---------------------------------------------------------------------
  // The people
  // ---------------------------------------------------------------------

  /// Everybody on the books, still working first; or those in the recycle
  /// bin when [hidden].
  Future<List<Employee>> employees({bool hidden = false}) async {
    _requirePay();
    return _reads.employees(_firmId, hidden: hidden);
  }

  /// The people in the recycle bin, for whoever may bring them back; none
  /// for anybody else, so the bin is never a way round this permission.
  Future<List<Employee>> hiddenEmployees() async {
    if (!mayKeep || _app._identity == null) return const [];
    return _reads.employees(_firmId, hidden: true);
  }

  Future<Employee?> employee(String employeeId) async {
    _requirePay();
    return _reads.employee(_firmId, employeeId);
  }

  /// The shop's sign-ins, to link a man to his own (M9).
  Future<List<StaffMember>> signIns() async {
    _requireKeep();
    return _app.staffStore.staff(_firmId);
  }

  Future<String> add(EmployeeDraft draft) async {
    _requireKeep();
    return _writer.addEmployee(_app.actorNow(), draft);
  }

  Future<void> edit(String employeeId, EmployeeDraft draft) async {
    _requireKeep();
    await _writer.editEmployee(_app.actorNow(), employeeId, draft);
  }

  /// Puts him in the recycle bin. Refused while he owes an advance.
  Future<void> hide(String employeeId) async {
    _requireKeep();
    await _writer.setHidden(_app.actorNow(), employeeId, hidden: true);
  }

  Future<void> restore(String employeeId) async {
    _requireKeep();
    await _writer.setHidden(_app.actorNow(), employeeId, hidden: false);
  }

  // ---------------------------------------------------------------------
  // The register
  // ---------------------------------------------------------------------

  /// [day]'s register: everybody on the payroll that day, with his mark.
  Future<List<RegisterLine>> register(BusinessDate day) async {
    await _requireRegister();
    return _reads.register(_firmId, day);
  }

  /// Marks [day] for each man in [marks], in one act.
  Future<void> mark(BusinessDate day, Map<String, AttendanceMark> marks) async {
    await _requireRegister();
    await _writer.mark(_app.actorNow(), day, marks);
  }

  /// Every man on [day]'s register nobody has marked yet, marked present.
  /// Returns how many were marked.
  Future<int> markRestPresent(BusinessDate day) async {
    final open = [
      for (final line in await register(day))
        if (line.mark == null) line.employee.id,
    ];
    if (open.isEmpty) return 0;
    await mark(day, {for (final id in open) id: AttendanceMark.present});
    return open.length;
  }

  /// [employeeId]'s marks in [month], by day.
  Future<Map<String, AttendanceMark>> marks(
    String employeeId,
    SalaryMonth month,
  ) async {
    _requirePay();
    return _reads.marksOf(_firmId, employeeId, month.first, month.last);
  }

  // ---------------------------------------------------------------------
  // Advances
  // ---------------------------------------------------------------------

  Future<Money> advanceOwed(String employeeId) async {
    _requirePay();
    return _reads.advanceOwed(_firmId, employeeId);
  }

  Future<List<AdvanceLine>> advanceLines(String employeeId) async {
    _requirePay();
    return _reads.advanceLines(_firmId, employeeId);
  }

  /// What every man owes of his advances, by employee id.
  Future<Map<String, Money>> advancesOwed() async {
    _requirePay();
    return {
      for (final b in await _reads.advanceBalances(_firmId))
        b.employee.id: b.owed,
    };
  }

  /// Gives an advance. Returns the entry's number.
  Future<String> giveAdvance(AdvanceDraft draft) async {
    _requirePay();
    return _writer.giveAdvance(_app.actorNow(), draft);
  }

  /// Cancels an advance entered by mistake. Returns the cancelling entry's
  /// number.
  Future<String> cancelAdvance({
    required String employeeId,
    required String entryId,
    required String reason,
  }) async {
    _requirePay();
    return _writer.cancelAdvance(
      _app.actorNow(),
      employeeId: employeeId,
      entryId: entryId,
      reason: reason,
    );
  }

  // ---------------------------------------------------------------------
  // Wages
  // ---------------------------------------------------------------------

  /// [employeeId]'s wages for [month] as the register and the shop's rule
  /// work them out, before any bonus, cut or advance.
  Future<WageWorking> working(String employeeId, SalaryMonth month) async {
    _requirePay();
    final man = await _reads.employee(_firmId, employeeId);
    if (man == null) {
      throw const StaffRefused('That is not one of the shop\'s people.');
    }
    return workWages(
      employee: man,
      month: month,
      marks: await _reads.marksOf(_firmId, employeeId, month.first, month.last),
      rule: (await rules()).dayRule,
      today: _today,
    );
  }

  /// The live slip already paying [employeeId] for [month], by number.
  Future<String?> paidAlready(String employeeId, SalaryMonth month) async {
    _requirePay();
    return _reads.livePaidSlipNo(_firmId, employeeId, month);
  }

  /// Pays a month's wages. Returns the slip's id.
  Future<String> paySalary(SalaryDraft draft) async {
    _requirePay();
    return _writer.paySalary(_app.actorNow(), draft);
  }

  /// Cancels a slip. Returns the cancelling entry's number.
  Future<String> cancelSalary(String slipId, {required String reason}) async {
    _requirePay();
    return _writer.cancelSalary(_app.actorNow(), slipId, reason: reason);
  }

  /// Puts a slip right: cancelled and paid again as [draft], in one act.
  /// Returns the new slip's id.
  Future<String> correctSalary(
    String slipId,
    SalaryDraft draft, {
    required String reason,
  }) async {
    _requirePay();
    return _writer.correctSalary(
      _app.actorNow(),
      slipId,
      draft,
      reason: reason,
    );
  }

  /// One man's slips, newest month first.
  Future<List<SalarySlip>> slips(String employeeId) async {
    _requirePay();
    return _reads.slips(_firmId, employeeId: employeeId);
  }

  Future<SalarySlip?> slip(String slipId) async {
    _requirePay();
    return _reads.slip(_firmId, slipId);
  }
}
