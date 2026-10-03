import 'package:pk_money/pk_money.dart';

import '../accounting/chart_view.dart';
import '../catalogue/shelf.dart';
import '../catalogue/unit_converter.dart';
import '../cheques/cheque_lifecycle.dart';
import '../cheques/demand_notice.dart';
import '../corrections/return_builder.dart';
import '../costing/moving_average.dart';
import '../documents/quotation.dart';
import '../entitlement/activity.dart';
import '../pharmacy/medicine.dart';
import '../pricing/price_tier.dart';
import '../receivables/aging.dart';
import '../receivables/fifo_allocator.dart';
import '../sales/bill_copy.dart';
import '../sales/past_deal.dart';
import '../stock/lots.dart';
import '../tax/tax_charge.dart';
import '../time/clock.dart';
import 'catalogue_writer.dart';
import 'entry_details.dart';
import 'manufacturing.dart';
import 'party_groups.dart';
import 'purchase_return_writer.dart';
import 'receipt.dart';
import 'sale_search.dart';
import 'vans.dart';

/// The shop, as the app needs it on screen.
final class FirmProfile {
  const FirmProfile({
    required this.id,
    required this.name,
    required this.province,
    required this.isSalesTaxRegistered,
    required this.roundInvoiceToRupee,
    this.pricesIncludeTax = false,
    this.city,
    this.addressLine1,
    this.phone,
    this.ntn,
    this.strn,
    this.raastAlias,
    this.bankName,
    this.bankAccountTitle,
    this.bankIban,
    this.businessKind = 'general',
  });

  final String id;
  final String name;

  /// What the shop is, as it said at first run or in its details since:
  /// 'kiryana', 'pharmacy', 'wholesale' and the rest.
  final String businessKind;

  /// A chemist (M49): the DRAP price is enforced, and the pharmacy's own
  /// screens and fields are shown.
  bool get isPharmacy => businessKind == 'pharmacy';
  final String? city;
  final String? addressLine1;
  final String? phone;
  final String province;
  final String? ntn;
  final String? strn;
  final bool isSalesTaxRegistered;
  final bool roundInvoiceToRupee;

  /// Whether the prices on the shelf already include sales tax.
  final bool pricesIncludeTax;
  final String? raastAlias;
  final String? bankName;
  final String? bankAccountTitle;
  final String? bankIban;

  ReceiptShop toReceiptShop() => ReceiptShop(
    name: name,
    addressLine1: addressLine1,
    city: city,
    phone: phone,
    ntn: ntn,
    strn: strn,
    raastAlias: raastAlias,
    bankName: bankName,
    bankAccountTitle: bankAccountTitle,
    bankIban: bankIban,
  );
}

/// One row of the item list, and one tap away from a cart line.
final class ItemSummary {
  const ItemSummary({
    required this.id,
    required this.name,
    required this.unitId,
    required this.unitCode,
    required this.unitDecimals,
    required this.saleRate,
    required this.stockOnHand,
    required this.tracksStock,
    this.tracksBatch = false,
    this.tracksSerial = false,
    this.code,
    this.barcode,
    this.category,
    this.description,
    this.minStock = Qty.zero,
    this.purchaseRate,
    this.wholesaleRate,
    this.vipRate,
    this.mrp,
    this.hsCode,
    this.negativeStock,
    this.isThirdSchedule = false,
    this.isService = false,
    this.medicine,
  });

  /// Sold on the retail price printed on its pack (M59): taxed on [mrp], and
  /// warned of when sold above it.
  final bool isThirdSchedule;

  /// A service — a repair, a haircut, a meal — taxed by the province rather
  /// than with the federal sales tax on goods (M59).
  final bool isService;

  final String id;
  final String name;

  /// What it is as a medicine (M49): its salt and strength, maker and
  /// Schedule class. Null for an item that is not one.
  final MedicineDetails? medicine;
  final String? code;
  final String? barcode;
  final String? category;
  final String? description;

