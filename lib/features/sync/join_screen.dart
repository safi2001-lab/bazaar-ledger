import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Joining a shop's master phone as a counter: its address, the code it
/// shows, and a name for this counter.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  /// `192.168.1.5` or `192.168.1.5:47470`.
  (String, int) _hostAndPort() {
    final text = _address.text.trim();
    final colon = text.lastIndexOf(':');
    if (colon > 0) {
      final port = int.tryParse(text.substring(colon + 1));
      if (port != null) return (text.substring(0, colon), port);
    }
    return (text, defaultSyncPort);
  }

  Future<void> _join() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final (host, port) = _hostAndPort();
      final name = _name.text.trim();
      await ref
          .read(appServicesProvider)
          .sync
          .join(
            host: host,
            port: port,
            code: _code.text.trim(),
            label: name.isEmpty ? s.syncCounterNameHint : name,
          );
      container.bumpRefresh();
      navigator.popUntil((r) => r.isFirst);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
          SyncRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.syncJoinTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlOfflineNote(message: s.syncJoinHint),
            const SizedBox(height: BlTokens.space4),
            BlField(
              controller: _address,
              label: s.syncMasterAddress,
              hint: '192.168.1.5',
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _code, label: s.syncCode, numeric: true),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _name,
              label: s.syncCounterName,
              hint: s.syncCounterNameHint,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: BlTokens.space3),
              Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space5),
            BlButton(
              label: s.syncJoin,
              icon: Icons.link,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_join()),
            ),
          ],
        ),
      ),
    );
  }
}
