import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../documents/document_screen.dart';
import '../pos/pos_screen.dart';
import '../purchases/purchase_screen.dart';
import '../sales/send_bill.dart';
import '../sales/send_sheet.dart';
import 'order_form_screen.dart' show AdvanceModes;
import 'order_providers.dart';
import 'sale_order_to_cart.dart';
import 'send_order.dart';

/// One order, opened (M41): what was asked for, what of it has come in or
/// gone out, what came of it, and what can be done about the rest.
///
/// A purchase order is received here — "Maal aa gaya" opens the delivery
/// with the order's lines and rates in it — and sent to the supplier on
/// WhatsApp as a list they can read. A sale order is taken to the counter,
/// to be billed there, and an advance is taken on it.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  final _reason = TextEditingController();
  bool _busy = false;
  bool _confirmingCancel = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _sendText(OrderView view) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final services = ref.read(appServicesProvider);
      final text = await services.orders.purchaseOrderText(view.row.id);
      if (text == null) return;
      final outcome = await sendOrderText(
        text,
        number: await services.orders.whatsappFor(view.row.id),
      );
      if (outcome != OrderSendOutcome.chat) {
        messenger.showSnackBar(SnackBar(content: Text(s.sendNoNumber)));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPdf(OrderView view) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final services = ref.read(appServicesProvider);
      final doc = await OutgoingDocument.load(services, view.row.id);
      if (doc != null) await sharePdf(services, doc);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toCounter(OrderView view) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final problem = await takeSaleOrderToCounter(ref, s, view);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = problem;
    });
    if (problem == null) {
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const PosScreen()),
        ),
      );
    }
  }

  Future<void> _cancel(OrderView view) async {
    if (_busy) return;
    if (!_confirmingCancel) {
      setState(() => _confirmingCancel = true);
      return;
    }
    final s = AppStrings.of(context);
    if (_reason.text.trim().isEmpty) {
      setState(() => _failure = s.orderCancelNeedsReason);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .orders
          .cancel(view.row.id, reason: _reason.text);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.orderCancelled)));
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmingCancel = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is OrderRefused ? error.reason : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final view = ref.watch(orderViewProvider(widget.orderId));
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(view.valueOrNull?.row.docNo ?? '')),
      body: SafeArea(
        child: view.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 5),
          ),
          error: (error, _) => BlError(
            title: s.commonSomethingWentWrong,
            message: '$error',
            retryLabel: s.actionRetry,
            onRetry: () => ref.invalidate(orderViewProvider(widget.orderId)),
          ),
          data: (v) => v == null
              ? Center(child: BlEmpty(title: s.commonNothingSaved))
              : _body(context, s, t, v, today),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppStrings s,
    BlTokens t,
    OrderView v,
    BusinessDate today,
  ) {
    final row = v.row;
    final buying = row.kind == OrderKind.purchase;
    final (label, tone) = orderStatusChip(s, row, today);
    final standing = row.status.isStanding;
    return ListView(
      padding: const EdgeInsets.all(BlTokens.space4),
      children: [
        BlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.partyName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              Text(
                [
                  row.date.value,
                  if (row.dueDate != null) s.orderDue(row.dueDate!.value),
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space1,
                children: [
                  BlChip(label, tone: tone),
                  if (row.advance.isPositive)
                    BlChip(
                      s.orderAdvance(row.advance.amountOnly),
                      tone: BlChipTone.good,
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.purchaseTotal,
                      style: TextStyle(fontSize: 14, color: t.inkMuted),
                    ),
                  ),
                  BlMoney(row.total, size: 16),
                ],
              ),
              if (standing && v.pendingValue != row.total)
                Text(
                  s.orderStillToCome(v.pendingValue.amountOnly),
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
            ],
          ),
        ),
        const SizedBox(height: BlTokens.space3),
        for (final l in v.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: BlTokens.space2),
            child: BlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.itemName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    '${l.qty.display} ${l.unitCode} x ${l.rate.amountOnly}',
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  if (l.done.isPositive || standing)
                    Text(
                      buying
                          ? s.orderLineIn(
                              l.done.display,
                              l.pendingBase.display,
                              l.baseUnitCode,
                            )
                          : s.orderLineOut(
                              l.done.display,
                              l.pendingBase.display,
                              l.baseUnitCode,
                            ),
                      style: TextStyle(
                        fontSize: 13,
                        color: l.isDone ? t.accent : t.ink,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (v.notes != null && v.notes!.trim().isNotEmpty) ...[
          Text(v.notes!, style: TextStyle(fontSize: 14, color: t.inkMuted)),
          const SizedBox(height: BlTokens.space2),
        ],
        if (v.followUps.isNotEmpty) ...[
          BlSectionHeader(s.orderFollowUps),
          const SizedBox(height: BlTokens.space2),
          for (final f in v.followUps)
            Padding(
              padding: const EdgeInsets.only(bottom: BlTokens.space2),
              child: BlCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentScreen(
                      documentId: f.documentId,
                      docNo: f.docNo,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${f.docNo} · ${f.date.value}',
                        style: TextStyle(fontSize: 14, color: t.ink),
                      ),
                    ),
                    BlMoney(f.total, size: 14),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: BlTokens.space3),
        if (buying && standing) ...[
          BlButton(
            label: s.orderReceive,
            icon: Icons.move_to_inbox_outlined,
            big: true,
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PurchaseScreen(fromOrder: v),
                    ),
                  ),
          ),
          const SizedBox(height: BlTokens.space2),
        ],
        if (buying) ...[
          BlButton(
            label: s.sendWhatsApp,
            icon: Icons.chat_outlined,
            kind: BlButtonKind.secondary,
            onPressed: _busy ? null : () => unawaited(_sendText(v)),
          ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.quotationSharePdf,
            icon: Icons.picture_as_pdf_outlined,
            kind: BlButtonKind.secondary,
            onPressed: _busy ? null : () => unawaited(_sendPdf(v)),
          ),
        ] else ...[
          if (standing) ...[
            BlButton(
              label: s.orderToCounter,
              icon: Icons.point_of_sale_outlined,
              big: true,
              onPressed: _busy ? null : () => unawaited(_toCounter(v)),
            ),
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.orderTakeAdvance,
              icon: Icons.payments_outlined,
              kind: BlButtonKind.secondary,
              onPressed: _busy
                  ? null
                  : () => unawaited(showAdvanceSheet(context, v)),
            ),
            const SizedBox(height: BlTokens.space2),
          ],
          SendButtons(
            documentId: v.row.id,
            onFailure: (message) {
              if (mounted) setState(() => _failure = message);
            },
          ),
        ],
        if (standing) ...[
          const SizedBox(height: BlTokens.space4),
          if (_confirmingCancel) ...[
            Text(
              s.orderCancelConfirm(row.docNo),
              style: TextStyle(fontSize: 14, color: t.ink),
            ),
            const SizedBox(height: BlTokens.space2),
            BlField(controller: _reason, label: s.orderCancelReason),
            const SizedBox(height: BlTokens.space2),
          ],
          BlButton(
            label: s.orderCancel,
            icon: Icons.block,
            kind: BlButtonKind.danger,
            onPressed: _busy ? null : () => unawaited(_cancel(v)),
          ),
        ],
        if (_failure != null) ...[
          const SizedBox(height: BlTokens.space3),
          Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
        ],
      ],
    );
  }
}

