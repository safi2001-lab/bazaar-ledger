import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'staff_providers.dart';

/// The staff book's two rules (M65): how a day of a monthly salary is
/// reckoned, and whether the counter may mark the register. The owner's to
/// set, as every rule of the shop is; anybody who opens the staff book may
/// read them, so nobody has to guess why a slip came to what it did.
class StaffRulesScreen extends ConsumerStatefulWidget {
  const StaffRulesScreen({super.key});

  @override
  ConsumerState<StaffRulesScreen> createState() => _StaffRulesScreenState();
}

class _StaffRulesScreenState extends ConsumerState<StaffRulesScreen> {
  bool _busy = false;
  String? _failure;

  Future<void> _set(StaffRules rules) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(appServicesProvider).staffBook.setRules(rules);
      ref.bumpRefresh();
    } on Object catch (error) {
      if (mounted) setState(() => _failure = staffError(s, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayChange = ref.watch(appServicesProvider).staffBook.maySetRules;
    final rules = ref.watch(staffRulesProvider).valueOrNull;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.staffRulesTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            if (rules != null) ...[
              Text(
                s.staffDayRuleHint,
                style: TextStyle(fontSize: 14, color: t.inkMuted),
              ),
              RadioGroup<DayRule>(
                groupValue: rules.dayRule,
                onChanged: (rule) {
                  if (rule == null || !mayChange) return;
                  _set(
                    StaffRules(
                      dayRule: rule,
                      cashierMarksAttendance: rules.cashierMarksAttendance,
                    ),
                  );
                },
                child: Column(
                  children: [
                    RadioListTile<DayRule>(
                      value: DayRule.thirtyDay,
                      enabled: mayChange && !_busy,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.staffDayRuleThirty),
                      subtitle: Text(s.staffDayRuleThirtyHint),
                    ),
                    RadioListTile<DayRule>(
                      value: DayRule.calendar,
                      enabled: mayChange && !_busy,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.staffDayRuleCalendar),
                      subtitle: Text(s.staffDayRuleCalendarHint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BlTokens.space3),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rules.cashierMarksAttendance,
                title: Text(s.staffCashierMarks),
                subtitle: Text(s.staffCashierMarksHint),
                onChanged: !mayChange || _busy
                    ? null
                    : (on) => _set(
                        StaffRules(
                          dayRule: rules.dayRule,
                          cashierMarksAttendance: on,
                        ),
                      ),
              ),
              const SizedBox(height: BlTokens.space3),
              Text(
                s.staffWhoSeesPay,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ],
            if (!mayChange) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.staffRulesOwnerOnly,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