  final String unitId;
  final String unitCode;

  /// How many decimals the counter offers for this unit. Pieces get none, so
  /// a cashier cannot sell 2.5 shampoo bottles by mistyping.
  final int unitDecimals;

  final Rate saleRate;

  /// What the shop pays, what it charges a trade customer, and what the box
  /// says. None of the three can be derived from the retail price: a
  /// wholesaler quotes two, and a pharmacy has a third printed on the pack
  /// that it may not legally exceed.
  final Rate? purchaseRate;
  final Rate? wholesaleRate;

  /// What a VIP buyer pays per base unit, if the item has a VIP price.
  final Rate? vipRate;
  final Money? mrp;

  /// For the FBR invoice, which wants it per line rather than per bill.
  final String? hsCode;

  final Qty stockOnHand;
  final Qty minStock;
  final bool tracksStock;

  /// Bought and sold by batch and expiry.
  final bool tracksBatch;

  /// Bought and sold by serial number.
  final bool tracksSerial;

  /// The item's own rule for selling below nothing (M53); null when it
  /// follows the shop's.
  final NegativeStock? negativeStock;

  bool get isLowOnStock =>
      tracksStock && !minStock.isZero && stockOnHand <= minStock;

  /// Sold past what it had (M53): two counters that each sold the last one
  /// while apart, a cashier who was asked and said sell anyway, or an item
  /// that sells on. Shown, not hidden — a shelf below nothing is a count
  /// somebody has to make.
  bool get isBelowNothing => tracksStock && stockOnHand.isNegative;
}

/// A cheque the bank returned, and what the shop has to do about it.
final class BouncedCheque {
  const BouncedCheque({
    required this.paymentId,
    required this.partyId,
    required this.partyName,
    required this.amount,
    required this.chequeNo,
    required this.bouncedOn,
    this.bank,
  });

  final String paymentId;
  final String partyId;
  final String partyName;
  final Money amount;
  final String chequeNo;
  final String? bank;
  final BusinessDate bouncedOn;

  /// The last day to serve the Section 489-F notice.
  BusinessDate get noticeBy => bouncedOn.addDays(noticeDaysAfterBounce);
}

/// One delivery, as the purchases list shows it.
final class PurchaseListRow {
  const PurchaseListRow({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.supplierName,
    required this.total,
    required this.owed,
    required this.lineCount,
    this.supplierBillNo,
  });

  final String id;
  final String docNo;
  final String dateLocal;
  final String supplierName;
  final Money total;

  /// What is still unpaid on this delivery, after every payment since.
  final Money owed;
  final int lineCount;

  /// The number on the supplier's own paper, which is what they will quote.
  final String? supplierBillNo;
}

/// One expense, as the list shows it.
///
/// [head] is the system key of the account the expense was debited to, read
/// back off the journal line. There is no column holding it anywhere else,
/// so the list and the Trial Balance cannot disagree about where Rs 4,000 of
/// bijli went.
final class ExpenseRow {
  const ExpenseRow({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.head,
    required this.amount,
    required this.owed,
    required this.note,
    this.partyName,
  });

  final String id;
  final String docNo;
  final String dateLocal;
  final String head;
  final Money amount;

  /// What is still unpaid. Zero for an expense paid at the counter.
  final Money owed;

  final String note;

  /// Who it is owed to, when it was not paid at once.
  final String? partyName;
}

/// One row of the sales list.
final class SaleListRow {
  const SaleListRow({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.timeLabel,
    required this.total,
    required this.balance,
    required this.lineCount,
    required this.status,
    this.partyName,
    this.partyId,
    this.partyPhone,
  });

  final String id;
  final String docNo;
  final String dateLocal;
  final String timeLabel;
  final String? partyName;

  /// The khata the bill is on, when it is not a walk-in's (M30).
  final String? partyId;

