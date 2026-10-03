import 'package:pk_money/pk_money.dart';

import '../catalogue/packs.dart';
import '../catalogue/shelf.dart';
import '../catalogue/spelling.dart';
import '../identity/actor_context.dart';
import '../pricing/price_tier.dart';
import 'party_groups.dart';

/// An item as the quick-add and edit screens describe it.
final class ItemDraft {
  const ItemDraft({
    required this.name,
    required this.baseUnitId,
    required this.saleRate,
    this.code,
    this.barcode,
    this.category,
    this.description,
    this.purchaseRate,
    this.wholesaleRate,
    this.vipRate,
    this.mrp,
    this.hsCode,
    this.openingStock = Qty.zero,
    this.openingRate = Rate.zero,
    this.minStock = Qty.zero,
    this.tracksStock = true,
    this.tracksBatch = false,
    this.tracksSerial = false,
    this.isActive = true,
    this.negativeStock,
    this.packs,
    this.isThirdSchedule,
    this.isService,
  });

  /// Sold on its printed retail price (M59). Null leaves it as it is, so a
  /// form that does not show it — the quick-add sheet, the importer — never
  /// takes it off.
  final bool? isThirdSchedule;

  /// A service rather than goods (M59); null leaves it as it is.
  final bool? isService;

  final String name;
  final String? code;
  final String? barcode;
  final String? category;
  final String? description;

  final String baseUnitId;
  final Rate saleRate;
  final Rate? purchaseRate;
  final Rate? wholesaleRate;
  final Rate? vipRate;
  final Money? mrp;
  final String? hsCode;

  final Qty openingStock;
  final Rate openingRate;
  final Qty minStock;
  final bool tracksStock;

  /// Bought and sold by batch, each with its expiry: medicines, packaged
  /// food. The counter sells the batch that expires first.
  final bool tracksBatch;

  /// One serial number per piece, bought and sold by it: phones by IMEI.
  final bool tracksSerial;
  final bool isActive;

  /// What the counter does when a sale would take this below nothing
  /// (M53). Null follows the shop's own setting, which is what nearly every
  /// item does; an edit that leaves it null puts the item back on the
  /// shop's rule.
  final NegativeStock? negativeStock;

  /// The packs it comes in, each with its size (M53): a carton of 24, a
  /// bori of 50 kg.
  ///
  /// Null leaves the item's packs as they are, so a form that knows nothing
  /// of packs — the quick-add sheet, the importer — never takes them off.
  /// An empty list takes every one off.
  final List<ItemPack>? packs;

  /// The name with capitals, spaces and punctuation set aside, in any
  /// script: what "the same name" means when the quick-add sheet looks for
  /// an item already in the shop.
  ///
  /// Not what is stored in `name_search` any more. That is
  /// [nameSearchColumn], which carries this and a spelling key besides
  /// (M56), so a search for "cheeni" finds "Chini". A twin is still the
  /// same name, not a name that sounds the same: "Chini" and "Cheeni" are
  /// offered to each other by the search, and a shopkeeper decides.
  String get searchKey => plainSearchText(name);
}

/// A customer or supplier as the party editor describes them.
final class PartyDraft {
  const PartyDraft({
    required this.name,
    this.partyType = 'customer',
    this.phone,
    this.whatsapp,
    this.addressLine1,
    this.city,
    this.ntn,
    this.strn,
    this.cnic,
    this.buyerRegistrationType = 'unregistered',
    this.isOnAtl,
    this.openingBalance = Money.zero,
    this.creditLimit,
    this.creditDays,
    this.priceTier = PriceTier.retail,
    this.defaultDiscountBp = 0,
    this.group,
    this.remarks,
  });

  final String name;
  final String partyType;

  /// The area, route or kind of customer they are filed under (M40):
  /// "Mohalla Gulberg", "Route 3", "Hotels". Null is no group.
  ///
  /// Written as given, tidied by [partyGroupName], and spelt the way the
  /// shop already spells it when it matches a group in another case — so
  /// "route 3" typed in a hurry joins "Route 3" instead of starting a second
  /// route with one customer on it.
  final String? group;

  /// What the cashier should know before giving them credit (M40): "Sirf
  /// cash — cheque bounce ho chuka", "Delivery after 5pm". Shown under their
  /// name on the payment sheet, read-only there. Null or blank is nothing.
  final String? remarks;

  /// Which of an item's prices they are sold at.
  final PriceTier priceTier;

  /// A discount on every line they buy, in basis points. 0 to 10000.
  final int defaultDiscountBp;
  final String? phone;
  final String? whatsapp;
  final String? addressLine1;
  final String? city;
  final String? ntn;
  final String? strn;
  final String? cnic;
  final String buyerRegistrationType;

  /// Further tax at 4% under s.3(1A) STA turns on the buyer being off the
  /// Active Taxpayer List. Null means nobody has checked, which is not the
  /// same as false.
  final bool? isOnAtl;

  final Money openingBalance;
  final Money? creditLimit;
  final int? creditDays;

  /// The name with capitals, spaces and punctuation set aside: what "the
  /// same name" means to the khata's twin check. See [ItemDraft.searchKey].
  String get searchKey => plainSearchText(name);
}

/// Writes to the catalogue.
///
/// Separate from [SaleWriter] because the transactions are different shapes,
/// and because a screen that can add an item has no business being able to
/// post a journal entry.

