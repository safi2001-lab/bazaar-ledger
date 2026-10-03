import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart';
import '../pos/scheme_book.dart';
import '../pos/shelf_guard.dart';
import '../sales/receipt_screen.dart';

/// "Qist par bechein": the payment sheet's way to sell what is on the
/// counter on instalments (M50), for a mobile or electronics shop.
///
/// One button on the payment sheet, and the whole of the qist here, so the
/// payment sheet carries one marked line. Not offered while billing a
/// quotation or challan, or putting a cancelled bill right: those bills are
/// what they were.
class QistButton extends ConsumerWidget {
  const QistButton({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firm = ref.watch(firmProvider).valueOrNull;
    final cart = ref.watch(cartProvider);
    final sells =
        firm != null &&
        (firm.isMobileShop || firm.businessKind == 'electronics');
    if (!sells || cart.sourceId != null || cart.replacesId != null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: BlButton(
        label: AppStrings.of(context).mobileQistSell,
        icon: Icons.calendar_month_outlined,
        kind: BlButtonKind.secondary,
        onPressed: enabled
            ? () => unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const QistSheet(),
                ),
              )
            : null,
      ),
    );
  }
}

/// The qist terms for the bill on the counter, the schedule they make, and
/// the sale itself.
///
/// The bill is an ordinary bill: the phone at its price, the markup (when
/// the shop charges one) as a charge on the same bill in plain sight, the
/// down payment taken in cash, and the rest on the customer's khata, due
/// instalment by instalment. The schedule shown here is the one the books
/// write: whole rupees, whatever does not divide evenly on the last.
class QistSheet extends ConsumerStatefulWidget {
  const QistSheet({super.key});

  @override
  ConsumerState<QistSheet> createState() => _QistSheetState();
}

