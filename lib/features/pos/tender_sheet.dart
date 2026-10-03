import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../cheques/cheque_fields.dart';
import '../khata/entry_actions.dart' show modeLabel;
import '../khata/goods_given.dart' show giveFromCounter; // M55
import '../loyalty/loyalty_at_counter.dart'; // M66
import '../loyalty/loyalty_providers.dart' show loyaltyProblemText; // M66
import '../mobile/qist_sheet.dart'; // M50
import '../parties/party_groups.dart' show PartyRemarksLine;
import '../parties/party_picker.dart';
import '../pharmacy/pharmacy_gate.dart';
import '../sales/receipt_offer.dart' show offerAfterSale; // M70
import '../sales/receipt_screen.dart';
import '../subscription/plans_screen.dart';
import '../tax/counter_tax.dart'; // M59
import 'cart.dart';
import 'pos_screen.dart';
import 'scheme_book.dart'; // M43
import 'schemes_at_counter.dart'; // M43
import 'shelf_guard.dart';

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
  final _chequeNo = TextEditingController();
  final _chequeBank = TextEditingController();

  // M59: a walk-in's name and CNIC, on a bill over Rs 100,000.
  final _buyerName = TextEditingController();
  final _buyerCnic = TextEditingController();

  /// The day the cheque can be banked. Null until the sheet first draws with
  /// a clock, then today unless the shopkeeper picks a term.
  BusinessDate? _chequeDue;

  String _mode = 'cash';
  bool _onUdhaar = false;
  bool _busy = false;
  String? _failure;

  /// Set once the shopkeeper has been shown the limit and chosen to go past
  /// it. Their shop, their call — but they get to make it knowingly, and it
  /// is not remembered beyond this bill.
  bool _creditLimitOverridden = false;

  /// The limit and what this bill would take the customer to, while the
  /// shopkeeper is being asked. Null the rest of the time.
  ({Money limit, Money after})? _overLimit;

  /// Set once the shopkeeper has been told this customer's cheque bounced
  /// and chosen to give credit anyway. Not remembered beyond this bill.
  bool _bounceOverridden = false;

  /// The bounced cheques and what is still owed, while the shopkeeper is
  /// being asked. Null the rest of the time.
  ({int count, Money owed})? _bounced;

  /// A bill putting another right starts from the money the customer had
  /// already handed over for it (M36), in the way it came.
  ///
  /// Cancelling the old bill took its tenders off the books, as if the cash
  /// had been handed back; it was not, and it is this money that pays the
  /// corrected bill. Cash is written in as what the shop kept of it (the
  /// change went back the first time), so the card above shows the change
  /// to give back when the bill came down and what is still to take when
  /// it went up. Anything else is the same mode
  /// again, its reference and cheque carried; a bill that was all on udhaar
  /// starts on udhaar. The cashier can change any of it — the point is that
  /// the money is never silently forgotten, and never taken twice.
  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    final paid = cart.paidBefore;
    if (cart.replacesId == null || paid == null) return;
    if (paid.onUdhaar) {
      _onUdhaar = cart.partyId != null;
      return;
    }
    final mode = paid.mode ?? 'cash';
    _mode = mode;
    if (mode == 'cash') {
      _tendered.text = paid.amount.amountOnly;
    } else if (mode == 'cheque') {
      _chequeNo.text = paid.chequeNo ?? '';
      _chequeBank.text = paid.chequeBank ?? '';
      if (paid.chequeDateUtcMillis case final millis?) {
        _chequeDue = BusinessDate.fromUtc(
          DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
        );
      }
    } else {
      _reference.text = paid.reference ?? '';
    }
  }

  @override
  void dispose() {
    _tendered.dispose();
    _reference.dispose();
    _chequeNo.dispose();
    _chequeBank.dispose();
    _buyerName.dispose(); // M59
    _buyerCnic.dispose();
    super.dispose();
  }

  Money get _tenderedAmount => Money.tryParse(_tendered.text) ?? Money.zero;

  /// The account this tender posts into. It matches the chosen mode or there
  /// is none.
  ///
  /// There used to be two fallbacks here — the shop's default, then whatever
  /// sorted first — and first run seeded exactly one account, cash, marked
  /// default. So every JazzCash, EasyPaisa, Raast, card and cheque sale in
  /// the app debited Cash in Hand. The wallet balance never existed, the
  /// drawer never reconciled against the day's takings, and the screen said
  /// nothing at all. First run now seeds an account per mode; a mode with no
  /// account is a real failure and says so, rather than quietly booking the
  /// money somewhere it never went.
  PaymentAccountSummary? _accountFor(List<PaymentAccountSummary> accounts) {
    for (final a in accounts) {
      if (a.modeLabel == _mode) return a;
    }
    return null;
  }

  /// Keeps this cart as a quotation, or sends it on a delivery challan,
  /// instead of billing it.
  ///
  /// A quotation is a price asked for: nothing leaves the shelf and nothing
  /// is owed. A challan is goods sent before the bill: they leave the shelf,
  /// and are owed for once the bill is made from it. Either way the counter
  /// is cleared for the next bill.
  Future<void> _keep({required bool challan}) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final cart = ref.read(cartProvider);
    final units = ref.read(unitConverterProvider).valueOrNull;
    final firm = ref.read(firmProvider).valueOrNull;
    if (firm == null || cart.isEmpty) return;
    if (challan && cart.partyId == null) {
      setState(() => _failure = s.challanNeedsCustomer);
      return;
    }
    // A quotation is billed again item by item, and a challan sends goods
    // somebody counts; a loose line (M37) is neither. Said here, in the
    // shopkeeper's words, before the builder refuses it in English.
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
    // M53: a challan takes the goods off the shelf as a bill does.
    if (challan &&
        !await shelfAllowsBill(context, ref, cart, forChallan: true)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    // M54: and a Schedule medicine leaves on it only with its prescription,
    // asked here in the bill's own sheet (M49) and registered against the
    // challan's lines; the bill made from it carries the same paper.
    CounterRx? rx;
    if (challan) {
      final preview = ref.read(cartPreviewByProvider(null));
      if (preview == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      rx = await pharmacyAllowsBill(
        context,
        ref,
        preview,
        onAsk: () => setState(() => _busy = false),
      );
      if (rx == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!_busy) setState(() => _busy = true);
    }
    try {
      final services = ref.read(appServicesProvider);
      // M43; M66: a quotation or a challan spends no points.
      final books = cart.forBooks(units, schemesFor(ref), points: false);
      final draft = SaleDraft(
        lines: books.lines,
        partyId: cart.partyId,
        partyName: cart.partyName,
        billDiscount: books.billDiscount,
        roundToRupee: firm.roundInvoiceToRupee,
        // A quotation on the counter sent on a challan stays tied to it
        // (M25), so it reads as done rather than still open; a sale order
        // likewise (M54), and its advance waits for the challan's bill.
        convertedFromId: challan ? cart.sourceId : null,
        prescription: rx?.prescription, // M54
      );
      final String message;
      if (challan) {
        final saved = await services.issueChallan(services.actorNow(), draft);
        unawaited(keepPrescriptionPhoto(services, saved.id, rx)); // M54
        message = s.challanSaved(saved.docNo);
      } else {
        final saved = await services.saveQuotation(services.actorNow(), draft);
        message = s.quotationSaved(saved.docNo);
      }
      cartNotifier.clear();
      container.read(refreshTickProvider.notifier).update((n) => n + 1);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  /// M54: what the advance held for the customer's order pays of [owed] on
  /// this bill — the order on the counter, or the challan made from one.
  /// Nothing when the bill is made from no order; and nothing, rather than
  /// a failure, when it cannot be read: the limit is then asked about the
  /// whole bill, as it was before M54.
  Future<Money> _orderAdvance(Cart cart, Money owed) async {
    final partyId = cart.partyId;
    final sources = [?cart.sourceId, ...cart.alsoSourceIds];
    if (partyId == null || sources.isEmpty) return Money.zero;
    try {
      return await ref
          .read(appServicesProvider)
          .orders
          .advanceOnBill(partyId: partyId, sourceIds: sources, owed: owed);
    } on Object {
      return Money.zero;
    }
  }

  // M55: hands the counter's goods to its customer, rate later.
  Future<void> _rateLater() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await giveFromCounter(context, ref);
    if (!mounted || failure == null) return;
    setState(() {
      _busy = false;
      _failure = failure.isEmpty ? null : failure;
    });
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
      _overLimit = null;
    });

    final s = AppStrings.of(context);
    // M59: priced at the mode picked — a service's provincial tax is less
    // by card, wallet or QR.
    final preview = ref.read(cartPreviewByProvider(_onUdhaar ? null : _mode));
    final cart = ref.read(cartProvider);
    // Read before the write, not through `ref` afterwards: this is what turns
    // "two maunds" into the eighty kilos that actually leave the shelf.
    final units = ref.read(unitConverterProvider).valueOrNull;
    final firm = ref.read(firmProvider).valueOrNull;
    if (preview == null || firm == null) {
      setState(() => _busy = false);
      return;
    }

    // A loose line (M37) has no HS code, and a shop reporting to FBR must
    // send one for every line. The counter does not offer one there, but a
    // bill half-rung before reporting was turned on comes back with the
    // cart. Said before anything is written; the sale path refuses it too.
    if (cart.lines.any((l) => l.isLoose) &&
        await ref.read(appServicesProvider).fbr.reportsSales()) {
      if (mounted) {
        setState(() {
          _failure = s.looseFbrRefused;
          _busy = false;
        });
      }
      return;
    }

    // M59: a walk-in bill over Rs 100,000 names its buyer. Required of a
    // shop registered for sales tax, and the sale path refuses the bill
    // without it; any other shop is asked and may leave it.
    if (buyerNameNeeded(
      total: preview.total,
      partyId: cart.partyId,
      buyerName: null,
    )) {
      final problem = buyerNameProblem(
        s,
        name: _buyerName.text,
        cnic: _buyerCnic.text,
        required: firm.isSalesTaxRegistered,
      );
      if (problem != null) {
        setState(() {
          _failure = problem;
          _busy = false;
        });
        return;
      }
    }

    // Anything left owing is somebody's khata, whether the switch was flipped
    // or the cash handed over simply fell short. There is no such thing as an
    // anonymous debtor.
    final leavesBalance =
        _onUdhaar ||
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

    // A cheque is a promise to pay on a day, and the promise can bounce. The
    // sheet used to offer Cheque and ask for nothing, so the schema refused
    // every cheque sale and the counter showed "nothing was written".
    final byCheque = !_onUdhaar && _mode == 'cheque';
    if (byCheque && cart.partyId == null) {
      setState(() {
        _failure = s.chequeNeedsCustomer;
        _busy = false;
      });
      return;
    }
    if (byCheque && _chequeNo.text.trim().isEmpty) {
      setState(() {
        _failure = s.wasooliChequeNoRequired;
        _busy = false;
      });
      return;
    }

    // M54: what the advance on the customer's order (M41) pays of what this
    // bill leaves owed, read by the very reads the bill will take it with.
    // The part it pays is not credit: the money is already in the drawer,
    // held for exactly these goods. So a bill the advance covers is asked
    // neither about a bounced cheque nor about the limit, as a bill paid in
    // cash is not, and a customer at their limit can still be billed what
    // they paid for in advance. A bill that leaves more owed than that is
    // asked as before, and lands where it always said: their khata, with
    // the advance spent, plus the bill.
    final owedHere = _onUdhaar || _tenderedAmount.isZero
        ? preview.balance
        : preview.total - _tenderedAmount;
    final byAdvance = leavesBalance
        ? await _orderAdvance(cart, owedHere)
        : Money.zero;
    final givesCredit = leavesBalance && owedHere > byAdvance;
    if (!mounted) return;

    // A customer whose cheque bounced and who still owes is asked about
    // before more credit goes out: udhaar, or another cheque, which is only
    // credit with a date on it. Their shop, their call, but made knowingly.
    if ((givesCredit || byCheque) && !_bounceOverridden) { // M54
      final party = await ref
          .read(appServicesProvider)
          .queries
          .partyById(firm.id, cart.partyId!);
      if (party != null && party.hasUnsettledBounce) {
        if (mounted) {
          setState(() {
            _failure = null;
            _bounced = (count: party.bouncedCheques, owed: party.balance);
            _busy = false;
          });
        }
        return;
      }
    }

    // A credit limit that blocks nothing is decoration. It was being set in
    // the party editor, shown as a chip on two screens, and enforced nowhere:
    // a shop could put a customer on Rs 50,000 and watch them reach Rs
    // 200,000 without the app ever mentioning it.
    //
    // Checked here rather than at the cart, because this is the moment before
    // the goods leave — and against the balance as it stands right now rather
    // than the copy the picker handed over, which may be minutes old and is
    // exactly the figure a second till has been changing.
    if (givesCredit && !_creditLimitOverridden) { // M54: not what it covers
      final party = await ref
          .read(appServicesProvider)
          .queries
          .partyById(firm.id, cart.partyId!);
      final limit = party?.creditLimit;
      if (party != null && limit != null) {
        final after = party.balance + preview.balance;
        if (after > limit) {
          if (mounted) {
            setState(() {
              _failure = null;
              _overLimit = (limit: limit, after: after);
              _busy = false;
            });
          }
          return;
        }
      }
    }

    // M53: the shelf, asked once more before the goods leave
    // (shelf_guard.dart); the sale path refuses a blocked item again.
    if (!mounted) return;
    if (!await shelfAllowsBill(context, ref, cart)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    // M49: the DRAP price, and a Schedule medicine's prescription
    // (pharmacy_gate.dart); the sale path refuses both again.
    if (!mounted) return;
    // M54: a bill made from a challan carries the prescription the challan
    // was registered against, and the cashier is not asked a second time.
    final sentWith = cart.sourceType == 'delivery_challan'
        ? await ref
              .read(appServicesProvider)
              .pharmacy
              .prescriptionOn(cart.sourceId!)
              .then((p) => p, onError: (Object _) => null)
        : null;
    if (!mounted) return;
    final rx = await pharmacyAllowsBill(
      context,
      ref,
      preview,
      onAsk: () => setState(() => _busy = false),
      given: sentWith,
    );
    if (rx == null || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!_busy) setState(() => _busy = true);

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
      settling = _tenderedAmount < preview.total
          ? _tenderedAmount
          : preview.total;
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
              // Cash has no reference to carry. A transaction id typed under
              // "Bank transfer" and then switched to "Cash" was being saved
              // onto the cash payment, where it names a transfer that never
              // happened.
              reference:
                  _mode == 'cash' ||
                      _mode == 'cheque' ||
                      _reference.text.trim().isEmpty
                  ? null
                  : _reference.text.trim(),
              chequeNo: byCheque ? _chequeNo.text.trim() : null,
              chequeBank: byCheque && _chequeBank.text.trim().isNotEmpty
                  ? _chequeBank.text.trim()
                  : null,
              chequeDateUtc: byCheque
                  ? DateTime.fromMillisecondsSinceEpoch(
                      chequeDueUtcMillis(
                        _chequeDue ??
                            BusinessDate.now(
                              ref.read(appServicesProvider).clock,
                            ),
                      ),
                      isUtc: true,
                    )
                  : null,
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
      final books = cart.forBooks(units, schemesFor(ref)); // M43
      // A rider's phone sells from the van, not from the shop floor (M18).
      final location = await services.counterLocation();
      // M63: a repeating bill moves its template on in the same commit.
      // M66: and the customer's points are spent in it (loyalty_services).
      final sale = services.loyalty.postSaleFor(
        recurring: cart.recurring,
        redeem: cart.pointsOff.isPositive ? cart.loyalty : null,
      );
      final posted = await sale(
        services.actorNow(),
        SaleDraft(
          locationCode: location,
          lines: books.lines,
          partyId: cart.partyId,
          // M59: the walk-in's name and CNIC, when the counter asked.
          partyName: cart.partyId == null && _buyerName.text.trim().isNotEmpty
              ? _buyerName.text.trim()
              : cart.partyName,
          partyNtn: cart.partyId == null ? tidyCnic(_buyerCnic.text) : null,
          tenders: tenders,
          billDiscount: books.billDiscount,
          roundToRupee: firm.roundInvoiceToRupee,
          convertedFromId: cart.sourceId,
          alsoFromIds: cart.alsoSourceIds,
          // The cancelled bill this one puts right (M36), linked as the
          // sale posts.
          replacesId: cart.replacesId,
          prescription: rx.prescription, // M49
        ),
      );
      // M49: the paper prescription's photograph, beside the bill.
      unawaited(keepPrescriptionPhoto(services, posted.documentId, rx));

      // Through the captured handles, not through `ref`: this runs whether or
      // not the sheet is still on screen, because the sale is committed and
      // the cart must not survive it.
      // Waiting for FBR, when the shop reports (M19): the receipt says so
      // until FBR's number is back, and the send is tried at once.
      await services.fbr.afterSale(posted.documentId);
      unawaited(services.fbr.sendPending());

      cartNotifier.clear();
      container.read(posQueryProvider.notifier).state = '';
      container.read(refreshTickProvider.notifier).update((n) => n + 1);

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(s.billSaved(posted.docNo))),
      );

      // Back to the home screen, with the day's totals already bumped, and
      // the receipt on top of it.
      //
      // Counted pops were wrong. `pop` acts on the last route that is still
      // "present", and a route stops being present the moment it enters
      // `popping` — which happens synchronously inside `pop` itself. So if the
      // sheet was already on its way out when the sale returned — the cashier
      // tapped Save and then the ✕, or used the back gesture, and `postSale`
      // beat the ~250ms exit animation — the two pops took the counter and
      // the home screen instead, and the receipt was pushed onto an emptied
      // navigator. Back from there was a black screen.
      //
      // Home is the first route, so this names where to stop rather than how
      // many times to go, and it cannot overshoot.
      navigator.popUntil((route) => route.isFirst);
      offerAfterSale(navigator, posted); // M70
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReceiptScreen(documentId: posted.documentId, docNo: posted.docNo),
        ),
      );
    } on LoyaltyRefused catch (refused) {
      // M66: the points, refused in the bill's own commit, said in words.
      if (mounted) {
        setState(() {
          _failure =
              '${s.billSaveFailed}\n\n${loyaltyProblemText(s, refused.problem)}';
          _busy = false;
        });
      }
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
    // M59: at the mode picked, as _post prices it.
    final preview = ref.watch(cartPreviewByProvider(_onUdhaar ? null : _mode));
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
    final short =
        counting && _tenderedAmount.isPositive && _tenderedAmount < due
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
                // Flexible, so a long title at 200% ellipsises instead of
                // shouldering the close button off the right of the sheet.
                Flexible(
                  child: Text(
                    s.tenderTitle,
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
            _DueCard(due: due, change: change, short: short),
            const BillSlabRow(), // M43: the shop's discount on a big bill.
            ServiceTaxNote(sale: preview), // M59: "PRA 8% (card)"
            // M66: the customer's points, and the profit for whoever may
            // see it (loyalty_at_counter.dart).
            LoyaltyRow(onUdhaar: _onUdhaar),
            MarginLine(mode: _onUdhaar ? null : _mode),
            if (cart.paidBefore case final paid? when cart.replacesNo != null)
              _PaidBefore(
                docNo: cart.replacesNo!,
                paid: paid,
                due: due,
                // Cash says its own change and shortfall on the card above;
                // another mode settles the whole bill, so the difference
                // from what came before is said here.
                showDifference: !_onUdhaar && _mode != 'cash',
              ),
            const SizedBox(height: BlTokens.space4),

            // Who is this bill for. A walk-in needs nobody, which is the
            // common case at a kiryana counter and must never be an obstacle.
            _CustomerRow(cart: cart),
            // What the shop wrote about them, read-only, under their name
            // where credit is given (M40). Nothing at all when there is none.
            if (cart.partyId != null) PartyRemarksLine(partyId: cart.partyId!),
            // M59: the buyer's name on a walk-in bill over Rs 100,000.
            if (buyerNameNeeded(
              total: preview.total,
              partyId: cart.partyId,
              buyerName: null,
            ))
              BuyerNameFields(
                name: _buyerName,
                cnic: _buyerCnic,
                required:
                    ref.watch(firmProvider).valueOrNull?.isSalesTaxRegistered ??
                    false,
                onChanged: () => setState(() => _failure = null),
              ),
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
              ] else if (_mode == 'cheque')
                ChequeFields(
                  number: _chequeNo,
                  bank: _chequeBank,
                  today: BusinessDate.now(ref.read(appServicesProvider).clock),
                  due:
                      _chequeDue ??
                      BusinessDate.now(ref.read(appServicesProvider).clock),
                  onDueChanged: (d) => setState(() => _chequeDue = d),
                  onChanged: () => setState(() => _failure = null),
                )
              else
                BlField(controller: _reference, label: s.tenderReference),
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

            // The bounce, and the way past it, where the limit's would be.
            if (_bounced case final bounced?) ...[
              const SizedBox(height: BlTokens.space3),
              Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  color: t.dangerSurface,
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.report_gmailerrorred_outlined,
                          size: 18,
                          color: t.danger,
                        ),
                        const SizedBox(width: BlTokens.space2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.tenderChequeBounced,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: t.danger,
                                ),
                              ),
                              Text(
                                s.tenderChequeBouncedDetail(
                                  bounced.count,
                                  bounced.owed.amountOnly,
                                ),
                                style: TextStyle(fontSize: 13, color: t.danger),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BlTokens.space2),
                    BlButton(
                      label: s.tenderChequeBouncedAllow,
                      kind: BlButtonKind.secondary,
                      onPressed: () => setState(() {
                        _bounceOverridden = true;
                        _bounced = null;
                      }),
                    ),
                  ],
                ),
              ),
            ],

            // The limit, and the way past it. Not a dialog: a shopkeeper with
            // a customer waiting should see the number and the button in the
            // same place they were already looking.
            if (_overLimit case final over?) ...[
              const SizedBox(height: BlTokens.space3),
              Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  color: t.warningSurface,
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: t.warning,
                        ),
                        const SizedBox(width: BlTokens.space2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.tenderOverLimit,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: t.warning,
                                ),
                              ),
                              Text(
                                s.tenderOverLimitDetail(
                                  over.limit.amountOnly,
                                  over.after.amountOnly,
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: t.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BlTokens.space2),
                    BlButton(
                      label: s.tenderOverLimitAllow,
                      kind: BlButtonKind.secondary,
                      onPressed: () => setState(() {
                        _creditLimitOverridden = true;
                        _overLimit = null;
                      }),
                    ),
                  ],
                ),
              ),
            ],

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
            // M50: a phone sold on qist (mobile/qist_sheet.dart).
            QistButton(enabled: !_busy),
            // A price asked for, or goods sent ahead of the bill. Not
            // offered while billing a quotation or a challan: that bill is
            // the one being kept. Nor while putting a bill right (M36): what
            // replaces a cancelled bill is a bill.
            if (cart.sourceId == null && cart.replacesId == null) ...[
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.quotationMake,
                icon: Icons.request_quote_outlined,
                kind: BlButtonKind.secondary,
                onPressed: _busy
                    ? null
                    : () => unawaited(_keep(challan: false)),
              ),
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.challanMake,
                icon: Icons.assignment_turned_in_outlined,
                kind: BlButtonKind.secondary,
                onPressed: _busy ? null : () => unawaited(_keep(challan: true)),
              ),
              // M55: the goods handed over with the rate to be agreed — a
              // challan with no rate, priced later from the khata.
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.counterRateLater,
                icon: Icons.scale_outlined,
                kind: BlButtonKind.secondary,
                onPressed: _busy ? null : () => unawaited(_rateLater()),
              ),
            ]
            // M54: a customer's order (M41) may go out ahead of its bill on
            // a challan, linked to the order, and the bill made from that
            // challan takes the order's advance (withHeldAdvances). The one
            // loaded paper that may: a quotation billed is the bill, and a
            // challan's goods have already gone.
            else if (cart.fromSaleOrder && cart.replacesId == null) ...[
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.challanMake,
                icon: Icons.assignment_turned_in_outlined,
                kind: BlButtonKind.secondary,
                onPressed: _busy ? null : () => unawaited(_keep(challan: true)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What was taken on the bill being put right, and — when the new bill is
/// settled another way than cash — the difference to give back or take
/// (M36).
class _PaidBefore extends StatelessWidget {
  const _PaidBefore({
    required this.docNo,
    required this.paid,
    required this.due,
    required this.showDifference,
  });

  final String docNo;
  final PaidBefore paid;
  final Money due;
  final bool showDifference;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final difference = due - paid.amount;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 16, color: t.inkMuted),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paid.onUdhaar
                      ? s.tenderPaidBeforeUdhaar(docNo)
                      : s.tenderPaidBefore(
                          docNo,
                          paid.amount.amountOnly,
                          modeLabel(s, paid.mode ?? 'cash'),
                        ),
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
                if (showDifference && !paid.onUdhaar && !difference.isZero)
                  Text(
                    difference.isNegative
                        ? s.tenderGiveBack((-difference).amountOnly)
                        : s.tenderTakeMore(difference.amountOnly),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.warning,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
          BlAmountRow(
            label: s.tenderDue,
            labelStyle: TextStyle(fontSize: 14, color: t.inkMuted),
            child: BlMoney(
              due,
              size: 30,
              weight: FontWeight.w700,
              withSymbol: true,
              semanticPrefix: s.tenderDue,
            ),
          ),
          if (!change.isZero) ...[
            const Divider(height: BlTokens.space5),
            BlAmountRow(
              label: s.tenderChange,
              labelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.money,
              ),
              child: BlMoney(
                change,
                size: 24,
                weight: FontWeight.w700,
                colour: t.money,
                semanticPrefix: s.tenderChange,
              ),
            ),
          ] else if (!short.isZero) ...[
            const Divider(height: BlTokens.space5),
            BlAmountRow(
              label: s.tenderRemaining,
              labelStyle: TextStyle(fontSize: 14, color: t.warning),
              child: BlMoney(
                short,
                size: 18,
                colour: t.warning,
                semanticPrefix: s.tenderRemaining,
              ),
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
        // A name that matches nobody is offered as a new customer, made and
        // chosen without leaving the bill (M32). Whoever comes back — found
        // or just made — goes through the same `setParty`, so the lines move
        // to their price list exactly as they would for an old customer.
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
                  color: cart.partyName == null ? t.inkMuted : t.ink,
                ),
              ),
            ),
            if (cart.partyId != null)
              BlIconButton(
                icon: Icons.close,
                label: s.actionClose,
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .setParty(
                      null,
                      units: ref.read(unitConverterProvider).valueOrNull,
                    ),
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

class _ModePicker extends ConsumerWidget {
  const _ModePicker({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final modes = <String, ({String label, IconData icon})>{
      'cash': (label: s.tenderModeCash, icon: Icons.payments_outlined),
      'bank_transfer': (
        label: s.tenderModeBank,
        icon: Icons.account_balance_outlined,
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
            onSelected: (_) async {
              // A new cheque needs a plan with cheques (M21).
              if (entry.key == 'cheque' &&
                  !await ensurePlan(context, ref, PlanFeature.cheques)) {
                return;
              }
              onChanged(entry.key);
            },
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
        ActionChip(label: Text(s.tenderExact), onPressed: () => onPick(due)),
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
