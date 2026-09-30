import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Sends waiting bills to FBR every few minutes while the shop is open, for
/// a shop that reports (M19). A counter with no signal simply tries again
/// at the next tick; nothing about billing waits on FBR.
class FbrKeeper extends ConsumerStatefulWidget {
  const FbrKeeper({required this.child, super.key});

  final Widget child;

  static const every = Duration(minutes: 5);

  @override
  ConsumerState<FbrKeeper> createState() => _FbrKeeperState();
}

class _FbrKeeperState extends ConsumerState<FbrKeeper> {
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    if (!(await services.fbr.settings()).enabled || !mounted) return;
    Future<void> tick() async {
      if (_sending) return;
      _sending = true;
      try {
        final r = await services.fbr.sendPending();
        if (r.posted > 0 || r.rejected > 0) container.bumpRefresh();
      } on Object {
        // Tried again at the next tick.
      } finally {
        _sending = false;
      }
    }

    unawaited(tick());
    _timer = Timer.periodic(FbrKeeper.every, (_) => unawaited(tick()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
