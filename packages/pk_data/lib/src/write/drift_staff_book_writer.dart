import 'package:pk_domain/pk_domain.dart';

import '../read/drift_staff_book_reads.dart';
import 'chart_top_up.dart' show accountsBySystemKey;
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The staff book, written through the one write path (M65).
///
/// The people and the register are rows of their own; an advance and a
/// month's wages are entries, every line tagged with whose they are (see
/// `staff_book.dart` in the domain). Roles are the service's to check; this
/// checks what is true of the books whoever is asking: a man who left is
/// not marked present, no more of an advance comes back than he owes, and
/// a slip adds up.
final class DriftStaffBookWriter {
  const DriftStaffBookWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  // ---------------------------------------------------------------------
  // The people
  // ---------------------------------------------------------------------

  /// Adds somebody to the payroll. Returns his id.
  Future<String> addEmployee(ActorContext actor, EmployeeDraft draft) =>
      runner.run(actor, (tx) async {
        checkEmployeeDraft(draft, today: actor.businessDate);
        await _checkUserLink(tx, draft.userId, employeeId: null);
        final id = await tx.insert('employees', _columns(draft));
        tx.audit(
          action: employeeAddedAction,
          entityTable: 'employees',
          entityId: id,
          summary:
              '${draft.name.trim()} joined on ${draft.joinedOn.value}, '
              '${draft.basis.code}',
        );
        return id;
      });

  /// Changes his details: his pay from the next slip, the day he left.
  Future<void> editEmployee(
    ActorContext actor,
    String employeeId,
    EmployeeDraft draft,
  ) => runner.run(actor, (tx) async {
    final was = await _employee(tx, employeeId);
    checkEmployeeDraft(draft, today: actor.businessDate);
    await _checkUserLink(tx, draft.userId, employeeId: employeeId);
    final paidAfter = await tx.selectOne(
      'SELECT month_local FROM salary_slips WHERE firm_id = ? '
      "AND employee_id = ? AND status = 'paid' AND deleted_at_utc IS NULL "
      'AND month_local < ? ORDER BY month_local LIMIT 1',
      [actor.firmId, employeeId, SalaryMonth.of(draft.joinedOn).code],
    );
    if (paidAfter != null) {
      throw StaffRefused(
        '${was.name} was paid for ${paidAfter.read<String>('month_local')}, '
        'before ${draft.joinedOn.value}. Cancel that slip first, or keep '
        'the day he joined.',
      );
    }
    await tx.update('employees', employeeId, _columns(draft));
    tx.audit(
      action: employeeEditedAction,
      entityTable: 'employees',
      entityId: employeeId,
      summary: '${draft.name.trim()}: details changed',
      before: {
        'name': was.name,
        'pay_basis': was.basis.code,
        'rate_paisa': was.rate.inPaisa,
        'left_on_local': was.leftOn?.value,
      },
      after: {
        'name': draft.name.trim(),
        'pay_basis': draft.basis.code,
        'rate_paisa': draft.rate.inPaisa,
        'left_on_local': draft.leftOn?.value,
      },
    );
  });

  Map<String, Object?> _columns(EmployeeDraft draft) {
    final phone = draft.phone?.trim() ?? '';
    final note = draft.note?.trim() ?? '';
    return {
      'name': draft.name.trim(),
      'phone': phone.isEmpty ? null : phone,
      'cnic': draft.cnicKept,
      'kaam': draft.kaam.code,
      'joined_on_local': draft.joinedOn.value,
      'pay_basis': draft.basis.code,
      'rate_paisa': draft.rate.inPaisa,
      'left_on_local': draft.leftOn?.value,
      'user_id': draft.userId,
      'note': note.isEmpty ? null : note,
    };
  }

  /// One sign-in is one man: a link already made elsewhere is refused.
  Future<void> _checkUserLink(
    Tx tx,
    String? userId, {
    required String? employeeId,
  }) async {
    if (userId == null) return;
    final user = await tx.selectOne(
      'SELECT name FROM users WHERE id = ? AND firm_id = ? '
      'AND deleted_at_utc IS NULL',
      [userId, tx.actor.firmId],
    );
    if (user == null) {
      throw const StaffRefused('That sign-in is not one of this shop.');
    }
    final taken = await tx.selectOne(
      'SELECT name FROM employees WHERE firm_id = ? AND user_id = ? '
      'AND id <> ? AND deleted_at_utc IS NULL',
      [tx.actor.firmId, userId, employeeId ?? ''],
    );
    if (taken != null) {
      throw StaffRefused(
        "${user.read<String>('name')}'s sign-in is already "
        "${taken.read<String>('name')}'s.",
      );
    }
  }

