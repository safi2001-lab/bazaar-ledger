import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What the pharmacy rules asked of a bill before it was saved (M49): the
/// prescription its Schedule medicines are registered against, and the
/// photograph of the paper, when one was taken.
typedef CounterRx = ({
  Prescription? prescription,
  Uint8List? photo,
  String? photoName,
});

const CounterRx _nothingAsked = (
  prescription: null,
  photo: null,
  photoName: null,
);

/// Asks the pharmacy rules about [preview] just before the bill is saved.
///
///  * A medicine above its printed price, batch by batch: refused in a
///    pharmacy, in words. Any other shop is warned on the line itself, for
///    its Third Schedule goods (M59's note), and is not asked again here.
///  * A medicine the shelf cannot give — first-expiry-first-out would have
///    to reach a batch on hold or out of date — is said, in the words the
///    hold was given, and the bill waits.
///  * A Schedule medicine asks who it is for and who prescribed it.
///
/// Null when the bill must not go; otherwise what was asked. The sale path
/// refuses the first and the last again on its own, so no screen that
/// forgets to ask can sell above the MRP or without a prescription.
///
/// [onAsk] is called just before anything is put in front of the cashier,
/// so the screen can stop showing its Save as working: the question is
/// modal, and a spinner behind it while somebody types a doctor's name
/// reads as the bill being stuck.
Future<CounterRx?> pharmacyAllowsBill(
  BuildContext context,
  WidgetRef ref,
  CalculatedSale preview, {
  VoidCallback? onAsk,
}) async {
  final services = ref.read(appServicesProvider);
  final charged = <String, ({String name, Qty qty, Money charged})>{};
  for (final line in preview.lines) {
    final id = line.draft.itemId;
    if (id == null) continue;
    final was = charged[id];
    charged[id] = (
      name: line.draft.itemName,
      qty: (was?.qty ?? Qty.zero) + line.draft.baseQty,
      charged: (was?.charged ?? Money.zero) + line.lineTotal,
    );
  }
  if (charged.isEmpty) return _nothingAsked;
  final rules = await services.pharmacy.rules();
  final medicines = await services.pharmacy.atCounter({
    for (final e in charged.entries) e.key: e.value.qty,
  });
  if (!context.mounted) return null;

  final refused = [for (final m in medicines.values) ?m.refused];
  if (refused.isNotEmpty) {
    onAsk?.call();
    await _tell(context, AppStrings.of(context).pharmacyCannotSellTitle, [
      ...refused,
    ]);
    return null;
  }

  // The one above-MRP check (pricing/mrp.dart). A pharmacy is refused; a
  // shop of any other kind has already seen M59's red note under a Third
  // Schedule line, and is not stopped a second time.
  final breaches = rules.mrpRule == MrpRule.block
      ? mrpBreaches(charged, medicines)
      : const <MrpBreach>[];
  if (breaches.isNotEmpty) {
    onAsk?.call();
    final s = AppStrings.of(context);
    await _tell(context, s.pharmacyMrpBlockedTitle, [
      for (final b in breaches)
        s.pharmacyMrpBlocked(
          b.itemName,
          b.charged.amountOnly,
          b.ceiling.amountOnly,
        ),
    ]);
    return null;
  }

  final scheduled = [
    for (final m in medicines.values)
      if (m.schedule != null) m.itemName,
  ];
  if (scheduled.isEmpty) return _nothingAsked;
  if (!context.mounted) return null;
  onAsk?.call();
  return showModalBottomSheet<CounterRx>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PrescriptionSheet(medicines: scheduled),
  );
}

/// Keeps the photograph [rx] carries with the bill [documentId], once it is
/// saved. Never in the way of the sale: the bill and its register rows are
/// already written, the picture is evidence beside them, and a picture that
/// would not shrink is the only thing lost.
Future<void> keepPrescriptionPhoto(
  AppServices services,
  String documentId,
  CounterRx? rx,
) async {
  final photo = rx?.photo;
  if (photo == null) return;
  try {
    await services.pharmacy.attachPrescriptionPhoto(
      documentId,
      source: photo,
      fileName: rx?.photoName ?? 'prescription.jpg',
    );
  } on Object {
    // See above: nothing on the books depends on it.
  }
}

Future<void> _tell(BuildContext context, String title, List<String> lines) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.block, color: context.bl.danger),
        title: Text(title),
        content: _Lines(lines),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.of(context).actionOk),
          ),
        ],
      ),
    );

class _Lines extends StatelessWidget {
  const _Lines(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) ...[
          Text(line, style: TextStyle(fontSize: 15, color: context.bl.ink)),
          const SizedBox(height: BlTokens.space2),
        ],
      ],
    ),
  );
}

/// Who a Schedule medicine is for and who prescribed it, asked before the
/// bill is saved: the two people the register needs that the bill does not
/// already know.
class _PrescriptionSheet extends StatefulWidget {
  const _PrescriptionSheet({required this.medicines});

  final List<String> medicines;

  @override
  State<_PrescriptionSheet> createState() => _PrescriptionSheetState();
}

class _PrescriptionSheetState extends State<_PrescriptionSheet> {
  final _form = GlobalKey<FormState>();
  final _patient = TextEditingController();
  final _address = TextEditingController();
  final _doctor = TextEditingController();
  final _regNo = TextEditingController();
  final _reference = TextEditingController();
  Uint8List? _photo;
  String? _photoName;

  @override
  void dispose() {
    _patient.dispose();
    _address.dispose();
    _doctor.dispose();
    _regNo.dispose();
    _reference.dispose();
    super.dispose();
  }

  /// From the gallery, as an item's picture is: the system photo picker,
  /// which needs no permission.
  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      _photoName = picked.name;
    });
  }

  void _done() {
    if (!(_form.currentState?.validate() ?? false)) return;
    String? blank(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.of(context).pop<CounterRx>((
      prescription: Prescription(
        patientName: _patient.text.trim(),
        patientAddress: blank(_address),
        prescriberName: _doctor.text.trim(),
        prescriberRegNo: _regNo.text.trim(),
        reference: blank(_reference),
      ),
      photo: _photo,
      photoName: _photoName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? s.commonRequired : null;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlSectionHeader(s.pharmacyRxTitle),
            const SizedBox(height: BlTokens.space1),
            Text(
              s.pharmacyRxFor(widget.medicines.join(', ')),
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _patient,
              label: s.pharmacyRxPatient,
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: required,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _address,
              label: s.pharmacyRxPatientAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _doctor,
              label: s.pharmacyRxDoctor,
              textInputAction: TextInputAction.next,
              validator: required,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _regNo,
              label: s.pharmacyRxRegNo,
              textInputAction: TextInputAction.next,
              validator: required,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _reference,
              label: s.pharmacyRxRef,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: _photo == null
                  ? s.pharmacyRxPhoto
                  : s.pharmacyRxPhotoTaken,
              icon: _photo == null
                  ? Icons.add_a_photo_outlined
                  : Icons.check_circle_outline,
              kind: BlButtonKind.secondary,
              onPressed: () => unawaited(_pickPhoto()),
            ),
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.pharmacyRxSave,
              icon: Icons.check,
              big: true,
              onPressed: _done,
            ),
          ],
        ),
      ),
    );
  }
}
