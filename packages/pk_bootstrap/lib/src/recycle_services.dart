part of 'app_services.dart';

/// Everything a shopkeeper can hide, and bringing it back (M60).
///
/// The recycle bin's own work: putting away what had no way to be put away
/// before (a van, a recipe), reading what else is hidden, and when and by
/// whom each went in. Items, customers, heads, staff and photographs are
/// hidden and brought back by the services that always held them —
/// [CatalogueWriter], [ShopMoneyServices], [AppServices.setStaffActive],
/// [EntryPhotoServices] — under the permissions those already ask, so the
/// bin cannot become a side door round any of them.
///
/// Nothing is ever emptied from it. A hidden thing has history the books
/// must keep for six years, so it stays restorable for as long as the books
/// do.
final class RecycleServices {
  RecycleServices._(this._app);

  final AppServices _app;

  DriftHiddenThings get _things =>
      DriftHiddenThings(_app.database, () => _app._runner);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('This device has no shop yet.');
    return id.firmId;
  }

  /// When each hidden thing went into the bin and who put it there, keyed
  /// `table/id` as its hiding act's audit row names it.
  Future<Map<String, HiddenMark>> marks() => _things.hiddenMarks(_firmId);

  // ---------------------------------------------------------------------
  // Vans (M18): the shop's setup, so the owner's.
  // ---------------------------------------------------------------------

  bool get mayPutVansAway => _app.can(Permission.settings);

  /// Puts a van away. Refused with [VanRefused] while goods are on it or a
  /// phone sells from it.
  Future<void> hideVan(String vanId) async {
    _app.require(Permission.settings);
    await _things.hideVan(_app.actorNow(), vanId);
  }

  Future<void> restoreVan(String vanId) async {
    _app.require(Permission.settings);
    await _things.restoreVan(_app.actorNow(), vanId);
  }

  Future<List<HiddenVan>> hiddenVans() => _things.hiddenVans(_firmId);

  // ---------------------------------------------------------------------
  // Recipes (M17): whoever may make things may put a recipe away.
  // ---------------------------------------------------------------------

  bool get mayPutRecipesAway => _app.can(Permission.purchases);

  Future<void> hideRecipe(String bomId) async {
    _app.require(Permission.purchases);
    await _things.hideRecipe(_app.actorNow(), bomId);
  }

  Future<void> restoreRecipe(String bomId) async {
    _app.require(Permission.purchases);
    await _things.restoreRecipe(_app.actorNow(), bomId);
  }

  Future<List<HiddenRecipe>> hiddenRecipes() => _things.hiddenRecipes(_firmId);

  // ---------------------------------------------------------------------
  // Staff (M9): read here, let back in by setStaffActive.
  // ---------------------------------------------------------------------

  /// The staff who can no longer sign in. Only for whoever manages staff:
  /// the bin is not a way round the staff screen's own permission.
  Future<List<StaffMember>> switchedOffStaff() async {
    if (!_app.can(Permission.manageUsers)) return const [];
    final everyone = await _app.staffStore.staff(_firmId);
    return [
      for (final m in everyone)
        if (!m.isActive) m,
    ];
  }
}
