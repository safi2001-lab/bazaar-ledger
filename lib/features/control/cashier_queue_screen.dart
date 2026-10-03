import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/when.dart';
import '../parties/party_picker.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart';
import '../pos/scheme_book.dart';
import 'control_providers.dart';

/// Cashier mode (M68): the cashier's queue of bills the salesmen made, and
/// the salesman's sheet that sends one there.
///
/// A held bill is taken onto the cashier's counter the way a quotation is
/// (M25): its lines at the prices it was made at, its customer, and a note
/// of where it came from; the cashier takes the money on the payment sheet
/// as for any bill, and the bill is made then -- stock and the books move at
/// that moment, never before. See `cashier_mode.dart` in the domain.
class CashierQueueScreen extends ConsumerStatefulWidget {
  const CashierQueueScreen({super.key});

  @override
  ConsumerState<CashierQueueScreen> createState() => _CashierQueueScreenState();
}

class _CashierQueueScreenState extends ConsumerState<CashierQueueScreen> {
  bool _busy = false;
  String? _failure;

  /// Puts [held] on this counter and opens it, to take the money.
  Future<void> _pay(HeldBill held) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    try {
      final services = ref.read(appServicesProvider);
      final firm = (await ref.read(firmProvider.future))!;
      final lines = <(ItemSummary, QuotedLine)>[];
      for (final line in await services.cashier.linesOf(held.id)) {
        final item = await services.queries.itemById(firm.id, line.itemId);
        if (item == null) throw StateError(s.quotationItemGone);
        lines.add((item, line));
      }
      final party = held.partyId == null
          ? null
          : await services.queries.partyById(firm.id, held.partyId!);
      final notifier = ref.read(cartProvider.notifier)
        ..loadQuotation(
          QuotationRow(
            id: held.id,
            docNo: held.docNo,
            date: BusinessDate.fromUtc(
              DateTime.fromMillisecondsSinceEpoch(
                held.madeAtUtcMillis,
                isUtc: true,
              ),
            ),
            total: held.total,
            partyId: held.partyId,
            partyName: held.partyName,
            docType: heldBillDocType,
          ),
          lines,
          party: party,
        );
      // The salesman's own discount on the bill comes with it.
      if (held.billDiscount.isPositive) {
        notifier.setBillDiscount(held.billDiscount);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const PosScreen()),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is StateError ? error.message : '$error';
        });
      }
    }
  }

  Future<void> _drop(HeldBill held) async {
    final s = AppStrings.of(context);
    final reason = TextEditingController();
    final why = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cashierDrop),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: InputDecoration(labelText: s.stockCheckReasonLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(reason.text),
            child: Text(s.cashierDrop),
          ),
        ],
      ),
    );
    reason.dispose();
    if (why == null || why.trim().isEmpty || !mounted) return;
    setState(() => _failure = null);
    try {
      await ref.read(appServicesProvider).cashier.drop(held.id, why);
      if (mounted) ref.bumpRefresh();
    } on ApprovalNeeded {
      // Data Lock's PIN was not given: the bill stays in the queue.
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final queue = ref.watch(heldQueueProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.cashierQueueTitle)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.bumpRefresh(),
          child: queue.when(
            loading: () => const BlSkeletonList(rows: 3),
            error: (error, _) => Center(
              child: Text('$error', style: TextStyle(color: t.danger)),
            ),
            data: (bills) => bills.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: BlTokens.space8),
                      BlEmpty(
                        title: s.cashierQueueEmpty,
                        icon: Icons.point_of_sale_outlined,
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(BlTokens.space4),
                    children: [
                      if (_failure != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: BlTokens.space3,
                          ),
                          child: Text(
                            _failure!,
                            style: TextStyle(fontSize: 13, color: t.danger),
                          ),
                        ),
                      for (final held in bills)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: BlTokens.space3,
                          ),
                          child: _HeldCard(
                            held: held,
                            busy: _busy,
                            onPay: () => unawaited(_pay(held)),
                            onDrop: () => unawaited(_drop(held)),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _HeldCard extends StatelessWidget {
  const _HeldCard({
    required this.held,
    required this.busy,
    required this.onPay,
    required this.onDrop,
  });

  final HeldBill held;
  final bool busy;
  final VoidCallback onPay;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final at = shopTime(held.madeAtUtcMillis);
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      held.partyName ?? s.posWalkInCustomer,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      '${held.docNo} - ${s.stockCheckItems(held.lineCount)}',
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                    Text(
                      s.cashierMadeBy(
                        held.madeByName,
                        at.substring(at.length - 5),
                      ),
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              BlMoney(held.total, size: 18, weight: FontWeight.w700),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.cashierTakeMoney,
            icon: Icons.payments_outlined,
            busy: busy,
            onPressed: busy ? null : onPay,
          ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.cashierDrop,
            kind: BlButtonKind.ghost,
            onPressed: busy ? null : onDrop,
          ),
        ],
      ),
    );
  }
}

