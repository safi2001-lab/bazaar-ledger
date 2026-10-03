import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/when.dart';
import '../expenses/shop_money_providers.dart';

/// What the shop has hidden, and a way to bring it back.
///
/// Nothing in this app is ever deleted — six-year retention is a legal
/// obligation, and an old bill has to keep pointing at the item it sold —
/// but until this, hiding was one-way. A shopkeeper who archived the wrong
/// item, or stopped stocking one and started again, could only enter it a
/// second time: a duplicate with none of its history, and a stock count
/// split across two rows.
///
/// ## Everything, since M60
///
/// M5 brought back items and customers. The shop has since learned to hide
/// expense heads and heads of income (M47), switch staff off (M9), and now
/// to put away a van (M18) or a recipe (M17) and to take a photograph off
/// an entry. All of it is here, each with when it went in and who put it
/// there — read from the activity log the act itself wrote — and each back
/// with one tap, through the service that always held it, under the
/// permission that always guarded it. A section the person at the phone may
/// not bring back from is not shown to them at all.
///
/// Nothing is ever emptied. Thirty days, as Business Khata keeps, is a
/// clock that one day takes back a customer whose bills still point at
/// them; the books need the rows for six years, so the bin keeps them for
/// as long as the books do, and says so.
final archivedItemsProvider = FutureProvider.autoDispose<List<ItemSummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.archivedItems(firm.id);
});

final archivedPartiesProvider = FutureProvider.autoDispose<List<PartySummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.archivedParties(firm.id);
});

/// One section's rows, or none when the person at the phone may not bring
/// them back — the bin is never a way round a permission.
AutoDisposeFutureProvider<List<T>> _hidden<T>(
  bool Function(AppServices services) may,
  Future<List<T>> Function(AppServices services) read,
) => FutureProvider.autoDispose<List<T>>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !may(services)) return const [];
  return read(services);
});

final _expenseHeadsProvider = _hidden<ExpenseHead>(
  (s) => s.can(Permission.journal) && s.can(Permission.expenses),
  (s) async => [
    for (final h in await s.shopMoney.expenseHeads())
      if (h.hidden) h,
  ],
);

final _incomeHeadsProvider = _hidden<IncomeHead>(
  (s) => s.can(Permission.journal) && s.can(Permission.expenses),
  (s) async => [
    for (final h in await s.shopMoney.incomeHeads())
      if (h.hidden) h,
  ],
);

final _staffProvider = _hidden<StaffMember>(
  (s) => s.can(Permission.manageUsers),
  (s) => s.recycle.switchedOffStaff(),
);

// M65: the staff book's people, for whoever keeps it.
final _employeesProvider = _hidden<Employee>(
  (s) => s.staffBook.mayKeep,
  (s) => s.staffBook.hiddenEmployees(),
);

final _vansProvider = _hidden<HiddenVan>(
  (s) => s.recycle.mayPutVansAway,
  (s) => s.recycle.hiddenVans(),
);

final _recipesProvider = _hidden<HiddenRecipe>(
  (s) => s.recycle.mayPutRecipesAway,
  (s) => s.recycle.hiddenRecipes(),
);

final _photosProvider = _hidden<RemovedPhoto>(
  (s) => true,
  (s) async => [
    for (final p in await s.photos.removed())
      if (s.photos.mayRestore(p)) p,
  ],
);

final _marksProvider = FutureProvider.autoDispose<Map<String, HiddenMark>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const {};
  return services.recycle.marks();
});

class RecycleScreen extends ConsumerWidget {
  const RecycleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final items = ref.watch(archivedItemsProvider);
    final parties = ref.watch(archivedPartiesProvider);
    final heads = ref.watch(_expenseHeadsProvider);
    final incomes = ref.watch(_incomeHeadsProvider);
    final staff = ref.watch(_staffProvider);
    final vans = ref.watch(_vansProvider);
    final recipes = ref.watch(_recipesProvider);
    final photos = ref.watch(_photosProvider);
    final employees = ref.watch(_employeesProvider); // M65
    final marks = ref.watch(_marksProvider).valueOrNull ?? const {};

    final sections = [
      items,
      parties,
      heads,
      incomes,
      staff,
      vans,
      recipes,
      employees, // M65
    ];
    final loaded = sections.every((a) => a.hasValue) && photos.hasValue;
    final empty =
        loaded &&
        sections.every((a) => a.requireValue.isEmpty) &&
        photos.requireValue.isEmpty;

    HiddenMark? mark(String table, String id) => marks['$table/$id'];