  /// The customer's number as the khata has it now, so a bill can be sent
  /// to them from the list without opening it first.
  final String? partyPhone;
  final Money total;
  final Money balance;
  final int lineCount;
  final String status;

  bool get isPaid => balance.isZero;
  bool get isVoid => status == 'void';
}

/// What one day of trading came to.
final class DayTotals {
  const DayTotals({
    required this.dateLocal,
    required this.billCount,
    required this.sales,
    required this.received,
    required this.onUdhaar,
  });

  final String dateLocal;
  final int billCount;
  final Money sales;
  final Money received;
  final Money onUdhaar;

  static const DayTotals empty = DayTotals(
    dateLocal: '',
    billCount: 0,
    sales: Money.zero,
    received: Money.zero,
    onUdhaar: Money.zero,
  );
}

/// A tender destination the counter can offer.
final class PaymentAccountSummary {
  const PaymentAccountSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.modeLabel,
    required this.isDefault,
  });

  final String id;
  final String name;
  final String kind;
  final String modeLabel;
  final bool isDefault;
}

/// A customer, as the counter needs them.
final class PartySummary {
  const PartySummary({
    required this.id,
    required this.name,
    required this.partyType,
    required this.balance,
    this.phone,
    this.creditLimit,
    this.payable = Money.zero,
    this.bouncedCheques = 0,
    this.priceTier = PriceTier.retail,
    this.defaultDiscountBp = 0,
    this.group,
    this.remarks,
  });

  /// The area, route or kind they are filed under (M40). Null is none.
  final String? group;

  /// What the counter is told about them before it gives credit (M40).
  /// Null when the shop has written nothing.
  final String? remarks;

  /// Which of an item's prices they are sold at.
  final PriceTier priceTier;

  /// A discount they get on every line, in basis points: 250 is 2.5%.
  final int defaultDiscountBp;

  final String id;
  final String name;
  final String? phone;
  final String partyType;

  /// How many of their cheques the bank has returned, ever.
  final int bouncedCheques;

  /// Positive means they owe the shop.
  final Money balance;
  final Money? creditLimit;

  /// What the shop owes them: deliveries not yet paid for and expenses left
  /// on account.
  ///
  /// Kept apart from [balance] rather than netted into it. A wholesaler who
  /// buys from a mill and sells it bran is owed Rs 40,000 and owes Rs 25,000,
  /// and "owes the shop Rs 15,000" is a number neither of them agreed to —
  /// the two debts are settled separately, in cash, and each has its own
  /// bills behind it.
  final Money payable;

  /// Somebody the shop buys from, whatever else they are.
  bool get isSupplier => partyType != 'customer' || payable.isPositive;

  /// Somebody the shop sells to, whatever else they are.
  bool get isCustomer => partyType != 'supplier' || !balance.isZero;

  bool get isOverCreditLimit => creditLimit != null && balance > creditLimit!;

  /// A cheque of theirs has bounced and they still owe the shop. More credit
  /// — udhaar, or another cheque, which is only credit with a date on it —
  /// is asked about at the counter before it is given. Paid up, and the flag
  /// lifts; the bounce itself stays on the khata.
  bool get hasUnsettledBounce => bouncedCheques > 0 && balance.isPositive;
}

/// One thing that happened on a customer's khata.
final class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.reference,
    required this.dateLocal,
    required this.amount,
    required this.balanceAfter,
  });

  final String id;

  /// `sale`, `charge` (a debit note), `return` (goods brought back),
  /// `payment` or `bounce` on a customer's khata; `purchase`, `expense` or
  /// `payment` on what the shop owes a supplier.
  final String kind;

  /// The invoice or receipt number, which is what a customer holding a piece
  /// of paper can match against.
  final String reference;

  final String dateLocal;

  /// Positive increases what they owe, negative reduces it. Signed rather
  /// than paired with a direction flag, because a running balance that adds
  /// some rows and subtracts others by looking at a second column is a
  /// running balance somebody eventually gets backwards.
  final Money amount;

  /// What they owed after this. Computed on read, never stored — a cached
  /// running balance is wrong the moment a backdated bill is entered, which
  /// happens in every shop that does its paperwork on Sundays.
  final Money balanceAfter;

  bool get isPayment => kind == 'payment';
}

