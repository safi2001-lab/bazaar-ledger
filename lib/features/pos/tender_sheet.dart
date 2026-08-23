import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_picker.dart';
import '../sales/receipt_screen.dart';
import 'cart.dart';
import 'pos_screen.dart';

/// Taking the money.
///
/// Every mode here is a label on a ledger row and nothing more. The customer
/// pays however they pay — cash in hand, EasyPaisa from their own phone, a
/// card on the bank's own machine — and the money never touches this app.
/// There is no API call behind any of these buttons, which is exactly why they
/// keep working during a national internet shutdown, and exactly what keeps
/// this product outside the SBP licensing perimeter.
class TenderSheet extends ConsumerStatefulWidget {
  const TenderSheet({super.key});

  @override
  ConsumerState<TenderSheet> createState() => _TenderSheetState();
}

class _TenderSheetState extends ConsumerState<TenderSheet> {
  final _tendered = TextEditingController();
  final _reference = TextEditingController();

  String _mode = 'cash';
  bool _onUdhaar = false;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _tendered.dispose();
    _reference.dispose();
    super.dispose();
  }

  Money get _tenderedAmount =>
      Money.tryParse(_tendered.text) ?? Money.zero;

  /// The account this tender posts into: one matching the chosen mode, else
  /// the shop's default, else nothing at all.
  PaymentAccountSummary? _accountFor(List<PaymentAccountSummary> accounts) {
    for (final a in accounts) {
      if (a.modeLabel == _mode) return a;
    }
    for (final a in accounts) {
      if (a.isDefault) return a;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  Future<void> _post() async {
    // The very first thing, before any await. `onPressed: _busy ? null :
    // _post` only disables the button once a frame has been built, so setting
    // this after the account read left a window in which two taps both
    // reached postSale and one cart became two invoices.
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final s = AppStrings.of(context);
    final preview = ref.read(cartPreviewProvider);
    final cart = ref.read(cartProvider);
    final firm = ref.read(firmProvider).valueOrNull;
    if (preview == null || firm == null) {
      setState(() => _busy = false);
      return;
    }

    // Anything left owing is somebody's khata, whether the switch was flipped
    // or the cash handed over simply fell short. There is no such thing as an
    // anonymous debtor.
    final leavesBalance = _onUdhaar ||
        (_mode == 'cash' &&
            !_tenderedAmount.isZero &&
            _tenderedAmount < preview.total);
    if (leavesBalance && cart.partyId == null) {
      setState(() {
        _failure = s.tenderUdhaarNeedsCustomer;
        _busy = false;
      });
      return;
    }

    // Held rather than reached for through `ref` after the write. A sheet that
    // is dismissed mid-post disposes its ConsumerState, and `ref.read` on a
    // disposed state throws — which the catch below would swallow, leaving a
    // committed sale with the cart still full. The shopkeeper then rings the
    // same bill again.
    final cartNotifier = ref.read(cartProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);

    // Read fresh rather than off the provider cache. A payment account can be
    // archived by the owner on another screen — or, with M13's LAN sync, by a
    // second counter — between this sheet opening and the shopkeeper tapping
    // save, and a tender pointing at a dead account must fail loudly here
    // rather than three layers down inside the transaction.
    List<PaymentAccountSummary> accounts;
    try {
      accounts = await ref
          .read(appServicesProvider)
          .queries
          .paymentAccounts(firm.id);
    } on Object catch (error) {
      // `_busy` has to come back down here too. Leaving it set showed the
      // shopkeeper an error message underneath a permanently dead Save
      // button, and the only way out was to dismiss the sheet and rebuild
      // the whole cart.
      if (mounted) {
        setState(() {
          _failure = '${s.billSaveFailed}\n\n$error';
          _busy = false;
        });
      }
      return;
    }

    final account = _onUdhaar ? null : _accountFor(accounts);
    if (!_onUdhaar && account == null) {
      // Nothing to post the money into. First run seeds a cash account, so
      // this means every account has been archived — which is recoverable,
      // and is said in words rather than thrown.
      if (mounted) {
        setState(() {
          _failure = s.tenderNoAccount;
          _busy = false;
        });
      }
      return;
    }

    // On udhaar there is no tender at all: the whole bill lands in the
    // customer's khata. Otherwise the shopkeeper is settling what they are
    // actually settling — which for cash is what the customer handed over,
    // capped at the bill. Posting `preview.total` regardless meant a cashier
    // who typed Rs 3,000 against a Rs 5,000 bill saw "Remaining 2,000" on
    // screen and then wrote a fully-paid Rs 5,000 receipt.
    final Money settling;
    if (_mode != 'cash' || _tenderedAmount.isZero) {
      settling = preview.total;
    } else {
      settling =
          _tenderedAmount < preview.total ? _tenderedAmount : preview.total;
    }

    final tenders = account == null
        ? const <TenderDraft>[]
        : [
            TenderDraft(
              paymentAccountId: account.id,
              mode: _mode,
              amount: settling,
              tendered: _mode == 'cash' && !_tenderedAmount.isZero
                  ? _tenderedAmount
                  : null,
              reference: _reference.text.trim().isEmpty
                  ? null
                  : _reference.text.trim(),
            ),
          ];

    if (!mounted) return;

    // Captured before anything is popped: a sheet's context is defunct the
    // moment it closes, and reaching through it afterwards is the classic way
    // to turn a successful sale into a crash.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final services = ref.read(appServicesProvider);
      final posted = await services.postSale(
        services.actorNow(),
        SaleDraft(
          lines: [for (final l in cart.lines) l.toDraft()],
          partyId: cart.partyId,
          partyName: cart.partyName,
          tenders: tenders,
          billDiscount: cart.billDiscount,
          roundToRupee: firm.roundInvoiceToRupee,
        ),
      );

      // Through the captured handles, not through `ref`: this runs whether or
      // not the sheet is still on screen, because the sale is committed and
      // the cart must not survive it.
      cartNotifier.clear();
      container.read(posQueryProvider.notifier).state = '';
      container.read(refreshTickProvider.notifier).update((n) => n + 1);

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(s.billSaved(posted.docNo))),
      );

      // The sheet, then the counter. What is left behind is the home screen
      // with the day's totals already bumped, and the receipt on top of it.
      navigator.pop();
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ReceiptScreen(
            documentId: posted.documentId,
            docNo: posted.docNo,
          ),
        ),
      );
    } on Object catch (error) {
      // Nothing was written: the whole posting is one transaction, so a
      // failure here leaves the books exactly as they were. The message says
      // so, because "did that go through?" is the question that makes a
      // shopkeeper ring the same bill twice.
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
    final preview = ref.watch(cartPreviewProvider);
    final cart = ref.watch(cartProvider);

    if (preview == null) return const SizedBox.shrink();

    final due = preview.total;
    // Change and shortfall only mean anything when cash is being counted out.
    // Switching from cash to card used to leave a stale "Change" row sitting
    // on the due card.
    final counting = !_onUdhaar && _mode == 'cash';
    final change = counting && _tenderedAmount > due
        ? _tenderedAmount - due
        : Money.zero;
    final short = counting && _tenderedAmount.isPositive && _tenderedAmount < due
        ? due - _tenderedAmount
        : Money.zero;

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
                Text(
                  s.tenderTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
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
            _DueCard(due: due, change: change, short: short),
            const SizedBox(height: BlTokens.space4),

            // Who is this bill for. A walk-in needs nobody, which is the
            // common case at a kiryana counter and must never be an obstacle.
            _CustomerRow(cart: cart),
            const SizedBox(height: BlTokens.space4),

            BlSectionHeader(s.tenderOnUdhaar),
            const SizedBox(height: BlTokens.space2),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _onUdhaar,
              title: Text(s.tenderOnUdhaar),
              subtitle: cart.partyId == null
                  ? Text(
                      s.tenderUdhaarNeedsCustomer,
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    )
                  : null,
              onChanged: (v) => setState(() => _onUdhaar = v),
            ),

            if (!_onUdhaar) ...[
              const SizedBox(height: BlTokens.space2),
              _ModePicker(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
              const SizedBox(height: BlTokens.space4),
              if (_mode == 'cash') ...[
                BlField(
                  controller: _tendered,
                  label: s.tenderTendered,
                  numeric: true,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: BlTokens.space2),
                _NoteShortcuts(
                  due: due,
                  onPick: (amount) {
                    _tendered.text = amount.amountOnly;
                    setState(() {});
                  },
                ),
              ] else
                BlField(
                  controller: _reference,
                  label: s.tenderReference,
                ),
              const SizedBox(height: BlTokens.space3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 15, color: t.inkFaint),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Text(
                      s.tenderManualNote,
                      style: TextStyle(fontSize: 12, color: t.inkFaint),
                    ),
                  ),
                ],
              ),
            ],

            // s.21(s), Finance Act 2025: 50% of an expenditure is disallowed
            // where a single invoice above Rs 200,000 is settled otherwise
            // than through a banking or digital channel. A warning, never a
            // block — it is the shopkeeper's call, and a sale is never
            // stopped by this app.
            if (preview.cashThresholdBreached && !_onUdhaar && _mode == 'cash')
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space3),
                child: BlOfflineNote(message: s.tenderCashThresholdWarning),
              ),

            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  color: t.dangerSurface,
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: t.danger),
                    const SizedBox(width: BlTokens.space2),
                    Expanded(
                      child: Text(
                        _failure!,
                        style: TextStyle(fontSize: 13, color: t.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: BlTokens.space5),
            // One button, and it does exactly what it says. There is no
            // "Save and Print" here until a printer transport exists in M2:
            // a button that announces work it does not do is the specific
            // failure this rebuild was called for. The receipt opens straight
            // after saving, and the PDF can be sent from there today.
            BlButton(
              label: s.actionSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : _post,
            ),
          ],
        ),
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({
    required this.due,
    required this.change,
    required this.short,
  });

  final Money due;
  final Money change;
  final Money short;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return BlCard(
      accent: true,
      child: Column(
        children: [
          Row(
            children: [
              Text(
                s.tenderDue,
                style: TextStyle(fontSize: 14, color: t.inkMuted),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: BlMoney(
                  due,
                  size: 30,
                  weight: FontWeight.w700,
                  withSymbol: true,
                  semanticPrefix: s.tenderDue,
                ),
              ),
            ],
          ),
          if (!change.isZero) ...[
            const Divider(height: BlTokens.space5),
            Row(
              children: [
                Text(
                  s.tenderChange,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.money,
                  ),
                ),
                const Spacer(),
                BlMoney(
                  change,
                  size: 24,
                  weight: FontWeight.w700,
                  colour: t.money,
                  semanticPrefix: s.tenderChange,
                ),
              ],
            ),
          ] else if (!short.isZero) ...[
            const Divider(height: BlTokens.space5),
            Row(
              children: [
                Text(
                  s.tenderRemaining,
                  style: TextStyle(fontSize: 14, color: t.warning),
                ),
                const Spacer(),
                BlMoney(
                  short,
                  size: 18,
                  colour: t.warning,
                  semanticPrefix: s.tenderRemaining,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerRow extends ConsumerWidget {
  const _CustomerRow({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return InkWell(
      onTap: () async {
        final party = await showModalBottomSheet<PartySummary?>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const PartyPicker(),
        );
        if (party != null) {
          ref.read(cartProvider.notifier).setParty(party.id, party.name);
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
                  color: cart.partyName == null ? t.inkMuted : t.ink,
                ),
              ),
            ),
            if (cart.partyId != null)
              BlIconButton(
                icon: Icons.close,
                label: s.actionClose,
                onPressed: () =>
                    ref.read(cartProvider.notifier).setParty(null, null),
              )
            else
              Text(
                s.posChooseCustomer,
                style: TextStyle(fontSize: 13, color: t.accent),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final modes = <String, ({String label, IconData icon})>{
      'cash': (label: s.tenderModeCash, icon: Icons.payments_outlined),
      'bank_transfer': (
        label: s.tenderModeBank,
        icon: Icons.account_balance_outlined
      ),
      'jazzcash': (label: s.tenderModeJazzCash, icon: Icons.smartphone),
      'easypaisa': (label: s.tenderModeEasypaisa, icon: Icons.smartphone),
      'raast': (label: s.tenderModeRaast, icon: Icons.bolt_outlined),
      'card': (label: s.tenderModeCard, icon: Icons.credit_card),
      'cheque': (label: s.tenderModeCheque, icon: Icons.description_outlined),
    };

    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      children: [
        for (final entry in modes.entries)
          ChoiceChip(
            selected: mode == entry.key,
            avatar: Icon(entry.value.icon, size: 16),
            label: Text(entry.value.label),
            onSelected: (_) => onChanged(entry.key),
          ),
      ],
    );
  }
}

/// The notes a Pakistani till actually sees.
class _NoteShortcuts extends StatelessWidget {
  const _NoteShortcuts({required this.due, required this.onPick});

  final Money due;
  final ValueChanged<Money> onPick;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    const notes = [500, 1000, 5000];
    final rounded = due.roundToRupee(mode: RoundingMode.ceilAbs);

    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      children: [
        ActionChip(
          label: Text(s.tenderExact),
          onPressed: () => onPick(due),
        ),
        for (final note in notes)
          if (Money.rupees(note) > rounded)
            ActionChip(
              label: Text('$note'),
              onPressed: () => onPick(Money.rupees(note)),
            ),
        // The next round hundred above the bill, which is what a customer
        // hands over more often than a single note.
        if (due.wholeRupees % 100 != 0)
          ActionChip(
            label: Text('${(due.wholeRupees ~/ 100 + 1) * 100}'),
            onPressed: () =>
                onPick(Money.rupees((due.wholeRupees ~/ 100 + 1) * 100)),
          ),
      ],
    );
  }
}