/// The salesman's checkout: the bill sent to the cashier, written to the
/// books as a held bill before the counter is cleared, so nothing is lost
/// if the phone dies the moment after.
class HoldForCashierSheet extends ConsumerStatefulWidget {
  const HoldForCashierSheet({super.key});

  @override
  ConsumerState<HoldForCashierSheet> createState() =>
      _HoldForCashierSheetState();
}

class _HoldForCashierSheetState extends ConsumerState<HoldForCashierSheet> {
  bool _busy = false;
  String? _failure;

  Future<void> _send() async {
    // Before any await, as the payment sheet guards its own Save.
    if (_busy) return;
    final s = AppStrings.of(context);
    final cart = ref.read(cartProvider);
    final firm = ref.read(firmProvider).valueOrNull;
    final units = ref.read(unitConverterProvider).valueOrNull;
    if (firm == null || cart.isEmpty) return;
    if (cart.lines.any((l) => l.isLoose)) {
      setState(() => _failure = s.looseNotKept);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cartNotifier = ref.read(cartProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      final books = cart.forBooks(units, schemesFor(ref), points: false);
      final held = await services.cashier.hold(
        SaleDraft(
          lines: books.lines,
          partyId: cart.partyId,
          partyName: cart.partyName,
          billDiscount: books.billDiscount,
          roundToRupee: firm.roundInvoiceToRupee,
          locationCode: await services.counterLocation(),
        ),
      );
      // Committed: only now is the counter cleared.
      cartNotifier.clear();
      container.read(refreshTickProvider.notifier).update((n) => n + 1);
      messenger.showSnackBar(
        SnackBar(content: Text(s.cashierSent(held.docNo))),
      );
      navigator.popUntil((route) => route.isFirst);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cart = ref.watch(cartProvider);
    final preview = ref.watch(cartPreviewProvider);
    if (preview == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    s.cashierHoldTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                const Spacer(),
                BlIconButton(
                  icon: Icons.close,
                  label: s.actionClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlCard(
              accent: true,
              child: BlAmountRow(
                label: s.posTotal,
                labelStyle: TextStyle(fontSize: 14, color: t.inkMuted),
                child: BlMoney(
                  preview.total,
                  size: 28,
                  weight: FontWeight.w700,
                  withSymbol: true,
                  semanticPrefix: s.posTotal,
                ),
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            // Who it is for, picked here as on the payment sheet.
            InkWell(
              onTap: () async {
                final party = await showModalBottomSheet<PartySummary?>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const PartyPicker(newPartyType: 'customer'),
                );
                if (party != null) {
                  ref
                      .read(cartProvider.notifier)
                      .setParty(
                        party,
                        units: ref.read(unitConverterProvider).valueOrNull,
                      );
                }
              },
              borderRadius: BorderRadius.circular(BlTokens.radiusMd),
              child: Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20, color: t.inkMuted),
                    const SizedBox(width: BlTokens.space3),
                    Expanded(
                      child: Text(
                        cart.partyName ?? s.posWalkInCustomer,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            Text(
              s.cashierHoldHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.cashierSendToCashier,
              icon: Icons.send_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_send()),
            ),
          ],
        ),
      ),
    );
  }
}