/// A customer who owes, and how long they have.
final class AgedParty {
  const AgedParty({
    required this.party,
    required this.oldestDays,
    required this.oldestDateLocal,
    required this.openBills,
  });

  final PartySummary party;

  /// Days since the oldest bill they still owe on.
  final int oldestDays;
  final String oldestDateLocal;

  /// How many bills are open. A customer with one bill from March and one
  /// with eleven are the same age and different conversations.
  final int openBills;

  AgeBucket get bucket => AgeBucket.forDays(oldestDays);
}

/// Everything the app reads.
///
/// Declared here so the UI can be written against domain types and never has
/// to see a row, a companion or a transaction. `lib/` does not list the data
/// package in its pubspec at all, so a widget that reaches for drift is a
/// resolution error rather than a review comment.
abstract interface class AppQueries {
  /// The firm this device belongs to, or null before first run.
  Future<FirmProfile?> currentFirm();

  /// Every firm kept on this phone, oldest first.
  Future<List<FirmProfile>> firms();

  /// The signed-in user's display name.
  Future<String> userName(String userId);

  Future<List<PaymentAccountSummary>> paymentAccounts(String firmId);

  /// Item search for the counter: name, code or barcode, keyset-paginated.
  ///
  /// [afterId] is the last id of the previous page. Offset pagination on a
  /// 20,000-SKU catalogue is the crash cluster that shows up in every
  /// competitor's reviews.
  Future<List<ItemSummary>> searchItems(
    String firmId, {
    String query = '',
    String? afterId,
    int limit = 40,
  });

  Future<ItemSummary?> itemByBarcode(String firmId, String barcode);

  Future<ItemSummary?> itemById(String firmId, String itemId);

  /// The item whose own code is [code], leading zeros aside: how a scale
  /// label's PLU finds what was weighed (M16).
  Future<ItemSummary?> itemByCode(String firmId, String code);

  /// Every recipe the shop keeps (M17), by name.
  Future<List<BomView>> boms(String firmId);

  /// The shop's vans (M18).
  Future<List<VanView>> vans(String firmId);

  /// One van's [day]: its sales, the cash they took, what is still on it,
  /// and the settlement if the day is settled.
  Future<VanDay> vanDay(String firmId, String vanId, BusinessDate day);

  Future<List<PartySummary>> searchParties(
    String firmId, {
    String query = '',
    int limit = 40,
  });

  /// What the shop is owed, bucketed by how old it is.
  ///
  /// [asOfDateLocal] is the business date to age against, so a shopkeeper
  /// doing Friday's books on Sunday gets Friday's numbers if they ask for
  /// them. Aged on `doc_date_local`, never on a UTC instant: PKT is UTC+5
  /// with no daylight saving, and a bill raised at eight in the evening would
  /// otherwise be a day older than it is.
  Future<Aging> aging(String firmId, {required String asOfDateLocal});

  /// Customers who owe, with their oldest unpaid bill first.
  ///
  /// The chase list. Sorted by the age of the oldest debt rather than by size
  /// of balance, because the customer who owes Rs 3,000 since March is a
  /// different conversation from the one who owes Rs 40,000 since last week.
  Future<List<AgedParty>> partiesToChase(
    String firmId, {
    required String asOfDateLocal,
    int limit = 100,
  });

  /// Everything that moved this customer's balance, oldest first.
  ///
  /// Bills and payments interleaved, with the balance after each. The khata
  /// shows what is still owed; this is what settles an argument, because the
  /// question a customer actually asks is "I paid you last week" and the
  /// answer has to be a date and an amount.
  Future<List<LedgerEntry>> partyLedger(
    String firmId,
    String partyId, {
    int limit = 200,
  });

