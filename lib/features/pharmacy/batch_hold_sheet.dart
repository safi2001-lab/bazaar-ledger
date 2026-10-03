import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Puts a batch on hold, or lets it be sold again (M49).
///
/// A DRAP recall names a batch; a carton comes in wet; the distributor rings
/// about a batch he sent. Held, first-expiry-first-out passes it by and the
/// counter refuses a pack of it in the words typed here, until somebody who
/// may move stock lets it go. Struck out of nothing: the batch and every
/// strip in it stay where they are, and can still go back to the supplier.
Future<void> showBatchHoldSheet(
  BuildContext context, {
  required String lotId,
  required String lotNo,
  required String itemName,
  String? holdReason,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _BatchHoldSheet(
    lotId: lotId,
    lotNo: lotNo,
    itemName: itemName,
    holdReason: holdReason,
  ),
);

class _BatchHoldSheet extends ConsumerStatefulWidget {
  const _BatchHoldSheet({
    required this.lotId,
    required this.lotNo,
    required this.itemName,
    this.holdReason,
  });

  final String lotId;
  final String lotNo;
  final String itemName;
  final String? holdReason;

  @override
  ConsumerState<_BatchHoldSheet> createState() => _BatchHoldSheetState();
}

class _BatchHoldSheetState extends ConsumerState<_BatchHoldSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final held = widget.holdReason != null;
    if (!held && _reason.text.trim().isEmpty) {
      setState(() => _problem = s.commonRequired);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final pharmacy = ref.read(appServicesProvider).pharmacy;
      if (held) {
        await pharmacy.releaseBatch(widget.lotId);
      } else {
        await pharmacy.holdBatch(widget.lotId, _reason.text);
      }
      container.bumpRefresh();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(held ? s.pharmacyReleaseDone : s.pharmacyHoldDone),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final held = widget.holdReason;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(s.pharmacyHoldTitle(widget.lotNo)),
          Text(
            widget.itemName,
            style: TextStyle(fontSize: 14, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space3),
          if (held != null)
            Text(
              s.pharmacyHeld(held),
              style: TextStyle(fontSize: 15, color: t.danger),
            )
          else
            BlField(
              controller: _reason,
              label: s.pharmacyHoldReason,
              hint: s.pharmacyHoldReasonHint,
              autofocus: true,
            ),
          if (_problem case final problem?) ...[
            const SizedBox(height: BlTokens.space2),
            Text(problem, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: held == null ? s.pharmacyHold : s.pharmacyRelease,
            icon: held == null ? Icons.block : Icons.check_circle_outline,
            kind: held == null ? BlButtonKind.danger : BlButtonKind.primary,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : _go,
          ),
        ],
      ),
    );
  }
}
