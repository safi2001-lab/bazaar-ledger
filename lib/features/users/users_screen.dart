import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'pin_field.dart';

final _staffProvider = FutureProvider.autoDispose<List<StaffMember>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.staffStore.staff(firm.id);
});

/// The owner's list of who works in the shop, what each may do, and their
/// PINs.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final me = services.currentUser;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.usersTitle)),
      body: SafeArea(
        child: ref
            .watch(_staffProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 3),
              ),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) => ListView(
                padding: const EdgeInsets.all(BlTokens.space4),
                children: [
                  BlButton(
                    label: s.usersMyPin,
                    icon: Icons.pin_outlined,
                    kind: BlButtonKind.secondary,
                    onPressed: me == null
                        ? null
                        : () => unawaited(
                            _sheet(context, _PinSheet(userId: me.id)),
                          ),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  BlButton(
                    label: s.usersAdd,
                    icon: Icons.person_add_alt_outlined,
                    onPressed: () =>
                        unawaited(_sheet(context, const _AddSheet())),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  for (final m in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: BlCard(
                        onTap: m.role == Role.owner
                            ? null
                            : () => unawaited(
                                _sheet(context, _MemberSheet(member: m)),
                              ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: t.ink,
                                    ),
                                  ),
                                  Text(
                                    roleName(s, m.role),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!m.isActive)
                              BlChip(s.usersInactive)
                            else if (!m.hasPin)
                              BlChip(s.usersNoPin, tone: BlChipTone.warn),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }
}

Future<void> _sheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: BlTokens.space4,
          right: BlTokens.space4,
          top: BlTokens.space4,
          bottom:
              MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom +
              BlTokens.space4,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );

/// Checks two typed PINs, returning the words to show when they will not do.
String? _pinProblem(AppStrings s, String pin, String again) {
  if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return s.usersPinInvalid;
  if (pin != again) return s.usersPinMismatch;
  return null;
}

String _reasonOf(Object error) =>
    error is PermissionDenied ? error.reason : '$error';

/// A new PIN for [userId]: the owner's own, or one the owner resets.
class _PinSheet extends ConsumerStatefulWidget {
  const _PinSheet({required this.userId});

  final String userId;

  @override
  ConsumerState<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends ConsumerState<_PinSheet> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final problem = _pinProblem(s, _pin.text, _again.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).setPin(widget.userId, _pin.text);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.usersPinSaved)));
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reasonOf(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PinField(controller: _pin, label: s.usersPin, autofocus: true),
        const SizedBox(height: BlTokens.space3),
        PinField(controller: _again, label: s.usersPinAgain),
        if (_error != null) ...[
          const SizedBox(height: BlTokens.space2),
          Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
        ],
        const SizedBox(height: BlTokens.space4),
        BlButton(
          label: s.actionSave,
          icon: Icons.check,
          big: true,
          busy: _busy,
          onPressed: _busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}

/// Role chips for staff: never owner, which there is one of.
class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.onChanged});

  final Role role;
  final ValueChanged<Role> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Wrap(
      spacing: BlTokens.space2,
      children: [
        for (final r in [Role.cashier, Role.accountant, Role.manager])
          ChoiceChip(
            selected: r == role,
            label: Text(roleName(s, r)),
            onSelected: (_) => onChanged(r),
          ),
      ],
    );
  }
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _again = TextEditingController();
  Role _role = Role.cashier;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final problem = _name.text.trim().isEmpty
        ? s.usersName
        : _pinProblem(s, _pin.text, _again.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref
          .read(appServicesProvider)
          .addStaff(name: _name.text, role: _role, pin: _pin.text);
      container.bumpRefresh();
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reasonOf(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final ownerHasPin = services.currentUser?.hasPin ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ownerHasPin) ...[
          BlOfflineNote(message: s.usersOwnerPinFirst),
          const SizedBox(height: BlTokens.space3),
        ],
        BlField(controller: _name, label: s.usersName, autofocus: true),
        const SizedBox(height: BlTokens.space3),
        _RolePicker(role: _role, onChanged: (r) => setState(() => _role = r)),
        const SizedBox(height: BlTokens.space3),
        PinField(controller: _pin, label: s.usersPin),
        const SizedBox(height: BlTokens.space3),
        PinField(controller: _again, label: s.usersPinAgain),
        if (_error != null) ...[
          const SizedBox(height: BlTokens.space2),
          Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
        ],
        const SizedBox(height: BlTokens.space4),
        BlButton(
          label: s.usersAdd,
          icon: Icons.person_add_alt_outlined,
          big: true,
          busy: _busy,
          onPressed: _busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}

class _MemberSheet extends ConsumerStatefulWidget {
  const _MemberSheet({required this.member});

  final StaffMember member;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function(AppServices services) work) async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await work(ref.read(appServicesProvider));
      container.bumpRefresh();
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reasonOf(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final m = widget.member;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          m.name,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
        const SizedBox(height: BlTokens.space3),
        Text(s.usersRole, style: TextStyle(fontSize: 13, color: t.inkMuted)),
        const SizedBox(height: BlTokens.space1),
        _RolePicker(
          role: m.role,
          onChanged: (r) =>
              unawaited(_run((services) => services.setStaffRole(m.id, r))),
        ),
        const SizedBox(height: BlTokens.space4),
        BlButton(
          label: s.usersNewPin,
          icon: Icons.pin_outlined,
          kind: BlButtonKind.secondary,
          onPressed: _busy
              ? null
              : () {
                  Navigator.of(context).pop();
                  unawaited(_sheet(context, _PinSheet(userId: m.id)));
                },
        ),
        const SizedBox(height: BlTokens.space2),
        BlButton(
          label: m.isActive ? s.usersRemove : s.usersLetBack,
          icon: m.isActive ? Icons.person_off_outlined : Icons.person_outline,
          kind: m.isActive ? BlButtonKind.danger : BlButtonKind.secondary,
          busy: _busy,
          onPressed: _busy
              ? null
              : () => unawaited(
                  _run(
                    (services) =>
                        services.setStaffActive(m.id, active: !m.isActive),
                  ),
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: BlTokens.space2),
          Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
        ],
      ],
    );
  }
}