  /// The lines of one bill, with what earlier returns already took back.
  ///
  /// The same rows the writer reads inside its own transaction, so a
  /// shopkeeper picking quantities is picking against what is actually left.
  /// It can still go stale between the screen and the save — a second till
  /// taking the same tin back — and the writer re-reads, so the write is
  /// right and the screen was optimistic. That is the correct direction for
  /// that error to run.
  Future<List<SoldLine>> returnableLines(String firmId, String documentId);

  /// Whether one document is still standing: `posted`, `void` or `draft`.
  ///
  /// Null when there is no such document. A lookup rather than a scan of the
  /// recent list, because a shop with three years of bills has tens of
  /// thousands and the screen wants exactly one.
  Future<String?> documentStatus(String firmId, String documentId);

  /// One customer, by id.
  ///
  /// Exists because the khata screen needs exactly one and was filtering the
  /// result of an unfiltered `searchParties` to get it — which loads every
  /// customer in the shop to display one of them, and a wholesaler has
  /// thousands.
  Future<PartySummary?> partyById(String firmId, String partyId);

  /// Every bill this party still owes on, oldest first.
  ///
  /// The same rows, in the same order, that `PaymentWriteContext` reads
  /// inside the transaction — so a shopkeeper looking at "this will clear
  /// these three bills" is looking at what will actually happen, computed by
  /// the same function. Two different orderings here would make the preview a
  /// guess, and a preview that is sometimes wrong is worse than none.
  ///
  /// Sale invoices only: a customer's money never lands on a bill the shop
  /// owes them.
  Future<List<OpenBill>> openBillsFor(String firmId, String partyId);

  /// What the shop still owes one party, oldest first — the same rows
  /// `PaymentWriteContext.openPayablesFor` reads inside its transaction.
  Future<List<OpenBill>> openPayablesFor(String firmId, String partyId);

  /// Everything that moved what the shop owes one party, oldest first, with
  /// the running figure. Positive amounts are deliveries and unpaid
  /// expenses, negative ones are payments made.
  Future<List<LedgerEntry>> payablesLedger(
    String firmId,
    String partyId, {
    int limit = 200,
  });

  /// Bills, newest first, keyset-paged on [afterId].
  ///
  /// [filter] narrows the rows in SQL rather than over a page in memory, so
  /// the next page is the next page of what was asked for (M30). A filter
  /// applied to forty rows already fetched says "nothing found" about a bill
  /// that is simply further down.
  Future<List<SaleListRow>> recentSales(
    String firmId, {
    String? afterId,
    int limit = 40,
    String? onDateLocal,
    SaleFilter filter = SaleFilter.none,
  });

  /// Who one document is addressed to and the number they can be reached on
  /// now, for sending it to them again (M30). Null for a walk-in's bill.
  Future<DocumentRecipient?> recipientOf(String firmId, String documentId);

  Future<DayTotals> dayTotals(String firmId, String dateLocal);

  /// What the shelf holds of each item and at what average cost — the same
  /// read the purchase writer makes inside its transaction, so a preview of
  /// the new average starts from the position the write will.
  Future<Map<String, CostPosition>> costPositions(
    String firmId,
    Iterable<String> itemIds,
  );

  /// One delivery with what can still go back on it, or null if there is no
  /// such posted delivery. The same read `PurchaseReturnWriteContext` makes.
  Future<ReturnableDelivery?> returnableDelivery(
    String firmId,
    String documentId,
  );

  /// Cheques the shop is holding, soonest due first. Deposited ones included:
  /// they are still not money until the bank says so.
  Future<List<ChequeInHand>> chequesInHand(String firmId);

  /// Quotations, newest first, each with the bill it became if any.
  Future<List<QuotationRow>> quotations(String firmId, {int limit = 100});

  /// What was done in the shop, newest first; only [userId]'s when named.
  Future<List<ActivityEntry>> activity(
    String firmId, {
    String? userId,
    int limit = 200,
  });