class _QistSheetState extends ConsumerState<QistSheet> {
  final _down = TextEditingController();
  final _markup = TextEditingController();
  final _count = TextEditingController(text: '10');
  final _day = TextEditingController();
  final _guarantor = TextEditingController();
  final _guarantorCnic = TextEditingController();
  final _guarantorPhone = TextEditingController();
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    // The day of the month the phone is sold on, as the shop usually keeps
    // it; never past the 28th, which every month has.
    _day.text = '${today.day > 28 ? 28 : today.day}';
  }

  @override
  void dispose() {
    for (final c in [
      _down,
      _markup,
      _count,
      _day,
      _guarantor,
      _guarantorCnic,
      _guarantorPhone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whole rupees, as a shop says them.
  Money _rupees(TextEditingController c) =>
      (Money.tryParse(c.text) ?? Money.zero).roundToRupee();

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _sell(Money phones) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final cart = ref.read(cartProvider);
    final services = ref.read(appServicesProvider);
    final firm = ref.read(firmProvider).valueOrNull;
    final units = ref.read(unitConverterProvider).valueOrNull;
    final count = _int(_count) ?? 0;
    final day = _int(_day) ?? 0;
    final down = _rupees(_down);
    final markup = _rupees(_markup);
    final total = phones + markup;
    final problem = cart.partyId == null
        ? s.mobileQistNeedsCustomer
        : count < 1 || count > QistPlanDraft.maxInstalments
        ? s.mobileQistCountBad(QistPlanDraft.maxInstalments)
        : day < 1 || day > 31
        ? s.mobileQistDayBad
        : down.isNegative || down >= total
        ? s.mobileQistDownBad
        : _guarantorCnic.text.trim().isNotEmpty &&
              !cnicWellFormed(_guarantorCnic.text)
        ? s.mobileCnicBad
        : null;
    if (problem != null || firm == null) {
      setState(() => _failure = problem);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    if (!await shelfAllowsBill(context, ref, cart)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cartNotifier = ref.read(cartProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    final today = BusinessDate.now(services.clock);
    try {
      final books = cart.forBooks(units, schemesFor(ref));
      final location = await services.counterLocation();
      final accounts = await services.queries.paymentAccounts(firm.id);
      final cash = accounts.where((a) => a.modeLabel == 'cash').firstOrNull;
      if (down.isPositive && cash == null) {
        setState(() {
          _failure = s.tenderNoAccount;
          _busy = false;
        });
        return;
      }
      final name = _guarantor.text.trim();
      // M66: the customer's points chosen on the payment sheet are spent
      // in the bill's own commit, as on any bill.
      final sale = services.loyalty.postSaleFor(
        redeem: cart.pointsOff.isPositive ? cart.loyalty : null,
      );
      final posted = await sale(
        services.actorNow(),
        SaleDraft(
          locationCode: location,
          lines: books.lines,
          partyId: cart.partyId,
          partyName: cart.partyName,
          tenders: [
            if (down.isPositive)
              TenderDraft(
                paymentAccountId: cash!.id,
                mode: 'cash',
                amount: down,
              ),
          ],
          billDiscount: books.billDiscount,
          roundToRupee: firm.roundInvoiceToRupee,
          extraCharges: markup,
          qist: QistPlanDraft(
            count: count,
            dueDay: day,
            firstDue: firstDueAfter(today, day),
            guarantor: name.isEmpty
                ? null
                : Guarantor(
                    name: name,
                    cnic: _guarantorCnic.text,
                    phone: _guarantorPhone.text,
                  ),
          ),
        ),
      );
      await services.fbr.afterSale(posted.documentId);
      unawaited(services.fbr.sendPending());
      cartNotifier.clear();
      container.read(posQueryProvider.notifier).state = '';
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.billSaved(posted.docNo))),
      );
      navigator.popUntil((route) => route.isFirst);
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReceiptScreen(documentId: posted.documentId, docNo: posted.docNo),
        ),
      );
    } on QistRefused catch (refused) {
      if (mounted) {
        setState(() {
          _failure = refused.reason;
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '${s.billSaveFailed}\n\n$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cart = ref.watch(cartProvider);
    final preview = ref.watch(cartPreviewByProvider(null));
    final services = ref.watch(appServicesProvider);
    if (preview == null) return const SizedBox.shrink();
    final today = BusinessDate.now(services.clock);
    final phones = preview.total;
    final markup = _rupees(_markup);
    final total = phones + markup;
    final down = _rupees(_down);
    final financed = total - down;
    final count = _int(_count) ?? 0;
    final day = _int(_day) ?? 0;
    final schedule =
        financed.isPositive &&
            count >= 1 &&
            count <= QistPlanDraft.maxInstalments &&
            day >= 1 &&
            day <= 31 &&
            financed.inPaisa >= count
        ? scheduleInstalments(
            financed: financed,
            count: count,
            firstDue: firstDueAfter(today, day),
            dueDay: day,
          )
        : null;

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
                Expanded(
                  child: Text(
                    s.mobileQistSell,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                BlIconButton(
                  icon: Icons.close,
                  label: s.actionClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              cart.partyName ?? s.mobileQistNeedsCustomer,
              style: TextStyle(
                fontSize: 14,
                color: cart.partyId == null ? t.danger : t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            BlAmountRow(label: s.mobileQistPhones, child: BlMoney(phones)),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _markup,
              label: s.mobileQistMarkup,
              hint: '0',
              numeric: true,
              onChanged: (_) => setState(() => _failure = null),
            ),
            const SizedBox(height: BlTokens.space1),
            Text(
              s.mobileQistMarkupNote,
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _down,
              label: s.mobileQistDown,
              hint: '0',
              numeric: true,
              onChanged: (_) => setState(() => _failure = null),
            ),
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: BlField(
                    controller: _count,
                    label: s.mobileQistCount,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                ),
                const SizedBox(width: BlTokens.space3),
                Expanded(
                  child: BlField(
                    controller: _day,
                    label: s.mobileQistDay,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BlAmountRow(
                    label: s.mobileQistBillTotal,
                    child: BlMoney(total),
                  ),
                  BlAmountRow(label: s.mobileQistDownNow, child: BlMoney(down)),
                  BlAmountRow(
                    label: s.mobileQistOnQist,
                    child: BlMoney(financed),
                  ),
                  if (schedule != null) ...[
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      _scheduleWords(s, schedule),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      s.mobileQistFromTo(
                        printedDate(schedule.first.dueOn),
                        printedDate(schedule.last.dueOn),
                      ),
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.mobileQistGuarantor),
            const SizedBox(height: BlTokens.space2),
            BlField(controller: _guarantor, label: s.mobileQistGuarantorName),
            const SizedBox(height: BlTokens.space2),
            BlField(
              controller: _guarantorCnic,
              label: s.mobileQistGuarantorCnic,
              hint: '35202-1234567-1',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: BlTokens.space2),
            BlField(
              controller: _guarantorPhone,
              label: s.mobileQistGuarantorPhone,
              keyboardType: TextInputType.phone,
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.mobileQistSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_sell(phones)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "10 x Rs 5,000" or "9 x Rs 5,000 + 1 x Rs 5,001".
String _scheduleWords(AppStrings s, List<Instalment> schedule) {
  final first = schedule.first.amount;
  final last = schedule.last.amount;
  return first == last
      ? s.mobileQistEach(schedule.length, first.amountOnly)
      : s.mobileQistEachLast(
          schedule.length - 1,
          first.amountOnly,
          last.amountOnly,
        );
}
