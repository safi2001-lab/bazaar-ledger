import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'accounts_screen.dart';

/// Writing a journal voucher: a reason, and two or more lines that agree.
///
/// Only the accounts a hand entry may touch are offered; the ones with a
/// book beneath them are moved from their own screens.
class JournalVoucherScreen extends ConsumerStatefulWidget {
  const JournalVoucherScreen({super.key});

  @override
  ConsumerState<JournalVoucherScreen> createState() =>
      _JournalVoucherScreenState();
}

class _Line {
  ChartAccount? account;
  final debit = TextEditingController();
  final credit = TextEditingController();

  Money get debitAmount => Money.tryParse(debit.text) ?? Money.zero;
  Money get creditAmount => Money.tryParse(credit.text) ?? Money.zero;

  void dispose() {
    debit.dispose();
    credit.dispose();
  }
}

class _JournalVoucherScreenState extends ConsumerState<JournalVoucherScreen> {
  final _narration = TextEditingController();
  final _lines = [_Line(), _Line()];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _narration.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      final entryNo = await services.postJournal(
        services.actorNow(),
        narration: _narration.text,
        lines: [
          for (final l in _lines)
            if (l.account case final account?)
              VoucherLine(
                account: account.asVoucherAccount,
                debit: l.debitAmount,
                credit: l.creditAmount,
              ),
        ],
      );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.journalSaved(entryNo))));
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
          VoucherRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final accounts = [
      for (final a
          in ref.watch(chartProvider).valueOrNull ?? const <ChartAccount>[])
        if (!a.isControl) a,
    ];
    final debit = Money.sum([for (final l in _lines) l.debitAmount]);
    final credit = Money.sum([for (final l in _lines) l.creditAmount]);
    final gap = debit - credit;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.journalTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlField(controller: _narration, label: s.journalNarration),
            const SizedBox(height: BlTokens.space4),
            for (final (i, line) in _lines.indexed) ...[
              BlCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButton<String>(
                      key: ValueKey('account-$i'),
                      isExpanded: true,
                      value: line.account?.id,
                      hint: Text(s.journalPickAccount),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.code} ${a.name}'),
                          ),
                      ],
                      onChanged: (id) => setState(
                        () => line.account = accounts.firstWhere(
                          (a) => a.id == id,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: BlField(
                            controller: line.debit,
                            label: s.journalDebit,
                            numeric: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: BlTokens.space2),
                        Expanded(
                          child: BlField(
                            controller: line.credit,
                            label: s.journalCredit,
                            numeric: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BlTokens.space2),
            ],
            BlButton(
              label: s.journalAddLine,
              icon: Icons.add,
              kind: BlButtonKind.secondary,
              onPressed: () => setState(() => _lines.add(_Line())),
            ),
            const SizedBox(height: BlTokens.space3),
            BlChip(
              gap.isZero
                  ? s.journalBalanced
                  : s.journalDifference(gap.abs.amountOnly),
              tone: gap.isZero ? BlChipTone.good : BlChipTone.warn,
            ),
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.journalSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
