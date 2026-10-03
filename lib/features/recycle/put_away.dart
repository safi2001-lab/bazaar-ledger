import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Putting away a van the shop sold, or a recipe it stopped making (M60).
///
/// Until now neither could go anywhere: a van sold two years ago stayed in
/// the list of places a phone could sell from, and a masala the shop no
/// longer makes stayed at the top of Making. Each page carries one of these
/// in its bar — one marked line in a file that belongs to M17 or M18 — and
/// what is put away waits in the recycle bin, a tap from coming back.
///
/// Asked once, in words that say nothing is lost; with Data Lock on, the
/// write path asks a PIN as well (M42).
Future<bool> _confirm(BuildContext context, String words) async {
  final s = AppStrings.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(words),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.commonNo),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(s.commonYes),
        ),
      ],
    ),
  );
  return sure ?? false;
}

String _refusal(AppStrings s, Object error) => switch (error) {
  VanRefused(:final reason) => reason,
  AssemblyRefused(:final reason) => reason,
  PermissionDenied(:final reason) => reason,
  ApprovalNeeded() => '$error',
  _ => '${s.commonSomethingWentWrong}: $error',
};

/// Puts [put] away after asking, then leaves the page it was on.
Future<void> _putAway(
  BuildContext context, {
  required String confirm,
  required String done,
  required Future<void> Function(AppServices services) put,
  required AppServices services,
}) async {
  if (!await _confirm(context, confirm) || !context.mounted) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final s = AppStrings.of(context);
  try {
    await put(services);
    container.bumpRefresh();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    navigator.pop();
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(_refusal(s, error))));
  }
}

/// The van page's "put away", for whoever sets the shop up.
class PutVanAwayButton extends ConsumerWidget {
  const PutVanAwayButton({super.key, required this.van});

  final VanView van;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final services = ref.watch(appServicesProvider);
    if (!services.recycle.mayPutVansAway) return const SizedBox.shrink();
    return BlIconButton(
      icon: Icons.archive_outlined,
      label: s.vanPutAway,
      colour: context.bl.danger,
      onPressed: () => unawaited(
        _putAway(
          context,
          confirm: s.vanPutAwayConfirm,
          done: s.vanPutAwayDone,
          services: services,
          put: (services) => services.recycle.hideVan(van.id),
        ),
      ),
    );
  }
}

/// The recipe page's "put away", for whoever may make things.
class PutRecipeAwayButton extends ConsumerWidget {
  const PutRecipeAwayButton({super.key, required this.recipe});

  /// Null while a recipe is being written for the first time: there is
  /// nothing to put away yet.
  final BomView? recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final services = ref.watch(appServicesProvider);
    final recipe = this.recipe;
    if (recipe == null || !services.recycle.mayPutRecipesAway) {
      return const SizedBox.shrink();
    }
    return BlIconButton(
      icon: Icons.archive_outlined,
      label: s.recipePutAway,
      colour: context.bl.danger,
      onPressed: () => unawaited(
        _putAway(
          context,
          confirm: s.recipePutAwayConfirm,
          done: s.recipePutAwayDone,
          services: services,
          put: (services) => services.recycle.hideRecipe(recipe.id),
        ),
      ),
    );
  }
}
