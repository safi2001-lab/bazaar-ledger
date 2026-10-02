import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_picker.dart';
import 'order_item_sheet.dart';
import 'order_providers.dart';
import 'order_screen.dart';

/// Writing an order down (M41): a purchase order to a supplier, or a
/// customer's order.
///
/// A purchase order is the list the order-booker used to write in his diary
/// on Tuesday: what, how many, at what rate, and by when. A sale order is
/// the wholesale customer's "do bori cheeni Jumme ko", lighter than a
/// quotation — items, quantities, the day promised, and whatever they paid
/// down, which goes on their khata as an advance the bill takes later.
class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key, required this.kind});

  final OrderKind kind;

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _due = TextEditingController();
  final _note = TextEditingController();
  final _advance = TextEditingController();
  final _lines = <OrderLineDraft>[];
  PartySummary? _party;
  String _mode = 'cash';
  bool _busy = false;
  String? _failure;

  bool get _buying => widget.kind == OrderKind.purchase;

  @override
  void dispose() {
    _due.dispose();
    _note.dispose();
    _advance.dispose();
    super.dispose();
  }

  Money get _total => Money.sum([for (final l in _lines) l.lineTotal]);
  Money get _advanceAmount =>
      Money.tryParse(_advance.text.trim().replaceAll(',', '')) ?? Money.zero;

  Future<void> _pickParty() async {
    final party = await showModalBottomSheet<PartySummary?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          PartyPicker(newPartyType: _buying ? 'supplier' : 'customer'),
    );
    if (party != null && mounted) {
      setState(() {
        _party = party;
        _failure = null;
      });
    }
  }

  Future<void> _addLine() async {
    final line = await showOrderItemSheet(
      context,
      kind: widget.kind,
      partyId: _party?.id,
      tier: _party?.priceTier ?? PriceTier.retail,
    );
    if (line != null && mounted) {
      setState(() {
        _lines.add(line);
        _failure = null;
      });
    }
  }

  void _dueIn(int days) {
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    setState(() => _due.text = today.addDays(days).value);
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final party = _party;
    if (party == null) {
      setState(() => _failure = s.orderPartyRequired);
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _failure = s.purchaseNoLines);
      return;
    }
    final dueText = _due.text.trim();
    final due = dueText.isEmpty ? null : typedDate(dueText);
    if (dueText.isNotEmpty && due == null) {
      setState(() => _failure = s.orderDueInvalid);
      return;
    }
    final services = ref.read(appServicesProvider);
    String? accountId;
    if (!_buying && _advanceAmount.isPositive) {
      final accounts = await services.queries.paymentAccounts(
        services.identity!.firmId,
      );
      accountId = accounts
          .where((a) => a.modeLabel == _mode)
          .map((a) => a.id)
          .firstOrNull;
      if (accountId == null) {
        setState(() => _failure = s.tenderNoAccount);
        return;
      }
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final placed = await services.orders.place(
        OrderDraft(
          kind: widget.kind,
          partyId: party.id,
          partyName: party.name,
          lines: List.of(_lines),
          dueDate: due,
          notes: _note.text,
        ),
      );
      // The advance is a receipt of its own, after the order it names.
      if (accountId != null) {
        await services.orders.takeAdvance(
          placed.id,
          amount: _advanceAmount,
          paymentAccountId: accountId,
          mode: _mode,
        );
      }
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.orderSaved(placed.docNo))),
      );
      unawaited(
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => OrderScreen(orderId: placed.id),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error is OrderRefused ? error.reason : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(_buying ? s.orderNewPurchase : s.orderNewSale),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
                ),
                children: [
                  BlCard(
                    onTap: () => unawaited(_pickParty()),
                    child: Row(
                      children: [
                        Icon(
                          _buying
                              ? Icons.local_shipping_outlined
                              : Icons.person_outline,
                          size: 20,
                          color: t.inkMuted,
                        ),
                        const SizedBox(width: BlTokens.space3),
                        Expanded(
                          child: Text(
                            _party?.name ??
                                (_buying
                                    ? s.purchaseSupplier
                                    : s.orderCustomer),
                            style: TextStyle(
                              fontSize: 15,
                              color: _party == null ? t.inkMuted : t.ink,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 20, color: t.inkFaint),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  if (_lines.isEmpty)
                    BlEmpty(
                      icon: Icons.playlist_add,
                      title: s.purchaseNoLines,
                      message: s.orderNoLinesHint,
                    )
                  else
                    for (var i = 0; i < _lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: BlCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _lines[i].itemName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: t.ink,
                                      ),
                                    ),
                                    Text(
                                      '${_lines[i].qty.display} '
                                      '${_lines[i].unitCode} x '
                                      '${_lines[i].rate.amountOnly}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: t.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              BlMoney(_lines[i].lineTotal, size: 15),
                              BlIconButton(
                                icon: Icons.close,
                                label: s.actionDelete,
                                onPressed: () =>
                                    setState(() => _lines.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: BlTokens.space2),
                  BlButton(
                    label: s.purchaseAddItem,
                    icon: Icons.add,
                    kind: BlButtonKind.secondary,
                    onPressed: () => unawaited(_addLine()),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  BlField(
                    controller: _due,
                    label: _buying ? s.orderDueExpected : s.orderDuePromised,
                    hint: 'YYYY-MM-DD',
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Wrap(
                    spacing: BlTokens.space2,
                    children: [
                      ActionChip(
                        label: Text(s.orderDueTomorrow),
                        onPressed: () => _dueIn(1),
                      ),
                      ActionChip(
                        label: Text(s.orderDueInDays(3)),
                        onPressed: () => _dueIn(3),
                      ),
                      ActionChip(
                        label: Text(s.orderDueInDays(7)),
                        onPressed: () => _dueIn(7),
                      ),
                    ],
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(controller: _note, label: s.orderNote, maxLines: 2),
                  if (!_buying) ...[
                    const SizedBox(height: BlTokens.space3),
                    BlField(
                      controller: _advance,
                      label: s.orderAdvanceAmount,
                      numeric: true,
                      onChanged: (_) => setState(() => _failure = null),
                    ),
                    if (_advanceAmount.isPositive) ...[
                      const SizedBox(height: BlTokens.space2),
                      AdvanceModes(
                        mode: _mode,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                    ],
                  ],
                  const SizedBox(height: BlTokens.space4),
                  BlCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.purchaseTotal,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ),
                        BlMoney(_total, size: 18, withSymbol: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: t.surface,
              padding: EdgeInsets.only(
                left: BlTokens.space4,
                right: BlTokens.space4,
                top: BlTokens.space3,
                bottom:
                    BlTokens.space3 +
                    (MediaQuery.viewInsetsOf(context).bottom > 0
                        ? 0
                        : MediaQuery.viewPaddingOf(context).bottom),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null) ...[
                    Text(
                      _failure!,
                      style: TextStyle(color: t.danger, fontSize: 14),
                    ),
                    const SizedBox(height: BlTokens.space2),
                  ],
                  BlButton(
                    label: s.orderSave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy ? null : () => unawaited(_save()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How an advance was paid: the ways money comes in at a counter, short of
/// a cheque, which has its own road through the khata.
class AdvanceModes extends StatelessWidget {
  const AdvanceModes({super.key, required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      children: [
        for (final (value, label) in [
          ('cash', s.tenderModeCash),
          ('jazzcash', s.tenderModeJazzCash),
          ('easypaisa', s.tenderModeEasypaisa),
          ('bank_transfer', s.tenderModeBank),
        ])
          ChoiceChip(
            label: Text(label),
            selected: mode == value,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}