  /// Puts him in the recycle bin, or brings him back. Refused while he
  /// still owes an advance, as M3 refuses hiding a customer who owes.
  Future<void> setHidden(
    ActorContext actor,
    String employeeId, {
    required bool hidden,
  }) => runner.run(actor, (tx) async {
    final man = await _employee(tx, employeeId);
    if (man.hidden == hidden) return;
    if (hidden) {
      final owed = await DriftStaffBookReads.inside(
        tx,
      ).advanceOwed(actor.firmId, employeeId);
      if (owed.isPositive) {
        throw StaffRefused(
          '${man.name} still owes Rs ${owed.amountOnly} of advances. Take '
          'it back off his wages first.',
        );
      }
    }
    await tx.update('employees', employeeId, {'is_hidden': hidden ? 1 : 0});
    tx.audit(
      action: hidden ? employeeHiddenAction : employeeRestoredAction,
      entityTable: 'employees',
      entityId: employeeId,
      summary: hidden
          ? '${man.name} put in the recycle bin'
          : '${man.name} brought back',
    );
  });

  // ---------------------------------------------------------------------
  // The register
  // ---------------------------------------------------------------------

  /// Marks [day] for each man in [marks]. One act, one line in the
  /// activity log; a man whose mark is already that is left as he was.
  Future<void> mark(
    ActorContext actor,
    BusinessDate day,
    Map<String, AttendanceMark> marks,
  ) => runner.run(actor, (tx) async {
    if (marks.isEmpty) return;
    if (day.value.compareTo(actor.businessDate.value) > 0) {
      throw const StaffRefused('A day not yet come cannot be marked.');
    }
    final changed = <String>[];
    final rows = <String>[];
    for (final entry in marks.entries) {
      final man = await _employee(tx, entry.key);
      if (man.hidden || !man.worksOn(day)) {
        throw StaffRefused(
          '${man.name} was not on the payroll on ${day.value}.',
        );
      }
      final id = attendanceRowId(man.id, day);
      final held = await tx.selectOne(
        'SELECT mark FROM attendance WHERE id = ?',
        [id],
      );
      if (held == null) {
        await tx.insert('attendance', {
          'employee_id': man.id,
          'day_local': day.value,
          'mark': entry.value.code,
        }, id: id);
      } else if (held.read<String>('mark') != entry.value.code) {
        await tx.update('attendance', id, {'mark': entry.value.code});
      } else {
        continue;
      }
      changed.add('${man.name}: ${entry.value.code}');
      rows.add(id);
    }
    if (changed.isEmpty) return;
    tx.audit(
      action: attendanceMarkedAction,
      entityTable: 'attendance',
      // One man's row when one was marked; the day when the register was.
      entityId: rows.length == 1 ? rows.single : day.value,
      summary: 'Register for ${day.value}: ${changed.join(', ')}',
    );
  });

  /// Sets the staff book's two rules.
  Future<void> setRules(ActorContext actor, StaffRules rules) =>
      runner.run(actor, (tx) async {
        final now = await DriftStaffBookReads.inside(tx).rules(actor.firmId);
        var changed = false;
        Future<void> put(String key, String value, String id) async {
          final held = await tx.selectOne(
            'SELECT id, setting_value FROM settings WHERE firm_id = ? '
            'AND setting_key = ? AND deleted_at_utc IS NULL',
            [actor.firmId, key],
          );
          if (held == null) {
            // An id worked out from the shop's, as M53's rule is: an owner
            // who sets it on two phones while they are apart writes one row
            // twice, and the merge keeps the later.
            await tx.insert('settings', {
              'setting_key': key,
              'setting_value': value,
            }, id: id);
          } else if (held.read<String>('setting_value') != value) {
            await tx.update('settings', held.read<String>('id'), {
              'setting_value': value,
            });
          } else {
            return;
          }
          changed = true;
        }

        await put(
          staffDayRuleSetting,
          rules.dayRule.code,
          'staff-day-rule-${actor.firmId}',
        );
        await put(
          staffCashierAttendanceSetting,
          rules.cashierMarksAttendance ? '1' : '0',
          'staff-cashier-register-${actor.firmId}',
        );
        if (!changed) return;
        tx.audit(
          action: staffRulesSetAction,
          entityTable: 'settings',
          entityId: actor.firmId,
          summary:
              'Staff book: a day is ${rules.dayRule.code}; cashier marks the '
              'register: ${rules.cashierMarksAttendance ? 'yes' : 'no'}',
          before: {
            'day_rule': now.dayRule.code,
            'cashier_attendance': now.cashierMarksAttendance,
          },
          after: {
            'day_rule': rules.dayRule.code,
            'cashier_attendance': rules.cashierMarksAttendance,
          },
        );
      });

