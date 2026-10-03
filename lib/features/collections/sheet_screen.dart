import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/printing_providers.dart';
import '../reports/report_export.dart';
import 'sheet_paper.dart';

/// One sheet, as kept (M55).
final collectionSheetProvider = FutureProvider.autoDispose
    .family<CollectionSheet?, String>((ref, sheetId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).collections.sheet(sheetId);
    });

/// One line's mark while the man's return is being written.
final class _Mark {
  CollectionOutcome? outcome;
  final amount = TextEditingController();
  final note = TextEditingController();
  String? promisedFor;
  String? accountId;

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

/// A recovery man's sheet: sent out, and written up on his return (M55).
///
/// Out: the numbered lines, each customer's bills and what they owe, to
/// print on the counter's roll, send as a PDF, or send him on WhatsApp.
///
/// Back: each line marked — paid in full, paid some, promised, shop closed,
/// refused, or left for not reached — with what came in and how, and a
/// running count of what came against what was expected and the cash he
/// should be handing over. Saving writes every receipt and promise on
/// every khata at once, or none of them.
class SheetScreen extends ConsumerStatefulWidget {
  const SheetScreen({super.key, required this.sheetId});

  final String sheetId;

  @override
  ConsumerState<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends ConsumerState<SheetScreen> {
  bool _marking = false;
  final _marks = <int, _Mark>{};
  bool _busy = false;
  bool _printing = false;
  String? _error;

  @override
  void dispose() {
    for (final m in _marks.values) {
      m.dispose();
    }
    super.dispose();
  }

  _Mark _markOf(int lineNo) => _marks.putIfAbsent(lineNo, _Mark.new);

  /// The cash account, which a round's money lands in unless said.
  String? _cashAccount(List<PaymentAccountSummary> accounts) =>
      accounts.where((a) => a.modeLabel == 'cash').firstOrNull?.id ??
      accounts.firstOrNull?.id;

  /// The marks as the service takes them; a line with no outcome left out.
  Map<int, SheetMark> _sheetMarks(
    CollectionSheet sheet,
    List<PaymentAccountSummary> accounts,
  ) {
    final byId = {for (final a in accounts) a.id: a};
    return {
      for (final line in sheet.lines)
        if (_marks[line.lineNo] case final m? when m.outcome != null)
          line.lineNo: SheetMark(
            outcome: m.outcome!,
            amount: switch (m.outcome!) {
              CollectionOutcome.paid => line.due,
              _ => _money(m.amount.text),
            },
            promisedFor: m.promisedFor,
            paymentAccountId: m.accountId ?? _cashAccount(accounts),
            mode:
                byId[m.accountId ?? _cashAccount(accounts)]?.modeLabel ??
                'cash',
            note: m.note.text.trim().isEmpty ? null : m.note.text.trim(),
          ),
    };
  }

  static Money? _money(String text) {
    final raw = text.trim().replaceAll(',', '');
    return raw.isEmpty ? null : Money.tryParse(raw);
  }

  Future<void> _save(
    CollectionSheet sheet,
    List<PaymentAccountSummary> accounts,
  ) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final marks = _sheetMarks(sheet, accounts);
    final today = ref.read(appServicesProvider).udhaar.today;
    // Said before anything is written, in the shopkeeper's words; the
    // service checks the same and writes nothing if one line is wrong.
    for (final line in sheet.lines) {
      final mark = marks[line.lineNo];
      if (mark == null) continue;
      if (mark.problemFor(line, today) != null) {
        setState(
          () => _error = switch (mark.outcome) {
            CollectionOutcome.promise => s.sheetPromiseDayMissing(
              line.partyName,
            ),
            _ => s.sheetAmountMissing(line.partyName),
          },
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final round = await ref
          .read(appServicesProvider)
          .collections
          .recordReturn(sheet.id, marks);
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.sheetSaved(round.sheet.collected.amountOnly))),
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _marking = false;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _print(CollectionSheet sheet) async {
    if (_printing) return;
    final s = AppStrings.of(context);
    setState(() => _printing = true);
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    try {
      final settings = await ref.read(printerSettingsProvider.future);
      if (settings == null) {
        say(s.receiptNoPrinter);
        return;
      }
      final services = ref.read(appServicesProvider);
      final firm = await ref.read(firmProvider.future);
      final paper = EscPos()..initialise();
      for (final line in sheetSlip(
        s,
        sheet,
        width: settings.columns,
        shopName: firm?.name ?? '',
      )) {
        paper
          ..align(line.centred ? EscPosAlign.centre : EscPosAlign.left)
          ..bold(on: line.bold)
          ..line(line.text);
      }
      paper
        ..bold(on: false)
        ..feed(3)
        ..cut();
      final result = await services.printing.print(
        actor: services.actorNow(),
        settings: settings,
        // A sheet is printed afresh each time it is asked for — out, and
        // again on his return — so each press is its own job.
        jobKey:
            'sheet#${sheet.id}#${sheet.isSettled ? 'back' : 'out'}#'
            '${services.clock.nowUtc().microsecondsSinceEpoch}',
        bytes: paper.bytes,
      );
      say(switch (result.outcome) {
        PrintOutcome.printed => s.printerDone,
        PrintOutcome.notSent => s.printerNotSent,
        PrintOutcome.partial || PrintOutcome.unknown => s.printerPartial,
      });
    } on Object catch (error) {
      say('${s.commonSomethingWentWrong}: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _pdf(CollectionSheet sheet) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final firm = await ref.read(firmProvider.future);
      await shareReport(
        sheetTable(s, sheet),
        ReportFormat.pdf,
        shopName: firm?.name ?? '',
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _message(CollectionSheet sheet) async {
    final s = AppStrings.of(context);
    final firm = await ref.read(firmProvider.future);
    await SharePlus.instance.share(
      ShareParams(
        text: sheetMessage(s, sheet, shop: firm?.name ?? ''),
        subject: '${s.sheetPaperTitle} ${sheet.sheetNo}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final accounts = [
      for (final a
          in ref.watch(paymentAccountsProvider).valueOrNull ??
              const <PaymentAccountSummary>[])
        // A cheque is taken on the khata, where its number and bank are
        // written; a hidden allowance account is never money that came.
        if (a.modeLabel != 'cheque' && a.modeLabel != 'adjustment') a,
    ];
    final found = ref.watch(collectionSheetProvider(widget.sheetId));
    final sheet = found.valueOrNull;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(sheet?.sheetNo ?? s.sheetsTitle),
        actions: [
          if (sheet != null) ...[
            BlIconButton(
              icon: Icons.print_outlined,
              label: s.receiptPrint,
              onPressed: _printing ? null : () => unawaited(_print(sheet)),
            ),
            BlIconButton(
              icon: Icons.picture_as_pdf_outlined,
              label: s.reportSharePdf,
              onPressed: () => unawaited(_pdf(sheet)),
            ),
            BlIconButton(
              icon: Icons.chat_outlined,
              label: s.sendWhatsAppShort,
              onPressed: () => unawaited(_message(sheet)),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: found.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (sheet) => sheet == null
              ? BlEmpty(
                  icon: Icons.assignment_ind_outlined,
                  title: s.sheetsEmpty,
                  message: s.sheetsEmptyHint,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    BlTokens.space10,
                  ),
                  children: [
                    _Summary(
                      sheet: sheet,
                      live: _marking
                          ? _live(sheet, _sheetMarks(sheet, accounts))
                          : null,
                    ),
                    const SizedBox(height: BlTokens.space3),
                    for (final line in sheet.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: _LineCard(
                          line: line,
                          mark: _marking ? _markOf(line.lineNo) : null,
                          accounts: accounts,
                          cashAccount: _cashAccount(accounts),
                          enabled: !_busy,
                          onChanged: () => setState(() => _error = null),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: BlTokens.space2),
                      Text(
                        _error!,
                        style: TextStyle(color: t.danger, fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: BlTokens.space3),
                    if (!sheet.isSettled &&
                        !_marking &&
                        services.collections.mayRecordReturn)
                      BlButton(
                        label: s.sheetRecord,
                        icon: Icons.assignment_turned_in_outlined,
                        big: true,
                        onPressed: () => setState(() => _marking = true),
                      ),
                    if (_marking && !sheet.isSettled) ...[
                      BlButton(
                        label: s.sheetSave,
                        icon: Icons.check,
                        big: true,
                        busy: _busy,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_save(sheet, accounts)),
                      ),
                      const SizedBox(height: BlTokens.space2),
                      BlButton(
                        label: s.actionCancel,
                        kind: BlButtonKind.ghost,
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _marking = false;
                                _error = null;
                              }),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  /// What the marks so far would make of the sheet: collected and cash, as
  /// they are being written.
  CollectionSheet _live(CollectionSheet sheet, Map<int, SheetMark> marks) =>
      sheet.settled(
        on: '',
        by: '',
        lines: [
          for (final line in sheet.lines)
            line.withResult(switch (marks[line.lineNo]) {
              final m? => m.resultFor(line),
              null => null,
            }),
        ],
      );
}

/// What was expected, and — once he is back, or while it is being written —
/// what came and the cash to hand over.
class _Summary extends StatelessWidget {
  const _Summary({required this.sheet, this.live});

  final CollectionSheet sheet;

  /// The marks being written, as a sheet; null when not marking.
  final CollectionSheet? live;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final shown = live ?? sheet;
    final back = live != null || sheet.isSettled;

    Widget figure(String label, Money amount, {Color? colour}) => Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14, color: t.inkMuted)),
        ),
        BlMoney(amount, size: 16, colour: colour),
      ],
    );

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.sheetCollectorLine(sheet.collector),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          Text(
            [
              shortDate(sheet.dateLocal),
              s.sheetCustomers(sheet.lines.length),
              ?sheet.title,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: BlChip(
              sheet.isSettled ? s.sheetSettled : s.sheetOut,
              tone: sheet.isSettled ? BlChipTone.good : BlChipTone.warn,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          figure(s.sheetExpected, sheet.expected),
          if (back) ...[
            const SizedBox(height: BlTokens.space1),
            figure(s.sheetCollected, shown.collected, colour: t.money),
            const SizedBox(height: BlTokens.space1),
            figure(s.sheetCash, shown.cashToHandOver),
            if (shown.promised.isPositive) ...[
              const SizedBox(height: BlTokens.space1),
              figure(s.sheetPromised, shown.promised),
            ],
            const SizedBox(height: BlTokens.space2),
            Text(
              s.sheetCounts(
                shown.count(CollectionOutcome.paid) +
                    shown.count(CollectionOutcome.partial),
                shown.count(CollectionOutcome.promise),
                shown.count(CollectionOutcome.shopClosed) +
                    shown.count(CollectionOutcome.refused),
                shown.notReached,
              ),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          ],
          if (sheet.settledBy case final by? when live == null) ...[
            const SizedBox(height: BlTokens.space1),
            Text(
              s.sheetSettledBy(by),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One customer on the sheet; with [mark], being marked on his return.
class _LineCard extends ConsumerWidget {
  const _LineCard({
    required this.line,
    required this.mark,
    required this.accounts,
    required this.cashAccount,
    required this.enabled,
    required this.onChanged,
  });

  final SheetLine line;
  final _Mark? mark;
  final List<PaymentAccountSummary> accounts;
  final String? cashAccount;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final result = resultWords(s, line.result);
    final mark = this.mark;

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${line.lineNo}. ${line.partyName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              BlMoney(line.due, size: 16),
            ],
          ),
          if ([?line.phone, ?line.group].isNotEmpty)
            Text(
              [?line.phone, ?line.group].join(' · '),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          for (final b in line.bills)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${b.docNo} · ${shortDate(b.dateLocal)}',
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                ),
                BlMoney(
                  b.outstanding,
                  size: 12,
                  colour: t.inkMuted,
                  weight: FontWeight.w400,
                ),
              ],
            ),
          if (line.earlier.isPositive)
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.partyOpeningBalance,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                ),
                BlMoney(
                  line.earlier,
                  size: 12,
                  colour: t.inkMuted,
                  weight: FontWeight.w400,
                ),
              ],
            ),
          if (line.unpriced > 0)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space1),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: BlChip(
                  s.goodsGivenUnpriced(line.unpriced),
                  tone: BlChipTone.warn,
                ),
              ),
            ),
          if (result != null && mark == null)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space2),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: BlChip(
                  [result, ?line.result?.paymentNo].join(' · '),
                  tone: line.result!.outcome.tookMoney
                      ? BlChipTone.good
                      : BlChipTone.neutral,
                ),
              ),
            ),
          if (line.result == null && mark == null)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space1),
              child: Text(
                '${s.sheetPaperGot} ____________',
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
            ),
          if (mark != null) ..._marking(context, ref, mark),
        ],
      ),
    );
  }

  List<Widget> _marking(BuildContext context, WidgetRef ref, _Mark mark) {
    final s = AppStrings.of(context);
    final today = ref.watch(appServicesProvider).udhaar.today;
    final days = promiseDays(today);
    final outcome = mark.outcome;

    void set(void Function() change) {
      change();
      onChanged();
    }

    return [
      const SizedBox(height: BlTokens.space2),
      Wrap(
        spacing: BlTokens.space2,
        runSpacing: BlTokens.space2,
        children: [
          for (final (o, label) in [
            (CollectionOutcome.paid, s.outcomePaid),
            (CollectionOutcome.partial, s.outcomePartial),
            (CollectionOutcome.promise, s.outcomePromise),
            (CollectionOutcome.shopClosed, s.outcomeShopClosed),
            (CollectionOutcome.refused, s.outcomeRefused),
          ])
            ChoiceChip(
              selected: outcome == o,
              label: Text(label),
              // Tapped again, the mark comes off: not reached.
              onSelected: enabled
                  ? (on) => set(() => mark.outcome = on ? o : null)
                  : null,
            ),
        ],
      ),
      if (outcome == CollectionOutcome.partial ||
          outcome == CollectionOutcome.promise) ...[
        const SizedBox(height: BlTokens.space2),
        BlField(
          controller: mark.amount,
          label: outcome == CollectionOutcome.partial
              ? s.sheetAmount
              : s.promiseAmount,
          numeric: true,
          enabled: enabled,
          onChanged: (_) => onChanged(),
        ),
      ],
      if (outcome == CollectionOutcome.promise) ...[
        const SizedBox(height: BlTokens.space2),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final (day, label) in [
              (days.tomorrow, s.promiseTomorrow),
              (days.friday, s.promiseFriday),
              (days.nextWeek, s.promiseNextWeek),
              (days.salaryDay, s.promiseSalaryDay),
            ])
              ChoiceChip(
                selected: mark.promisedFor == day,
                label: Text('$label · ${shortDate(day)}'),
                onSelected: enabled
                    ? (_) => set(() => mark.promisedFor = day)
                    : null,
              ),
          ],
        ),
      ],
      if (outcome != null && outcome.tookMoney && accounts.length > 1) ...[
        const SizedBox(height: BlTokens.space2),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final a in accounts)
              ChoiceChip(
                selected: (mark.accountId ?? cashAccount) == a.id,
                label: Text(a.name),
                onSelected: enabled
                    ? (_) => set(() => mark.accountId = a.id)
                    : null,
              ),
          ],
        ),
      ],
      if (outcome != null) ...[
        const SizedBox(height: BlTokens.space2),
        BlField(controller: mark.note, label: s.sheetNote, enabled: enabled),
      ],
    ];
  }
}
