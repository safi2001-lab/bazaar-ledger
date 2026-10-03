import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/item_scheme_screen.dart' show showSchemeItemPicker;
import 'recurring_providers.dart';

/// A repeating bill set up or changed (M63): the goods and how many, how
/// often, from when and until when, at which prices, and whether the phone
/// may make it by itself.
///
/// Opened from a bill (its goods and customer already filled in), from a
/// customer's khata, or from the list of repeating bills to change one.
/// Nothing is kept until Save; the bill it came from is never touched.
class RecurringBillScreen extends ConsumerStatefulWidget {
  const RecurringBillScreen({
    super.key,
    required this.bill,
    this.isNew = false,
    this.leftOut,
  });

  final RecurringBill bill;
  final bool isNew;

  /// What of the bill it was copied from did not come, in words.
  final String? leftOut;

  @override
  ConsumerState<RecurringBillScreen> createState() =>
      _RecurringBillScreenState();
}

enum _Ends { never, onDate, times }

class _RecurringBillScreenState extends ConsumerState<RecurringBillScreen> {
  late final List<RecurringLine> _lines = [...widget.bill.lines];
  late final List<TextEditingController> _qty = [
    for (final l in widget.bill.lines)
      TextEditingController(text: l.qty.display),
  ];
  late RepeatKind _kind = widget.bill.every.kind;
  late int _weekday = widget.bill.every.kind == RepeatKind.weekly
      ? widget.bill.every.day
      : weekdayOf(widget.bill.startOn);
  late final _date = TextEditingController(
    text: widget.bill.every.kind == RepeatKind.monthly
        ? '${widget.bill.every.day}'
        : '${widget.bill.startOn.day}',
  );
  late final _days = TextEditingController(
    text: widget.bill.every.kind == RepeatKind.everyDays
        ? '${widget.bill.every.days}'
        : '14',
  );
  late BusinessDate _start = widget.bill.startOn;
  late _Ends _ends = widget.bill.endOn != null
      ? _Ends.onDate
      : widget.bill.times != null
      ? _Ends.times
      : _Ends.never;
  late BusinessDate? _endOn = widget.bill.endOn;
  late final _times = TextEditingController(
    text: widget.bill.times == null ? '' : '${widget.bill.times}',
  );
  late RecurringPrices _prices = widget.bill.prices;
  late RecurringMode _mode = widget.bill.mode;
  final Set<String> _gone = {};
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_readGone());
  }

  /// Which items on it are no longer kept: flagged on their lines.
  Future<void> _readGone() async {
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    if (firm == null) return;
    final gone = <String>{};
    for (final l in _lines) {
      final id = l.itemId;
      if (id == null) continue;
      if (await services.queries.itemById(firm.id, id) == null) gone.add(id);
    }
    if (mounted) setState(() => _gone.addAll(gone));
  }

  @override
  void dispose() {
    for (final c in _qty) {
      c.dispose();
    }
    _date.dispose();
    _days.dispose();
    _times.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final item = await showSchemeItemPicker(context);
    if (item == null || !mounted) return;
    setState(() {
      _lines.add(
        RecurringLine(
          itemId: item.id,
          name: item.name,
          qty: Qty.one,
          unitCode: item.unitCode,
          rate: item.saleRate,
        ),
      );
      _qty.add(TextEditingController(text: '1'));
    });
  }

  void _remove(int index) {
    setState(() {
      _lines.removeAt(index);
      _qty.removeAt(index).dispose();
    });
  }

  Future<BusinessDate?> _pickDate(BusinessDate initial) async {
    final services = ref.read(appServicesProvider);
    final today = BusinessDate.now(services.clock);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked == null) return null;
    return BusinessDate(
      '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}',
    );
  }

  /// The template as the screen holds it, or a refusal in words.
  RecurringBill _built() {
    final lines = <RecurringLine>[
      for (var i = 0; i < _lines.length; i++)
        _lines[i].withQty(Qty.tryParse(_qty[i].text) ?? Qty.zero),
    ];
    final every = switch (_kind) {
      RepeatKind.daily => const RepeatEvery.daily(),
      RepeatKind.weekly => RepeatEvery.weekly(_weekday),
      RepeatKind.monthly => RepeatEvery.monthly(
        int.tryParse(_date.text.trim()) ?? 0,
      ),
      RepeatKind.everyDays => RepeatEvery.everyDays(
        int.tryParse(_days.text.trim()) ?? 0,
      ),
    };
    final times = int.tryParse(_times.text.trim());
    return RecurringBill(
      id: widget.bill.id,
      partyId: widget.bill.partyId,
      partyName: widget.bill.partyName,
      lines: lines,
      every: every,
      startOn: _start,
      endOn: _ends == _Ends.onDate ? _endOn : null,
      times: _ends == _Ends.times ? (times ?? 0) : null,
      prices: _prices,
      mode: _mode,
      paused: widget.bill.paused,
      endedOn: widget.bill.endedOn,
      doneThrough: widget.bill.doneThrough,
      billDiscount: widget.bill.billDiscount,
      fromDocNo: widget.bill.fromDocNo,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await services.recurring.save(_built());
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.recurringSaved)));
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = recurringProblemText(s, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bill = widget.bill;

    Widget chips<T>(
      List<(T, String)> options,
      T selected,
      void Function(T) on,
    ) => Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            selected: value == selected,
            label: Text(label),
            onSelected: (_) => setState(() => on(value)),
          ),
      ],
    );

    Widget dateButton(BusinessDate? date, void Function(BusinessDate) on) =>
        Align(
          alignment: Alignment.centerLeft,
          child: BlButton(
            label: date == null
                ? s.recurringPickDate
                : shortDate(date.value, thisYear: 0),
            icon: Icons.event_outlined,
            kind: BlButtonKind.secondary,
            onPressed: () async {
              final picked = await _pickDate(date ?? _start);
              if (picked != null && mounted) setState(() => on(picked));
            },
          ),
        );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(widget.isNew ? s.recurringNewTitle : s.recurringEdit),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            BlTokens.space10,
          ),
          children: [
            Text(
              s.recurringFor(bill.partyName),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            if (bill.fromDocNo case final no?)
              Text(
                s.recurringFromBill(no),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            if (widget.leftOut case final note?) ...[
              const SizedBox(height: BlTokens.space2),
              Text(note, style: TextStyle(fontSize: 13, color: t.warning)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recurringItems),
            const SizedBox(height: BlTokens.space2),
            for (var i = 0; i < _lines.length; i++)
              _LineRow(
                key: ObjectKey(_qty[i]),
                line: _lines[i],
                controller: _qty[i],
                gone:
                    _lines[i].itemId != null &&
                    _gone.contains(_lines[i].itemId),
                onRemove: () => _remove(i),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: BlButton(
                label: s.recurringAddItem,
                icon: Icons.add,
                kind: BlButtonKind.ghost,
                onPressed: () => unawaited(_addItem()),
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recurringEvery),
            const SizedBox(height: BlTokens.space2),
            chips<RepeatKind>(
              [
                (RepeatKind.daily, s.recurringDaily),
                (RepeatKind.weekly, s.recurringWeekly),
                (RepeatKind.monthly, s.recurringMonthly),
                (RepeatKind.everyDays, s.recurringEveryFewDays),
              ],
              _kind,
              (k) => _kind = k,
            ),
            const SizedBox(height: BlTokens.space2),
            if (_kind == RepeatKind.weekly)
              chips<int>(
                [for (var d = 1; d <= 7; d++) (d, weekdayName(s, d))],
                _weekday,
                (d) => _weekday = d,
              ),
            if (_kind == RepeatKind.monthly)
              BlField(
                controller: _date,
                label: s.recurringDateField,
                numeric: true,
                decimals: 0,
              ),
            if (_kind == RepeatKind.everyDays)
              BlField(
                controller: _days,
                label: s.recurringDaysField,
                numeric: true,
                decimals: 0,
              ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recurringStart),
            const SizedBox(height: BlTokens.space2),
            dateButton(_start, (d) => _start = d),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recurringEnds),
            const SizedBox(height: BlTokens.space2),
            chips<_Ends>(
              [
                (_Ends.never, s.recurringEndNever),
                (_Ends.onDate, s.recurringEndOn),
                (_Ends.times, s.recurringEndTimes),
              ],
              _ends,
              (e) {
                _ends = e;
                // A month from the start until a day is picked.
                if (e == _Ends.onDate) _endOn ??= _start.addDays(30);
              },
            ),
            const SizedBox(height: BlTokens.space2),
            if (_ends == _Ends.onDate) dateButton(_endOn, (d) => _endOn = d),
            if (_ends == _Ends.times)
              BlField(
                controller: _times,
                label: s.recurringTimesField,
                numeric: true,
                decimals: 0,
              ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recurringPrices),
            const SizedBox(height: BlTokens.space2),
            chips<RecurringPrices>(
              [
                (RecurringPrices.today, s.recurringPricesToday),
                (RecurringPrices.fixed, s.recurringPricesFixed),
              ],
              _prices,
              (p) => _prices = p,
            ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.recurringMaking),
            const SizedBox(height: BlTokens.space2),
            chips<RecurringMode>(
              [
                (RecurringMode.remind, s.recurringModeRemind),
                (RecurringMode.automatic, s.recurringModeAuto),
              ],
              _mode,
              (m) => _mode = m,
            ),
            const SizedBox(height: BlTokens.space1),
            Text(
              _mode == RecurringMode.automatic
                  ? s.recurringModeAutoHint
                  : s.recurringModeRemindHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.recurringSave,
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

/// One line: what, how many, and a way off.
class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.controller,
    required this.gone,
    required this.onRemove,
  });

  final RecurringLine line;
  final TextEditingController controller;
  final bool gone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: gone ? t.inkMuted : t.ink,
                  ),
                ),
                if (gone)
                  BlChip(
                    s.recurringItemGone,
                    tone: BlChipTone.bad,
                    icon: Icons.warning_amber_outlined,
                  ),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          SizedBox(
            width: 120,
            child: BlField(
              controller: controller,
              label: line.unitCode.isEmpty
                  ? s.recurringQty
                  : '${s.recurringQty} (${line.unitCode})',
              numeric: true,
              decimals: 3,
            ),
          ),
          BlIconButton(
            icon: Icons.close,
            label: s.recurringRemoveLine(line.name),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
