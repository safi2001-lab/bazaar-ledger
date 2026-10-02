import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Which sheet of a bill goes out (M51): the original, a duplicate, a
/// triplicate, or the transporter's copy with no prices.
///
/// Nothing is chosen until somebody chooses, and then the bill goes out as
/// it always has: the first print is the original and plain, anything sent
/// after it is marked as the duplicate (M30), and asking to print twice
/// still hands over one receipt. A wholesaler printing the carbon-book set
/// picks each sheet in turn.
///
/// The original is not offered once it has been printed: a second
/// "original" is the sheet a buyer claims input tax on twice.
class CopyChooser extends StatelessWidget {
  const CopyChooser({
    super.key,
    required this.value,
    required this.onChanged,
    required this.originalPrinted,
    required this.offerTransporter,
  });

  final ReceiptCopy? value;
  final ValueChanged<ReceiptCopy?> onChanged;
  final bool originalPrinted;

  /// Only where goods leave on the paper: a sale bill or a challan.
  final bool offerTransporter;

  static String label(AppStrings s, ReceiptCopy copy) => switch (copy) {
    ReceiptCopy.original => s.copyOriginal,
    ReceiptCopy.duplicate => s.copyDuplicate,
    ReceiptCopy.triplicate => s.copyTriplicate,
    ReceiptCopy.transporter => s.copyTransporter,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final gone = originalPrinted && value != ReceiptCopy.original;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.copyTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: t.inkMuted,
          ),
        ),
        const SizedBox(height: BlTokens.space1),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space1,
          children: [
            for (final copy in ReceiptCopy.values)
              if (copy != ReceiptCopy.transporter || offerTransporter)
                ChoiceChip(
                  label: Text(label(s, copy)),
                  selected: value == copy,
                  onSelected: copy == ReceiptCopy.original && gone
                      ? null
                      : (on) => onChanged(on ? copy : null),
                ),
          ],
        ),
        // Why the original is greyed out comes first: a chip that will not
        // select, with nothing said, reads as a broken button.
        Text(
          value == ReceiptCopy.transporter
              ? s.copyTransporterHint
              : gone
              ? s.copyOriginalGone
              : value == null
              ? s.copyAutoHint
              : s.copyChosenHint,
          style: TextStyle(fontSize: 12, color: t.inkFaint),
        ),
      ],
    );
  }
}

/// How the goods travel, in one line, and a tap to write it (M51).
///
/// Saved at once to the bill's own transport fields, which the schema keeps
/// editable on a posted bill because the bilty arrives after the bill is
/// printed. Nothing about the money on the bill can change from here.
class TransportLine extends ConsumerWidget {
  const TransportLine({
    super.key,
    required this.documentId,
    required this.transport,
  });

  final String documentId;
  final ReceiptTransport transport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayEdit = ref.watch(appServicesProvider).can(Permission.sell);
    final summary = [
      transport.transporter,
      if (transport.vehicleNo != null)
        '${s.transportVehicle} ${transport.vehicleNo}',
      if (transport.biltyNo != null) '${s.transportBilty} ${transport.biltyNo}',
      transport.shipTo,
    ].whereType<String>().join(' · ');
    return BlCard(
      onTap: mayEdit
          ? () => showTransportSheet(
              context,
              documentId: documentId,
              current: transport,
            )
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: BlTokens.space3,
        vertical: BlTokens.space2,
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined, size: 20, color: t.inkMuted),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Text(
              summary.isEmpty ? s.transportAdd : summary,
              style: TextStyle(
                fontSize: 14,
                color: summary.isEmpty ? t.inkMuted : t.ink,
              ),
            ),
          ),
          if (mayEdit) Icon(Icons.edit_outlined, size: 18, color: t.inkFaint),
        ],
      ),
    );
  }
}

/// The four transport fields of one bill, to write or put right.
Future<void> showTransportSheet(
  BuildContext context, {
  required String documentId,
  required ReceiptTransport current,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _TransportSheet(documentId: documentId, current: current),
);

class _TransportSheet extends ConsumerStatefulWidget {
  const _TransportSheet({required this.documentId, required this.current});

  final String documentId;
  final ReceiptTransport current;

  @override
  ConsumerState<_TransportSheet> createState() => _TransportSheetState();
}

class _TransportSheetState extends ConsumerState<_TransportSheet> {
  late final _transporter = TextEditingController(
    text: widget.current.transporter ?? '',
  );
  late final _vehicle = TextEditingController(
    text: widget.current.vehicleNo ?? '',
  );
  late final _bilty = TextEditingController(text: widget.current.biltyNo ?? '');
  late final _shipTo = TextEditingController(text: widget.current.shipTo ?? '');
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _transporter.dispose();
    _vehicle.dispose();
    _bilty.dispose();
    _shipTo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // First statement: two taps in one frame both reach here.
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final s = AppStrings.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .setTransportDetails(
            widget.documentId,
            ReceiptTransport(
              transporter: _transporter.text,
              vehicleNo: _vehicle.text,
              biltyNo: _bilty.text,
              shipTo: _shipTo.text,
            ),
          );
      container.bumpRefresh();
      if (mounted) navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '${s.commonSomethingWentWrong}: $error';
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
            Text(
              s.transportTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              s.transportHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _transporter,
              label: s.transportTransporter,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _vehicle,
              label: s.transportVehicle,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _bilty,
              label: s.transportBilty,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _shipTo,
              label: s.transportShipTo,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 13)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.actionSave,
              icon: Icons.check,
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