  // ---------------------------------------------------------------------
  // Advances
  // ---------------------------------------------------------------------

  /// Gives an advance. Returns the entry's number.
  Future<String> giveAdvance(ActorContext actor, AdvanceDraft draft) =>
      runner.run(actor, (tx) async {
        final man = await _employee(tx, draft.employeeId);
        if (man.hidden) {
          throw StaffRefused('${man.name} is in the recycle bin.');
        }
        checkAdvance(draft, employee: man, today: actor.businessDate);
        final from = await _moneyAccount(tx, draft.paymentAccountId);
        final accounts = await _accounts(tx);
        final number = await _journalNumber(tx, draft.givenOn);
        final entry = advanceEntry(
          draft: draft,
          employeeName: man.name,
          entryNo: number,
          recordedAtUtcMillis: actor.epochMillis,
          advancesAccountId: accounts.advances,
          moneyAccountId: from,
        );
        await _write(tx, entry, man.id);
        tx.audit(
          action: staffAdvanceGivenAction,
          entityTable: 'employees',
          entityId: man.id,
          summary:
              '$number: Rs ${draft.amount.amountOnly} advance to ${man.name}',
          amountPaisa: draft.amount.inPaisa,
        );
        return number;
      });

  /// Cancels an advance entered by mistake, by the opposite entry dated
  /// today. Refused once any of it has come back off his wages beyond what
  /// he would then owe. Returns the cancelling entry's number.
  Future<String> cancelAdvance(
    ActorContext actor, {
    required String employeeId,
    required String entryId,
    required String reason,
  }) => runner.run(actor, (tx) async {
    if (reason.trim().isEmpty) {
      throw const StaffRefused('Say why it is cancelled.');
    }
    final man = await _employee(tx, employeeId);
    final reads = DriftStaffBookReads.inside(tx);
    final line = (await reads.advanceLines(
      actor.firmId,
      employeeId,
    )).where((l) => l.entryId == entryId).firstOrNull;
    if (line == null || line.kind != AdvanceLineKind.given) {
      throw const StaffRefused('That is not an advance given to him.');
    }
    if (line.cancelled) {
      throw const StaffRefused('That advance is already cancelled.');
    }
    final owed = await reads.advanceOwed(actor.firmId, employeeId);
    if (line.amount > owed) {
      throw StaffRefused(
        'Rs ${(line.amount - owed).amountOnly} of it has already come back '
        "off ${man.name}'s wages. Cancel that slip first.",
      );
    }
    final (id: _, :number) = await _reverse(
      tx,
      entryId,
      man.id,
      reason: 'Advance to ${man.name}, ${reason.trim()}',
    );
    tx.audit(
      action: staffAdvanceCancelledAction,
      entityTable: 'journal_entries',
      entityId: entryId,
      summary:
          '$number cancels ${line.entryNo}, advance to ${man.name}: '
          '${reason.trim()}',
      amountPaisa: line.amount.inPaisa,
    );
    return number;
  });

  // ---------------------------------------------------------------------
  // Wages
  // ---------------------------------------------------------------------

  /// Pays a month's wages. Returns the slip's id.
  Future<String> paySalary(
    ActorContext actor,
    SalaryDraft draft,
  ) => runner.run(actor, (tx) async {
    final slip = await _pay(tx, draft);
    tx.audit(
      action: salaryPaidAction,
      entityTable: 'salary_slips',
      entityId: slip.id,
      summary:
          '${slip.no}: ${slip.name}, ${draft.month.code}, '
          'Rs ${slip.figures.net.amountOnly} paid'
          '${slip.figures.recovered.isPositive ? ', Rs ${slip.figures.recovered.amountOnly} off his advance' : ''}',
      amountPaisa: slip.figures.earned.inPaisa,
    );
    return slip.id;
  });

