import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';

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
    this.mrp,
    this.hsCode,
    this.openingStock = Qty.zero,
    this.openingRate = Rate.zero,
    this.minStock = Qty.zero,
    this.tracksStock = true,
    this.isActive = true,
  });

  final String name;
  final String? code;
  final String? barcode;
  final String? category;
  final String? description;

  final String baseUnitId;
  final Rate saleRate;
  final Rate? purchaseRate;
  final Rate? wholesaleRate;
  final Money? mrp;
  final String? hsCode;

  final Qty openingStock;
  final Rate openingRate;
  final Qty minStock;
  final bool tracksStock;
  final bool isActive;

  /// Lowercased, punctuation-stripped, space-collapsed — what type-ahead
  /// matches against, and what M1's FTS5 index is built over.
  String get searchKey => name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  });

  final String name;
  final String partyType;
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

  String get searchKey => name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Writes to the catalogue.
///
/// Separate from [SaleWriter] because the transactions are different shapes,
/// and because a screen that can add an item has no business being able to
/// post a journal entry.
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

  Future<void> archiveParty(ActorContext actor, String partyId);
}