  /// The last time the day was closed, if it ever has been.
  Future<ActivityEntry?> lastDayClose(String firmId);

  /// How much of [itemId] is at each place the shop keeps goods, `MAIN`
  /// first.
  Future<Map<String, Qty>> stockByLocation(String firmId, String itemId);

  /// The tax standing of this firm and of [partyId] as a buyer, read the
  /// way a bill for them is priced, so the counter shows what will post.
  Future<TaxContext> taxContextFor(String firmId, String? partyId);

  /// Every place the shop has kept goods: `MAIN` and each godown named.
  Future<List<String>> stockLocations(String firmId);

  /// Every batch or serial of [itemId] still on the shelf, soonest expiry
  /// first; every one in the shop when [itemId] is null.
  Future<List<LotOnHand>> lotsOnHand(String firmId, {String? itemId});

  /// The piece with serial number [serial], if it is on the shelf.
  Future<LotOnHand?> serialOnHand(String firmId, String serial);

  /// Every account in the chart with its balance now, by code.
  Future<List<ChartAccount>> chartOfAccounts(String firmId);

  /// Every posting to [accountId], oldest first, with the running balance.
  Future<List<AccountLedgerLine>> accountLedger(
    String firmId,
    String accountId, {
    int limit = 500,
  });

  /// The cash the books say is in the drawer now.
  Future<Money> cashInDrawer(String firmId);

  /// Delivery challans, newest first, each with the bill it became if any.
  Future<List<QuotationRow>> challans(String firmId, {int limit = 100});

  /// A quotation's or a challan's lines, as written, for making the bill
  /// from it.
  Future<List<QuotedLine>> quotedLines(String firmId, String quotationId);

  /// Everything the party editor can change about one party, as it stands,
  /// so an edit writes back what it did not show instead of blanking it.
  Future<PartyDraft?> partyDraft(String firmId, String partyId);

  /// Cheques the shop has written that the bank has not yet paid or
  /// returned, soonest to be presented first.
  Future<List<IssuedCheque>> chequesIssued(String firmId);

  /// Cheques the bank returned, most recent first.
  Future<List<BouncedCheque>> bouncedCheques(String firmId, {int limit = 50});

  /// The demand notice for one bounced cheque, drawn up on [issuedOn] from
  /// the shop's details, the customer's khata, the cheque and the bank's
  /// return memo. Null if the payment is not a bounced cheque of this firm.
  Future<DemandNotice?> demandNotice(
    String firmId,
    String paymentId, {
    required BusinessDate issuedOn,
  });

  /// Deliveries, newest first.
  Future<List<PurchaseListRow>> recentPurchases(
    String firmId, {
    int limit = 60,
  });

  /// Items the shop has hidden from the counter, most recently hidden first.
  Future<List<ItemSummary>> archivedItems(String firmId, {int limit = 200});

  /// Customers and suppliers the shop has hidden, most recently hidden first.
  Future<List<PartySummary>> archivedParties(String firmId, {int limit = 200});

  /// Rent, bijli and wages, newest first.
  ///
  /// The head comes from the journal line the expense debited, never from a
  /// column of its own.
  Future<List<ExpenseRow>> recentExpenses(String firmId, {int limit = 60});

  /// Everything needed to draw or print one receipt.
  Future<ReceiptData?> receiptFor(String firmId, String documentId);

  /// The units a firm has, for the item editor.
  Future<List<({String id, String code, String name, int decimals})>> units(
    String firmId,
  );

  /// What is about to run out, worst first.
  ///
  /// Only items the shop has actually set a floor for. A default of zero
  /// would make every item the shop has ever sold out of into an alert, and
  /// an alert list that is always full is a list nobody reads.
  Future<List<ItemSummary>> lowStockItems(String firmId, {int limit = 50});

