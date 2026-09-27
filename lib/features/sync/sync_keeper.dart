import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// Keeps sync going while the shop is open: a master that was hosting hosts
/// again, and shows what the counters send as it arrives; a counter syncs
/// with its master every half minute.
class SyncKeeper extends ConsumerStatefulWidget {
  const SyncKeeper({required this.child, super.key});

  final Widget child;

  static const every = Duration(seconds: 30);

  @override
  ConsumerState<SyncKeeper> createState() => _SyncKeeperState();
}

class _SyncKeeperState extends ConsumerState<SyncKeeper> {
  StreamSubscription<ApplyResult>? _received;
  Timer? _timer;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    await services.sync.resume();
    _received = services.sync.received.listen((_) => container.bumpRefresh());
    if (!await services.sync.isCounter() || !mounted) return;
    _timer = Timer.periodic(SyncKeeper.every, (_) async {
      if (_syncing || services.isLocked) return;
      _syncing = true;
      try {
        final report = await services.sync.syncNow();
        if (report.received.applied > 0) container.bumpRefresh();
      } on Object {
        // The master is off or out of range. The next tick tries again, and
        // the counter goes on billing meanwhile.
      } finally {
        _syncing = false;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_received?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
