import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What the sync screen shows: which side of sync this phone is, and the
/// shop's phones.
final class SyncView {
  const SyncView({
    required this.isCounter,
    required this.master,
    required this.devices,
    required this.conflicts,
    required this.addresses,
  });

  final bool isCounter;
  final ({String host, int port})? master;
  final List<SyncDevice> devices;
  final int conflicts;
  final List<String> addresses;
}

final syncViewProvider = FutureProvider.autoDispose<SyncView>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final sync = services.sync;
  return SyncView(
    isCounter: await sync.isCounter(),
    master: await sync.master(),
    devices: await sync.devices(),
    conflicts: await sync.conflicts(),
    addresses: sync.isHosting ? await SyncServices.addresses() : const [],
  );
});

/// Counters on the shop's wi-fi: on the master, letting them join and
/// serving them; on a counter, syncing with the master.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _message;
  String? _code;
  Timer? _watchJoin;

  @override
  void dispose() {
    _watchJoin?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    String? message;
    try {
      message = await action();
    } on SyncRefused catch (e) {
      message = e.reason;
    } on PermissionDenied catch (e) {
      message = e.reason;
    } on Object catch (e) {
      message = '$e';
    }
    container.bumpRefresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  Future<String?> _setHosting(bool on) async {
    final sync = ref.read(appServicesProvider).sync;
    if (on) {
      await sync.startHosting();
    } else {
      _watchJoin?.cancel();
      _code = null;
      await sync.stopHosting();
    }
    return null;
  }

  void _letJoin() {
    final services = ref.read(appServicesProvider);
    try {
      setState(() => _code = services.sync.openJoining());
    } on SyncRefused catch (e) {
      setState(() => _message = e.reason);
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    _watchJoin?.cancel();
    // The code is spent when a counter joins with it; the list then has one
    // more phone in it.
    _watchJoin = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (services.sync.pairingCode != null) return;
      timer.cancel();
      container.bumpRefresh();
      if (mounted) setState(() => _code = null);
    });
  }

  Future<String?> _syncNow(AppStrings s) async {
    final report = await ref.read(appServicesProvider).sync.syncNow();
    return s.syncDone('${report.sent.applied}', '${report.received.applied}');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final view = ref.watch(syncViewProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.syncTitle)),
      body: SafeArea(
        child: view.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (v) => ListView(
            padding: const EdgeInsets.all(BlTokens.space4),
            children: [
              BlOfflineNote(message: s.syncStaysInShop),
              const SizedBox(height: BlTokens.space3),
              if (v.isCounter) ...[
                Text(
                  s.syncCounterOf(v.master?.host ?? '—'),
                  style: TextStyle(fontSize: 15, color: t.ink),
                ),
                const SizedBox(height: BlTokens.space3),
                BlButton(
                  label: s.syncNow,
                  icon: Icons.sync,
                  big: true,
                  busy: _busy,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_run(() => _syncNow(s))),
                ),
              ] else ...[
                SwitchListTile.adaptive(
                  value: services.sync.isHosting,
                  onChanged: _busy || !services.can(Permission.settings)
                      ? null
                      : (on) => unawaited(_run(() => _setHosting(on))),
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.syncHostSwitch),
                  subtitle: Text(s.syncHostHint),
                ),
                if (services.sync.isHosting) ...[
                  const SizedBox(height: BlTokens.space2),
                  BlCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.syncAddress,
                          style: TextStyle(fontSize: 13, color: t.inkMuted),
                        ),
                        if (v.addresses.isEmpty)
                          Text(
                            s.syncNoAddress,
                            style: TextStyle(fontSize: 15, color: t.ink),
                          ),
                        for (final a in v.addresses)
                          SelectableText(
                            '$a:${services.sync.port}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  if (_code case final code?)
                    BlCard(
                      child: Column(
                        children: [
                          Text(
                            s.syncJoinCode,
                            style: TextStyle(fontSize: 13, color: t.inkMuted),
                          ),
                          Text(
                            code,
                            style: TextStyle(
                              fontSize: 36,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    BlButton(
                      label: s.syncLetJoin,
                      icon: Icons.add_to_home_screen_outlined,
                      kind: BlButtonKind.secondary,
                      onPressed: _letJoin,
                    ),
                ],
              ],
              if (_message case final message?) ...[
                const SizedBox(height: BlTokens.space3),
                Text(message, style: TextStyle(fontSize: 14, color: t.ink)),
              ],
              if (v.conflicts > 0) ...[
                const SizedBox(height: BlTokens.space3),
                BlChip(
                  s.syncConflicts('${v.conflicts}'),
                  tone: BlChipTone.warn,
                ),
              ],
              const SizedBox(height: BlTokens.space4),
              BlSectionHeader(s.syncDevices),
              const SizedBox(height: BlTokens.space2),
              for (final d in v.devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space2),
                  child: BlCard(
                    child: Row(
                      children: [
                        Icon(
                          d.role == 'master'
                              ? Icons.dns_outlined
                              : Icons.point_of_sale_outlined,
                          color: t.inkMuted,
                        ),
                        const SizedBox(width: BlTokens.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.label,
                                style: TextStyle(fontSize: 15, color: t.ink),
                              ),
                              Text(
                                [
                                  d.role == 'master'
                                      ? s.syncMasterRole
                                      : s.syncCounterRole(d.prefix),
                                  if (d.isThisDevice)
                                    s.syncThisPhone
                                  else if (d.lastSyncedAt case final at?)
                                    s.syncLastSynced(
                                      DateFormat(
                                        'd MMM, h:mm a',
                                      ).format(at.toLocal()),
                                    )
                                  else
                                    s.syncNever,
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: t.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
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