/// Takes an advance on sale order [view]: how much, and how it was paid.
Future<void> showAdvanceSheet(BuildContext context, OrderView view) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AdvanceSheet(view: view),
    );

class _AdvanceSheet extends ConsumerStatefulWidget {
  const _AdvanceSheet({required this.view});

  final OrderView view;

  @override
  ConsumerState<_AdvanceSheet> createState() => _AdvanceSheetState();
}

class _AdvanceSheetState extends ConsumerState<_AdvanceSheet> {
  final _amount = TextEditingController();
  String _mode = 'cash';
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final amount =
        Money.tryParse(_amount.text.trim().replaceAll(',', '')) ?? Money.zero;
    if (!amount.isPositive) {
      setState(() => _failure = s.wasooliAmountRequired);
      return;
    }
    final services = ref.read(appServicesProvider);
    final accounts = await services.queries.paymentAccounts(
      services.identity!.firmId,
    );
    final account = accounts.where((a) => a.modeLabel == _mode).firstOrNull;
    if (account == null) {
      setState(() => _failure = s.tenderNoAccount);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await services.orders.takeAdvance(
        widget.view.row.id,
        amount: amount,
        paymentAccountId: account.id,
        mode: _mode,
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.orderAdvanceTaken(amount.amountOnly))),
      );
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is OrderRefused ? error.reason : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.orderTakeAdvance,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          Text(
            '${widget.view.row.partyName} · ${widget.view.row.docNo}',
            style: TextStyle(fontSize: 14, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _amount,
            label: s.orderAdvanceAmount,
            numeric: true,
            autofocus: true,
            onChanged: (_) => setState(() => _failure = null),
          ),
          const SizedBox(height: BlTokens.space2),
          AdvanceModes(
            mode: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          if (_failure != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.orderTakeAdvance,
            icon: Icons.check,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