/// A correction to what the shelf says.
///
/// Every one of these carries a reason, and the reason is required rather than
/// optional. A stock figure that can be changed without saying why is a stock
/// figure nobody can defend to an auditor, to a supplier, or to the person who
/// was on the counter that afternoon — and "the numbers are wrong and nobody
/// knows why" is the complaint that makes shopkeepers stop trusting a system
/// and go back to the register.
final class StockAdjustmentDraft {
  /// A stock take: the shelf was counted, and this is what is on it.
  ///
  /// The difference is worked out inside the transaction against the ledger,
  /// so two counters counting at once cannot both write the same correction
  /// from the same stale figure.
  const StockAdjustmentDraft.counted({
    required this.itemId,
    required Qty counted,
    required this.reason,
    this.locationCode = 'MAIN',
  }) : countedQty = counted,
       delta = null;

  /// A known movement: three tins broke, a sack was rat-eaten, a sample went
  /// out. The shelf is not recounted; this much simply left or arrived.
  const StockAdjustmentDraft.byDelta({
    required this.itemId,
    required Qty change,
    required this.reason,
    this.locationCode = 'MAIN',
  }) : delta = change,
       countedQty = null;

  final String itemId;

  /// What was counted, for a stock take. Null for a known movement.
  final Qty? countedQty;

  /// How much moved, for a known movement. Null for a stock take.
  final Qty? delta;

  /// Why. Never blank.
  final String reason;

  final String locationCode;

  /// True when this is a write-off rather than a recount.
  ///
  /// A recount that comes out short and a breakage are the same arithmetic and
  /// different facts, and the ledger says which it was.
  bool get isWriteOff => delta != null;
}

abstract interface class CatalogueWriter {
  /// Adds an item and, when it has opening stock, the ledger row that puts it
  /// on the shelf.
  Future<String> addItem(ActorContext actor, ItemDraft draft);

  /// Edits an item. Prices change forward only: documents already posted keep
  /// the snapshot they were written with.
  Future<void> updateItem(ActorContext actor, String itemId, ItemDraft draft);

  /// Deactivates an item without destroying it, so old invoices keep their
  /// history and the six-year retention obligation is met.
  Future<void> archiveItem(ActorContext actor, String itemId);

  Future<String> addParty(ActorContext actor, PartyDraft draft);

  Future<void> updateParty(
    ActorContext actor,
    String partyId,
    PartyDraft draft,
  );

  /// Hides a customer or supplier. Refused while money is still owed either
  /// way, or the balance disappears from the khata without being settled.
  Future<void> archiveParty(ActorContext actor, String partyId);

  /// Brings an archived item back to the counter.
  ///
  /// Archiving was one-way until this: a shopkeeper who hid the wrong item,
  /// or stopped stocking one and started again, had no way back except
  /// entering it a second time — a duplicate with none of its history.
  Future<void> restoreItem(ActorContext actor, String itemId);

  /// Brings an archived customer or supplier back into the khata.
  Future<void> restoreParty(ActorContext actor, String partyId);

  /// Corrects the shelf, and tells the books about it.
  ///
  /// Not a column write. Stock is a SUM over an append-only ledger, so a
  /// correction is another row on that ledger — which is what makes it
  /// visible in the stock detail report, attributable to whoever made it, and
  /// impossible to make disappear.
  ///
  /// It posts a journal entry too, at the item's weighted-average cost.
  /// Goods that walked off the shelf are an expense whether or not anyone
  /// noticed: without the entry the Inventory account still carries stock
  /// that is not there, the Trial Balance is quietly wrong, and the shop's
  /// profit is overstated by exactly the value of what it lost.
  ///
  /// Returns the id of the stock ledger row.
  Future<String> adjustStock(ActorContext actor, StockAdjustmentDraft draft);

  /// Moves goods between the shop floor and a godown, batch by batch for an
  /// item kept by batch. Nothing is bought or sold, so nothing reaches the
  /// books; the goods are only somewhere else.
  Future<void> transferStock(ActorContext actor, StockTransferDraft draft);

  /// Puts each of [partyIds] in [group], or in no group when it is null or
  /// blank (M40). Returns how many actually moved: one already there is not
  /// written again.
  ///
  /// One transaction, every party its own update through the outbox, so
  /// the other counters on the shop's Wi-Fi receive each move and none of
  /// them can see half a route reassigned.
  Future<int> setPartyGroup(
    ActorContext actor,
    List<String> partyIds,
    String? group,
  );

  /// Renames the group [from] to [to], moving every member, hidden ones
  /// included (M40). Returns how many moved.
  ///
  /// When [to] is a group the shop already has, the two become one: that is
  /// what merging is, and it is the same act — a shopkeeper who renames
  /// "Rt 3" to "Route 3" has merged them whether he meant to or not, and the
  /// screen says so before he does it.
  Future<int> renamePartyGroup(
    ActorContext actor, {
    required String from,
    required String to,
  });
}

/// Goods moved from one place the shop keeps them to another: the shop
/// floor (`MAIN`) and a godown down the street.
final class StockTransferDraft {
  const StockTransferDraft({
    required this.itemId,
    required this.qty,
    required this.from,
    required this.to,
    this.note,
  });

  final String itemId;

  /// In the item's base unit.
  final Qty qty;
  final String from;
  final String to;
  final String? note;
}