  /// Which unit is the same thing as which other, and by how much.
  ///
  /// Loaded whole rather than queried per line: a shop has a couple of dozen
  /// of these at most, the counter needs them on every keystroke to decide
  /// which units it may offer, and a query per keystroke against a 20,000-SKU
  /// catalogue on an Android Go handset is the thing this product cannot
  /// afford.
  Future<List<UnitEdge>> unitConversions(String firmId);

  /// Where one item's stock went, newest first.
  ///
  /// The question a shopkeeper actually asks is never "what is the balance" —
  /// they can see the shelf. It is "there should be forty and there are
  /// thirty-one, where did nine go", and the only honest answer is the list of
  /// movements. `stock_ledger` is append-only and every row names the document
  /// or the reason that caused it, so this is a read of history rather than a
  /// reconstruction of it.
  ///
  /// Keyset-paged on `(occurred_at_utc, id)` to match `idx_stock_position`. An
  /// OFFSET would get slower the further back a shopkeeper scrolled, and the
  /// interesting rows are usually the old ones.
  Future<List<StockMovement>> stockMovements(
    String firmId,
    String itemId, {
    String? afterId,
    int limit = 50,
  });

  /// What the shelves are worth, and how much of the shop is not on them.
  ///
  /// One indexed aggregation, never a fetch-and-sum in Dart. The largest
  /// single cluster of crash reports against the nearest competitor is reports
  /// on catalogues of a few thousand items, and the cause is exactly that.
  Future<StockSummary> stockSummary(String firmId);

  /// One payment, taken or made, whole (M31).
  ///
  /// [id] is the payment's own, or the id of a journal entry that names it —
  /// which is what a bounced cheque's line in the khata carries, so tapping
  /// the bounce opens the cheque it is about.
  Future<PaymentDetail?> paymentDetail(String firmId, String id);

  /// A charge on a khata, or an expense, whole (M31).
  Future<EntryDocument?> entryDocument(String firmId, String documentId);

  /// The last bills [itemId] was sold to [partyId] on, newest first, at
  /// most [limit] of them (M37).
  ///
  /// Posted bills only: a cancelled bill was never a price anybody paid,
  /// and a quotation is a price asked, not agreed. Free lines are left out,
  /// because "free" is not a rate to quote again. Read through the party's
  /// own index, so the cost is this customer's history and not the whole
  /// shop's — the counter asks this for every line it shows.
  Future<List<PastDeal>> lastSoldTo(
    String firmId, {
    required String partyId,
    required String itemId,
    int limit = 5,
  });

  /// The last deliveries [itemId] came in on, newest first: from
  /// [supplierId] when named, or from anybody (M37).
  ///
  /// What the shop paid, so a screen shows it only to a role that may see
  /// costs.
  Future<List<PastDeal>> lastBought(
    String firmId, {
    required String itemId,
    String? supplierId,
    int limit = 5,
  });

  // -------------------------------------------------------------------------
  // M40 — customers in groups, and a note the counter sees
  // -------------------------------------------------------------------------

  /// Every group the shop has put somebody in, A to Z, with how many are in
  /// it and what they owe and are owed.
  ///
  /// The totals are SUMs over the khata's own balance expression, so a
  /// group's header can never disagree with the rows under it.
  Future<List<PartyGroupSummary>> partyGroups(String firmId);

  /// The khata list: searched, narrowed to one group (or to nobody's), and
  /// put in the order asked for.
  ///
  /// [limit] bounds it; the screen says when it was reached, and the search
  /// box finds the rest.
  Future<List<PartySummary>> partyList(
    String firmId, {
    PartyListFilter filter = const PartyListFilter(),
    int limit = 300,
  });

  /// Sale, purchase, receivable and payable for every group, and one row for
  /// the parties in none, over the period [from] to [to] inclusive (M40).
  ///
  /// For Sale/Purchase by Party Group and every report a group filter
  /// narrows. Groups with no trade in the period still have a row, so a
  /// route that bought nothing this month is seen to have bought nothing.
  Future<List<PartyGroupTotals>> partyGroupTotals(
    String firmId, {
    required BusinessDate from,
    required BusinessDate to,
  });

