import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'pin_field.dart';

/// Everybody who can sign in, owner first.
final _signInListProvider = FutureProvider.autoDispose<List<StaffMember>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return [
    for (final m in await services.staffStore.staff(firm.id))
      if (m.isActive && m.hasPin) m,
  ];
});

/// Who is at the phone. Shown when the app opens in a shop where anybody
/// has a PIN, and whenever somebody locks it.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _pin = TextEditingController();
  StaffMember? _who;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final who = _who;
    if (who == null || _busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final ok = await ref.read(appServicesProvider).signIn(who.id, _pin.text);
      if (!mounted) return;
      if (ok) {
        container.bumpRefresh();
        return;
      }
      _pin.clear();
      setState(() {
        _busy = false;
        _error = s.signInWrong;
      });
    } on PermissionDenied catch (denied) {
      if (!mounted) return;
      _pin.clear();
      setState(() {
        _busy = false;
        _error = denied.reason;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final people = ref.watch(_signInListProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.signInTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: people.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (rows) => ListView(
            padding: const EdgeInsets.all(BlTokens.space4),
            children: [
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final m in rows)
                    ChoiceChip(
                      selected: _who?.id == m.id,
                      label: Text('${m.name} · ${roleName(s, m.role)}'),
                      onSelected: (_) => setState(() {
                        _who = m;
                        _error = null;
                      }),
                    ),
                ],
              ),
              if (_who != null) ...[
                const SizedBox(height: BlTokens.space4),
                PinField(
                  controller: _pin,
                  label: s.signInPin,
                  autofocus: true,
                  onSubmitted: (_) => unawaited(_open()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    _error!,
                    style: TextStyle(color: t.danger, fontSize: 14),
                  ),
                ],
                const SizedBox(height: BlTokens.space4),
                BlButton(
                  label: s.signInOpen,
                  icon: Icons.lock_open_outlined,
                  big: true,
                  busy: _busy,
                  onPressed: _busy ? null : () => unawaited(_open()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
