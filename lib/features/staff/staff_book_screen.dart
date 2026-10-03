import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'employee_editor_screen.dart';
import 'employee_screen.dart';
import 'register_screen.dart';
import 'staff_providers.dart';
import 'staff_rules_screen.dart';

/// The staff book (M65): the shop's people, what each is paid and owes of
/// his advances, and the way to the day's register.
///
/// DigiKhata's Staff Book, offline: attendance, salary, advance. Opened
/// from Home by whoever keeps or pays the staff; a cashier the owner lets
/// mark the register gets the register itself, and never a rupee.
class StaffBookScreen extends ConsumerWidget {
  const StaffBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final book = ref.watch(appServicesProvider).staffBook;
    if (!book.mayPay) return const RegisterScreen();

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.staffBookTitle),
        actions: [
          BlIconButton(
            icon: Icons.tune_outlined,
            label: s.staffRulesTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StaffRulesScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: book.mayKeep
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EmployeeEditorScreen(),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: Text(s.staffAdd),
            )
          : null,
      body: SafeArea(
        child: ref
            .watch(employeesProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              ),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (book) {
                final owed = Money.sum(book.owed.values);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space4,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  children: [
                    BlButton(
                      label: s.staffRegisterToday,
                      icon: Icons.fact_check_outlined,
                      expand: true,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: BlTokens.space3),
                    if (owed.isPositive) ...[
                      BlCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.staffAdvancesOwedTotal,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: t.inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            BlMoney(owed, size: 18, withSymbol: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: BlTokens.space3),
                    ],
                    if (book.people.isEmpty)
                      BlEmpty(
                        icon: Icons.badge_outlined,
                        title: s.staffEmpty,
                        message: s.staffEmptyHint,
                      )
                    else
                      for (final man in book.people)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: BlTokens.space2,
                          ),
                          child: _EmployeeCard(
                            man: man,
                            owed: book.owed[man.id] ?? Money.zero,
                          ),
                        ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.man, required this.owed});

  final Employee man;
  final Money owed;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final left = man.leftOn;
    return BlCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EmployeeScreen(employeeId: man.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            man.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: left == null ? t.ink : t.inkMuted,
            ),
          ),
          Text(
            '${kaamName(s, man.kaam)} · ${payText(s, man.basis, man.rate)}',
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          if (left != null || owed.isPositive) ...[
            const SizedBox(height: BlTokens.space1),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space1,
              children: [
                if (left != null) BlChip(s.staffLeftOn(left.value)),
                if (owed.isPositive)
                  BlChip(
                    s.staffAdvanceOwedChip(owed.amountOnly),
                    tone: BlChipTone.warn,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