  /// Cancels a slip entered by mistake: the opposite entry, dated today,
  /// and the slip marked cancelled with [reason]. What it took off his
  /// advance is owed again. Returns the cancelling entry's number.
  Future<String> cancelSalary(
    ActorContext actor,
    String slipId, {
    required String reason,
  }) => runner.run(actor, (tx) async {
    final undone = await _cancel(tx, slipId, reason);
    tx.audit(
      action: salaryCancelledAction,
      entityTable: 'salary_slips',
      entityId: slipId,
      summary:
          '${undone.reversalNo} cancels ${undone.slipNo}, ${undone.name}: '
          '${reason.trim()}',
      amountPaisa: undone.earned.inPaisa,
    );
    return undone.reversalNo;
  });

  /// Puts a slip right: cancels it and pays [draft] in its place, in one
  /// act, the new slip pointing at the old. Returns the new slip's id.
  Future<String> correctSalary(
    ActorContext actor,
    String slipId,
    SalaryDraft draft, {
    required String reason,
  }) => runner.run(actor, (tx) async {
    final undone = await _cancel(tx, slipId, reason);
    final slip = await _pay(tx, draft, replaces: slipId);
    tx.audit(
      action: salaryCorrectedAction,
      entityTable: 'salary_slips',
      entityId: slipId,
      summary:
          '${undone.slipNo} (Rs ${undone.net.amountOnly}) put right as '
          '${slip.no} (Rs ${slip.figures.net.amountOnly}), ${slip.name}: '
          '${reason.trim()}',
      before: {'slip_no': undone.slipNo, 'net_paisa': undone.net.inPaisa},
      after: {'slip_no': slip.no, 'net_paisa': slip.figures.net.inPaisa},
      amountPaisa: slip.figures.earned.inPaisa,
    );
    return slip.id;
  });

  Future<({String id, String no, String name, SalaryFigures figures})> _pay(
    Tx tx,
    SalaryDraft draft, {
    String? replaces,
  }) async {
    final actor = tx.actor;
    final reads = DriftStaffBookReads.inside(tx);
    final man = await _employee(tx, draft.employeeId);
    if (man.hidden) {
      throw StaffRefused('${man.name} is in the recycle bin.');
    }
    final paid = await reads.livePaidSlipNo(actor.firmId, man.id, draft.month);
    if (paid != null) {
      throw StaffRefused(
        '${man.name} has been paid for ${draft.month.code} already, on '
        '$paid. Correct that slip, or cancel it first.',
      );
    }
    final rules = await reads.rules(actor.firmId);
    final working = workWages(
      employee: man,
      month: draft.month,
      marks: await reads.marksOf(
        actor.firmId,
        man.id,
        draft.month.first,
        draft.month.last,
      ),
      rule: rules.dayRule,
      today: actor.businessDate,
    );
    final figures = checkSalary(
      employee: man,
      working: working,
      draft: draft,
      advanceOwed: await reads.advanceOwed(actor.firmId, man.id),
      today: actor.businessDate,
    );
    final accounts = await _accounts(tx);
    final from = figures.net.isPositive
        ? await _moneyAccount(tx, draft.paymentAccountId!)
        : null;
    final entryNo = await _journalNumber(tx, draft.paidOn);
    final entry = salaryEntry(
      figures: figures,
      employeeName: man.name,
      month: draft.month,
      paidOn: draft.paidOn,
      entryNo: entryNo,
      recordedAtUtcMillis: actor.epochMillis,
      salariesAccountId: accounts.salaries,
      advancesAccountId: accounts.advances,
      moneyAccountId: from,
    );
    final entryId = await _write(tx, entry, man.id);
    final number = await sequences.allocate(
      tx,
      docType: 'salary_slip',
      fiscalYear: draft.paidOn.fiscalYear,
    );
    final note = draft.note?.trim() ?? '';
    final t = working.tally;
    final slipId = await tx.insert('salary_slips', {
      'slip_no': number.formatted,
      'employee_id': man.id,
      'month_local': draft.month.code,
      'paid_on_local': draft.paidOn.value,
      'pay_basis': working.basis.code,
      'rate_paisa': working.rate.inPaisa,
      'day_rule': working.dayRule?.code,
      'basis_days': working.basisDays,
      'employed_days': t.employedDays,
      'present_days': t.present,
      'late_days': t.late,
      'half_days': t.halfDay,
      'paid_leave_days': t.paidLeave,
      'unpaid_leave_days': t.unpaidLeave,
      'absent_days': t.absent,
      'unmarked_days': t.unmarked + t.toCome,
      'paid_halves': working.paidHalves,
      'base_pay_paisa': figures.basePay.inPaisa,
      'additions_paisa': figures.additions.inPaisa,
      'deductions_paisa': figures.deductions.inPaisa,
      'advance_recovered_paisa': figures.recovered.inPaisa,
      'net_paid_paisa': figures.net.inPaisa,
      'payment_account_id': figures.net.isPositive
          ? draft.paymentAccountId
          : null,
      'journal_entry_id': entryId,
      'status': 'paid',
      'replaces_slip_id': replaces,
      'note': note.isEmpty ? null : note,
    });
    var lineNo = 0;
    for (final line in draft.lines) {
      await tx.insert('salary_lines', {
        'slip_id': slipId,
        'line_no': ++lineNo,
        'kind': line.kind.code,
        'label': line.label.trim(),
        'amount_paisa': line.amount.inPaisa,
      });
    }
    return (id: slipId, no: number.formatted, name: man.name, figures: figures);
  }

