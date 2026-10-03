import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'fbr_offline_line.dart';

final _fbrSettingsProvider = FutureProvider.autoDispose<FbrSettings>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).fbr.settings();
});

final _fbrBillsProvider = FutureProvider.autoDispose<List<FbrBill>>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).fbr.bills();
});

/// FBR Digital Invoicing (M19): whether the shop reports its bills, how it
/// reaches FBR, and what FBR has said about each bill.
class FbrScreen extends ConsumerStatefulWidget {
  const FbrScreen({super.key});

  @override
  ConsumerState<FbrScreen> createState() => _FbrScreenState();
}

class _FbrScreenState extends ConsumerState<FbrScreen> {
  final _token = TextEditingController();
  final _baseUrl = TextEditingController();
  bool _enabled = false;
  bool _sandbox = true;
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _token.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  void _load(FbrSettings s) {
    if (_loaded) return;
    _loaded = true;
    _enabled = s.enabled;
    _sandbox = s.sandbox;
    _token.text = s.token;
    _baseUrl.text = s.baseUrl;
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
    } on PermissionDenied catch (e) {
      message = e.reason;
    } on Object catch (e) {
      message = '$e';
    }
    container.bumpRefresh();
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    if (ref.watch(_fbrSettingsProvider).valueOrNull case final settings?) {
      _load(settings);
    }
    final bills = ref.watch(_fbrBillsProvider).valueOrNull ?? const [];
    final now = services.clock.nowUtc();
    final time = DateFormat('d MMM, h:mm a');

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.fbrTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlOfflineNote(message: s.fbrWhatIsSent),
            SwitchListTile.adaptive(
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.fbrReport),
            ),
            SwitchListTile.adaptive(
              value: _sandbox,
              onChanged: (v) => setState(() => _sandbox = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.fbrSandbox),
            ),
            BlField(controller: _token, label: s.fbrToken),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _baseUrl,
              label: s.fbrBaseUrl,
              hint: FbrClient.defaultBaseUrl,
            ),
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.fbrSave,
              icon: Icons.check,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run(() async {
                        await services.fbr.save(
                          FbrSettings(
                            enabled: _enabled,
                            sandbox: _sandbox,
                            token: _token.text,
                            baseUrl: _baseUrl.text,
                          ),
                        );
                        return s.fbrSaved;
                      }),
                    ),
            ),
            if (_message case final message?) ...[
              const SizedBox(height: BlTokens.space2),
              Text(message, style: TextStyle(fontSize: 14, color: t.ink)),
            ],
            const SizedBox(height: BlTokens.space4),
            Row(
              children: [
                Expanded(child: BlSectionHeader(s.fbrBills)),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _run(() async {
                            final r = await services.fbr.sendPending();
                            return s.fbrSent(
                              '${r.posted}',
                              '${r.rejected}',
                              '${r.waiting}',
                            );
                          }),
                        ),
                  child: Text(s.fbrSendNow),
                ),
              ],
            ),
            // Rule 150XC (M59): bills issued offline, and those late.
            const FbrOfflineSummary(),
            for (final b in bills)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: BlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.docNo,
                              style: TextStyle(fontSize: 15, color: t.ink),
                            ),
                          ),
                          BlChip(
                            switch (b.status) {
                              'posted' => s.fbrPosted,
                              'rejected' => s.fbrRejected,
                              _ => s.fbrPending,
                            },
                            tone: switch (b.status) {
                              'posted' => BlChipTone.good,
                              'rejected' => BlChipTone.warn,
                              _ => BlChipTone.neutral,
                            },
                          ),
                        ],
                      ),
                      Text(
                        time.format(b.madeAtUtc.toLocal()),
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                      if (b.fbrInvoiceNo case final no?)
                        SelectableText(
                          no,
                          style: TextStyle(fontSize: 13, color: t.ink),
                        ),
                      // Rule 150XC (M59): issued while FBR could not be
                      // reached, and late a day after it could again.
                      if (b.isOfflineOverdue(now))
                        Text(
                          s.fbrOverdueBadge,
                          style: TextStyle(fontSize: 12, color: t.danger),
                        )
                      else if (b.isOffline)
                        Text(
                          s.fbrOfflineBadge,
                          style: TextStyle(fontSize: 12, color: t.warning),
                        ),
                      if (b.isLate(now))
                        Text(
                          s.fbrLate,
                          style: TextStyle(fontSize: 12, color: t.danger),
                        ),
                      if (b.error case final error? when b.status != 'posted')
                        Text(
                          error,
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                      if (b.status == 'rejected')
                        TextButton(
                          onPressed: () => unawaited(
                            _run(() async {
                              await services.fbr.retry(b.documentId);
                              return null;
                            }),
                          ),
                          child: Text(s.fbrRetry),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