  /// What one document's paper needs beyond [receiptFor] (M51): its kind,
  /// the party's address and tax numbers, how the goods travel, each line's
  /// tax, and — for a sale to a named customer — the khata as it stood when
  /// the bill was made. Null if the document is not this firm's.
  Future<BillExtras?> billExtras(String firmId, String documentId);

  // -------------------------------------------------------------------------
  // M36 — a bill rung again, or put right and issued again
  // -------------------------------------------------------------------------

  /// A sale bill as the counter needs it to ring it again: its lines in the
  /// unit and at the rate billed, its customer, its discounts, and the money
  /// its own tenders took and still hold. Cancelled bills too. Null if it is
  /// not a sale bill of this firm.
  Future<BillCopy?> billCopy(String firmId, String documentId);

  /// [partyId]'s most recent bill still standing, for "the same as last
  /// time" at the counter; null if they have none.
  Future<LinkedBill?> lastBillFor(String firmId, String partyId);

  /// The bill [documentId] replaced, and the bill that replaced it.
  Future<BillLinks> billLinks(String firmId, String documentId);
}

/// The shop's stock, in five numbers.
///
/// Deliberately small. A shopkeeper glancing at this before locking up wants
/// to know what is tied up in stock, what is about to run out, and what has
/// already run out — not a table. The table is the item list, one tap away.
final class StockSummary {
  const StockSummary({
    required this.trackedItems,
    required this.stockValue,
    required this.lowCount,
    required this.outCount,
    required this.negativeCount,
  });

  /// Items that carry stock at all. A service has no shelf.
  final int trackedItems;

  /// Every item's quantity at its own weighted-average cost.
  ///
  /// At COST, not at retail. Valuing stock at what it would sell for counts
  /// profit the shop has not made, which is the single most common way a small
  /// business talks itself into believing it is richer than it is.
  final Money stockValue;

  /// At or below the floor the shopkeeper set, and not yet at zero.
  final int lowCount;

  /// Exactly nothing left.
  final int outCount;

  /// Less than nothing left.
  ///
  /// Impossible on a shelf and entirely possible in a ledger: it means the
  /// shop sold something it had never recorded receiving. Surfaced rather than
  /// clamped, because a negative balance is a bookkeeping error a person needs
  /// to fix, and hiding it makes the stock value quietly wrong.
  final int negativeCount;

  bool get isEmpty => trackedItems == 0;

  static const StockSummary empty = StockSummary(
    trackedItems: 0,
    stockValue: Money.zero,
    lowCount: 0,
    outCount: 0,
    negativeCount: 0,
  );
}

/// One line of an item's stock history.
final class StockMovement {
  const StockMovement({
    required this.id,
    required this.txnType,
    required this.qtyDelta,
    required this.occurredOnLocal,
    required this.balanceAfter,
    this.docNo,
    this.reason,
  });

  final String id;

  /// `opening`, `sale`, `adjustment`, `wastage`, and the rest of the closed
  /// set the schema's CHECK constraint admits.
  final String txnType;

  /// In the item's base unit. Negative is stock leaving.
  final Qty qtyDelta;

  /// The shopkeeper's day, not UTC. A sale at eight in the evening in Lahore
  /// belongs to that evening, and grouping on UTC would file it under tomorrow.
  final String occurredOnLocal;

  /// The cached running balance at this row, or null where it was never
  /// stamped. Derived, verified by the health check, never authoritative.
  final Qty? balanceAfter;

  /// The bill this came from, where there was one. An opening balance and a
  /// stock correction have no document, which is exactly why [reason] exists.
  final String? docNo;

  /// Why, for the movements a person made rather than a sale.
  final String? reason;

  bool get isOut => qtyDelta.isNegative;
}