  Future<
    ({String slipNo, String reversalNo, String name, Money earned, Money net})
  >
  _cancel(Tx tx, String slipId, String reason) async {
    if (reason.trim().isEmpty) {
      throw const StaffRefused('Say why it is cancelled.');
    }
    final slip = await DriftStaffBookReads.inside(
      tx,
    ).slip(tx.actor.firmId, slipId);
    if (slip == null) {
      throw const StaffRefused('That is not a slip of this shop.');
    }
    if (slip.cancelled) {
      throw StaffRefused('${slip.slipNo} is already cancelled.');
    }
    final reversal = await _reverse(
      tx,
      slip.entryId,
      slip.employeeId,
      reason: '${slip.slipNo}, ${slip.employeeName}, ${reason.trim()}',
    );
    await tx.update('salary_slips', slipId, {
      'status': 'void',
      'void_reason': reason.trim(),
      'reversal_entry_id': reversal.id,
    });
    return (
      slipNo: slip.slipNo,
      reversalNo: reversal.number,
      name: slip.employeeName,
      earned: slip.figures.earned,
      net: slip.figures.net,
    );
  }

  // ---------------------------------------------------------------------

  Future<Employee> _employee(Tx tx, String employeeId) async {
    final man = await DriftStaffBookReads.inside(
      tx,
    ).employee(tx.actor.firmId, employeeId);
    if (man == null) {
      throw const StaffRefused('That is not one of the shop\'s people.');
    }
    return man;
  }

  /// Salaries and Wages and Staff Advances, either added to the chart the
  /// first time a shop set up before M65 needs it (`chart_top_up`).
  Future<({String salaries, String advances})> _accounts(Tx tx) async {
    final keys = await accountsBySystemKey(tx, {salariesKey, staffAdvancesKey});
    final salaries = keys[salariesKey];
    final advances = keys[staffAdvancesKey];
    if (salaries == null || advances == null) {
      throw const StaffRefused(
        'The Salaries and Wages or Staff Advances account was archived. '
        'Bring it back in Accounts first.',
      );
    }
    return (salaries: salaries, advances: advances);
  }

  Future<String> _journalNumber(Tx tx, BusinessDate on) async {
    final n = await sequences.allocate(
      tx,
      docType: 'journal_entry',
      fiscalYear: on.fiscalYear,
    );
    return n.formatted;
  }

