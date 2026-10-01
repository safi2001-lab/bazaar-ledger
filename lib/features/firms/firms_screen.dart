import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../subscription/plans_screen.dart';

final _firmsProvider = FutureProvider.autoDispose<List<FirmProfile>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).queries.firms();
});

/// Every firm whose books this phone keeps, and a way to open another.
///
/// A trader with a retail shop and a wholesale agency next door keeps two
/// sets of books, two sets of khatas and two numberings, on one phone. Each
/// firm is its own: nothing written in one is ever read in the other.
class FirmsScreen extends ConsumerWidget {
  const FirmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final current = services.identity?.firmId;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.firmsTitle)),
      body: SafeArea(
        child: ref
            .watch(_firmsProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 2),
              ),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (firms) => ListView(
                padding: const EdgeInsets.all(BlTokens.space4),
                children: [
                  for (final f in firms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: BlCard(
                        onTap: f.id == current
                            ? null
                            : () => unawaited(_open(context, ref, f)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: t.ink,
                                    ),
                                  ),
                                  if (f.city case final city?)
                                    Text(
                                      city,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: t.inkMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (f.id == current)
                              BlChip(s.firmsCurrent, tone: BlChipTone.good)
                            else
                              Text(
                                s.firmsOpen,
                                style: TextStyle(color: t.accent),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: BlTokens.space3),
                  BlButton(
                    label: s.firmsAdd,
                    icon: Icons.add_business_outlined,
                    kind: BlButtonKind.secondary,
                    onPressed: () async {
                      // How many firms one phone keeps is the plan's (M21).
                      try {
                        ref
                            .read(appServicesProvider)
                            .plans
                            .requireFirmSlot(firms.length);
                      } on PlanRequired catch (refused) {
                        await offerPlan(context, refused);
                        return;
                      }
                      if (!context.mounted) return;
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => const _AddFirmSheet(),
                      );
                    },
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    FirmProfile firm,
  ) async {
    final s = AppStrings.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).switchFirm(firm.id);
      // The bill on the counter belonged to the other firm.
      container.read(cartProvider.notifier).clear();
      container.bumpRefresh();
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(content: Text(s.firmsSwitched(firm.name))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error is PermissionDenied ? error.reason : '$error'),
        ),
      );
    }
  }
}

class _AddFirmSheet extends ConsumerStatefulWidget {
  const _AddFirmSheet();

  @override
  ConsumerState<_AddFirmSheet> createState() => _AddFirmSheetState();
}

class _AddFirmSheetState extends ConsumerState<_AddFirmSheet> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _city = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _owner.text = ref.read(appServicesProvider).currentUser?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = s.firmsName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref
          .read(appServicesProvider)
          .addFirm(
            shopName: _name.text,
            ownerName: _owner.text,
            city: _city.text.trim(),
          );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.firmsAdded(_name.text.trim()))),
      );
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is PermissionDenied ? error.reason : '$error';
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlField(controller: _name, label: s.firmsName, autofocus: true),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _owner, label: s.firmsOwner),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _city, label: s.firmsCity),
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.firmsAdd,
              icon: Icons.add_business_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