    List<Widget> section<T>(
      String title,
      AsyncValue<List<T>> rows,
      Widget Function(T row) build,
    ) {
      final list = rows.valueOrNull ?? const [];
      if (list.isEmpty) return const [];
      return [
        BlSectionHeader(title),
        const SizedBox(height: BlTokens.space2),
        for (final row in list) build(row),
        const SizedBox(height: BlTokens.space4),
      ];
    }

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.recycleTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            if (!loaded)
              const BlSkeletonList(rows: 3)
            else if (empty)
              BlEmpty(icon: Icons.inventory_2_outlined, title: s.recycleEmpty)
            else ...[
              ...section(
                s.recycleItems,
                items,
                (item) => _HiddenRow(
                  name: item.name,
                  detail: item.saleRate.amountOnly,
                  mark: mark('items', item.id),
                  restore: (services) => services.catalogue.restoreItem(
                    services.actorNow(),
                    item.id,
                  ),
                ),
              ),
              ...section(
                s.recycleParties,
                parties,
                (party) => _HiddenRow(
                  name: party.name,
                  detail: party.phone,
                  mark: mark('parties', party.id),
                  restore: (services) => services.catalogue.restoreParty(
                    services.actorNow(),
                    party.id,
                  ),
                ),
              ),
              ...section(
                s.headsExpense,
                heads,
                (head) => _HiddenRow(
                  name: expenseHeadName(s, head),
                  mark: mark('accounts', head.accountId),
                  restore: (services) => services.shopMoney
                      .setExpenseHeadHidden(head.accountId, false),
                ),
              ),
              ...section(
                s.headsIncome,
                incomes,
                (head) => _HiddenRow(
                  name: incomeHeadName(s, head),
                  mark: mark('settings', head.key),
                  restore: (services) =>
                      services.shopMoney.setIncomeHeadHidden(head.key, false),
                ),
              ),
              ...section(
                s.usersTitle,
                staff,
                (member) => _HiddenRow(
                  name: member.name,
                  mark: mark('users', member.id),
                  restore: (services) =>
                      services.setStaffActive(member.id, active: true),
                ),
              ),
              // M65
              ...section(
                s.staffBookTitle,
                employees,
                (man) => _HiddenRow(
                  name: man.name,
                  mark: mark('employees', man.id),
                  restore: (services) => services.staffBook.restore(man.id),
                ),
              ),
              ...section(
                s.vansTitle,
                vans,
                (van) => _HiddenRow(
                  name: van.name,
                  detail: van.locationCode,
                  mark: mark('vans', van.id),
                  restore: (services) => services.recycle.restoreVan(van.id),
                ),
              ),
              ...section(
                s.recipesTitle,
                recipes,
                (recipe) => _HiddenRow(
                  name: recipe.name,
                  detail: recipe.outputName,
                  mark: mark('boms', recipe.id),
                  restore: (services) =>
                      services.recycle.restoreRecipe(recipe.id),
                ),
              ),
              ...section(
                s.recyclePhotos,
                photos,
                (photo) => _HiddenRow(
                  key: ValueKey('removed-photo-${photo.id}'),
                  name: photo.ownerLabel.isEmpty
                      ? s.recyclePhotoOfShop
                      : s.recyclePhotoFrom(photo.ownerLabel),
                  mark: HiddenMark(
                    atUtc: photo.removedAtUtc,
                    by: photo.removedBy,
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(BlTokens.radiusSm),
                    child: Image.memory(
                      photo.bytes,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                      excludeFromSemantics: true,
                    ),
                  ),
                  restore: (services) => services.photos.restore(photo),
                ),
              ),
            ],
            if (loaded) ...[
              const SizedBox(height: BlTokens.space2),
              Text(
                s.recycleKeptNote,
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HiddenRow extends ConsumerStatefulWidget {
  const _HiddenRow({
    super.key,
    required this.name,
    required this.restore,
    this.detail,
    this.mark,
    this.leading,
  });

  final String name;
  final String? detail;

  /// When it went into the bin and who put it there, when the activity log
  /// knows. Something hidden before M42 kept field-level history may have
  /// no row naming it; it is still brought back the same way.
  final HiddenMark? mark;

  final Widget? leading;
  final Future<void> Function(AppServices services) restore;

  @override
  ConsumerState<_HiddenRow> createState() => _HiddenRowState();
}

class _HiddenRowState extends ConsumerState<_HiddenRow> {
  bool _busy = false;

  Future<void> _bringBack() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.restore(services);
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.recycleRestored(widget.name))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error) {
            PhotoRefused(:final reason) => reason,
            PermissionDenied(:final reason) => reason,
            HeadRefused(:final reason) => reason,
            StaffRefused(:final reason) => reason, // M65
            _ => '${s.commonSomethingWentWrong}: $error',
          }),
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mark = widget.mark;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        child: Row(
          children: [
            if (widget.leading case final leading?) ...[
              leading,
              const SizedBox(width: BlTokens.space3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  if (widget.detail case final detail?
                      when detail.trim().isNotEmpty)
                    Text(
                      detail,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  if (mark != null)
                    Text(
                      s.recycleHiddenBy(
                        mark.by,
                        shopTime(mark.atUtc.millisecondsSinceEpoch),
                      ),
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            BlButton(
              label: s.recycleRestore,
              icon: Icons.restore,
              kind: BlButtonKind.secondary,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_bringBack()),
            ),
          ],
        ),
      ),
    );
  }
}