  /// Writes [entry] with every line tagged for [employeeId]. Returns the
  /// entry's id.
  Future<String> _write(
    Tx tx,
    JournalEntryPosting entry,
    String employeeId, {
    String? reverses,
  }) async {
    final id = await tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      'reverses_entry_id': reverses,
      'narration': entry.narration,
      'total_debit_paisa': entry.totalDebit.inPaisa,
      'total_credit_paisa': entry.totalCredit.inPaisa,
    });
    for (final line in entry.lines) {
      if (!line.isResolvedAccountId) {
        throw StateError(
          'A staff book line names account "${line.accountSystemKey}" by '
          'key. Its accounts are resolved before it is built.',
        );
      }
      await tx.insert('journal_lines', {
        'journal_entry_id': id,
        'line_no': line.lineNo,
        'account_id': line.accountId,
        'debit_paisa': line.debit.inPaisa,
        'credit_paisa': line.credit.inPaisa,
        'cost_centre': staffTag(employeeId),
        'narration': line.narration,
      });
    }
    return id;
  }

  /// Writes the opposite of [entryId], dated today and tagged as it was.
  Future<({String id, String number})> _reverse(
    Tx tx,
    String entryId,
    String employeeId, {
    required String reason,
  }) async {
    final head = (await tx.selectOne(
      'SELECT entry_no, entry_date_utc, entry_date_local, fiscal_year, '
      '       source_type, narration, total_debit_paisa, total_credit_paisa '
      'FROM journal_entries WHERE id = ? AND firm_id = ?',
      [entryId, tx.actor.firmId],
    ))!;
    final lines = await tx.select(
      'SELECT line_no, account_id, debit_paisa, credit_paisa, narration '
      'FROM journal_lines '
      'WHERE journal_entry_id = ? AND firm_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY line_no',
      [entryId, tx.actor.firmId],
    );
    final original = JournalEntryPosting(
      entryNo: head.read<String>('entry_no'),
      entryDateUtcMillis: head.read<int>('entry_date_utc'),
      entryDateLocal: head.read<String>('entry_date_local'),
      fiscalYear: head.read<int>('fiscal_year'),
      sourceType: head.read<String>('source_type'),
      totalDebit: Money.paisa(head.read<int>('total_debit_paisa')),
      totalCredit: Money.paisa(head.read<int>('total_credit_paisa')),
      narration: head.readNullable<String>('narration'),
      lines: [
        for (final l in lines)
          JournalLinePosting(
            lineNo: l.read<int>('line_no'),
            // The same account rows the original named, never re-resolved.
            accountSystemKey: '#${l.read<String>('account_id')}',
            debit: Money.paisa(l.read<int>('debit_paisa')),
            credit: Money.paisa(l.read<int>('credit_paisa')),
            narration: l.readNullable<String>('narration'),
          ),
      ],
    );
    final n = await sequences.allocate(
      tx,
      docType: 'journal_entry',
      fiscalYear: tx.actor.businessDate.fiscalYear,
    );
    final reversal = reverseEntry(
      original,
      actor: tx.actor,
      number: AllocatedNumber(
        formatted: n.formatted,
        series: n.series,
        sequence: n.sequence,
      ),
      reason: reason,
    );
    final id = await _write(tx, reversal, employeeId, reverses: entryId);
    return (id: id, number: reversal.entryNo);
  }

  /// The account in the chart the drawer or the bank [paymentAccountId]
  /// posts to. Never the cheque drawer or an adjustment: wages are paid in
  /// money, and a cheque the shop writes has its own book (M6).
  Future<String> _moneyAccount(Tx tx, String paymentAccountId) async {
    final row = await tx.selectOne(
      'SELECT pa.ledger_account_id, pa.mode_label, a.system_key '
      'FROM payment_accounts pa JOIN accounts a ON a.id = pa.ledger_account_id '
      'WHERE pa.id = ? AND pa.firm_id = ? AND pa.deleted_at_utc IS NULL '
      '  AND pa.is_active = 1',
      [paymentAccountId, tx.actor.firmId],
    );
    if (row == null) {
      throw const StaffRefused('Pick the cash or the bank it is paid from.');
    }
    if (const {
          'cheque',
          'adjustment',
        }.contains(row.read<String>('mode_label')) ||
        controlAccountKeys.contains(row.readNullable<String>('system_key'))) {
      throw const StaffRefused(
        'Wages and advances are paid from the cash or a bank. A cheque the '
        'shop writes is recorded in the cheque book.',
      );
    }
    return row.read<String>('ledger_account_id');
  }
}
