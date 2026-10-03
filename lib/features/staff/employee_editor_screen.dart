import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../loans/loan_fields.dart' show LoanDateField, typedMoney;
import 'staff_providers.dart';

/// The shop's sign-ins, to link a man to his own (M9).
final _signInsProvider = FutureProvider.autoDispose<List<StaffMember>>((
  ref,
) async {
  final book = ref.watch(appServicesProvider).staffBook;
  if (!book.mayKeep) return const [];
  return book.signIns();
});

/// Adding a man to the payroll, or changing his details (M65).
///
/// His name, what he does and what he is paid are asked for; his phone is
/// for sending him his slip on WhatsApp, and his CNIC is there for a shop
/// that keeps one but never asked for — DigiKhata's CNIC prompts are among
/// what its users complain of. He may be linked to his own sign-in, and
/// needn't be: the boy who carries the sacks never touches the phone.
class EmployeeEditorScreen extends ConsumerStatefulWidget {
  const EmployeeEditorScreen({super.key, this.existing});

  /// The man being changed, or null for a new one.
  final Employee? existing;

  @override
  ConsumerState<EmployeeEditorScreen> createState() =>
      _EmployeeEditorScreenState();
}

class _EmployeeEditorScreenState extends ConsumerState<EmployeeEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _cnic;
  late final TextEditingController _rate;
  late final TextEditingController _note;
  late EmployeeKaam _kaam;
  late PayBasis _basis;
  BusinessDate? _joined;
  BusinessDate? _left;
  String? _userId;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _cnic = TextEditingController(
      text: e?.cnic == null ? '' : cnicDisplay(e!.cnic!),
    );
    _rate = TextEditingController(
      text: e == null ? '' : e.rate.amountOnly.replaceAll(',', ''),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _kaam = e?.kaam ?? EmployeeKaam.helper;
    _basis = e?.basis ?? PayBasis.monthly;
    _joined = e?.joinedOn;
    _left = e?.leftOn;
    _userId = e?.userId;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _cnic, _rate, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(BusinessDate joined) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final rate = typedMoney(_rate.text);
    if (rate == null) {
      setState(() => _failure = s.staffRateInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = EmployeeDraft(
      name: _name.text,
      kaam: _kaam,
      basis: _basis,
      rate: rate,
      joinedOn: joined,
      leftOn: _left,
      phone: _phone.text,
      cnic: _cnic.text,
      userId: _userId,
      note: _note.text,
    );
    try {
      final book = ref.read(appServicesProvider).staffBook;
      final existing = widget.existing;
      if (existing == null) {
        await book.add(draft);
      } else {
        await book.edit(existing.id, draft);
      }
      ref.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.staffSaved)));
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = staffError(s, error);
      });
    }
  }

  Future<void> _hide(Employee man) async {
    final s = AppStrings.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appServicesProvider).staffBook.hide(man.id);
      ref.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.staffHidden(man.name))));
      navigator
        ..pop()
        ..pop();
    } on Object catch (error) {
      if (mounted) setState(() => _failure = staffError(s, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final joined = _joined ?? today;
    final signIns = ref.watch(_signInsProvider).valueOrNull ?? const [];
    final existing = widget.existing;

    void changed(String _) => setState(() => _failure = null);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(existing == null ? s.staffAdd : s.staffEdit)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space5,
                ),
                children: [
                  BlField(
                    controller: _name,
                    label: s.staffName,
                    autofocus: existing == null,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  Text(
                    s.staffKaam,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      for (final k in EmployeeKaam.values)
                        ChoiceChip(
                          selected: _kaam == k,
                          label: Text(kaamName(s, k)),
                          onSelected: (_) => setState(() => _kaam = k),
                        ),
                    ],
                  ),
                  const SizedBox(height: BlTokens.space4),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      ChoiceChip(
                        selected: _basis == PayBasis.monthly,
                        label: Text(s.staffBasisMonthly),
                        onSelected: (_) =>
                            setState(() => _basis = PayBasis.monthly),
                      ),
                      ChoiceChip(
                        selected: _basis == PayBasis.daily,
                        label: Text(s.staffBasisDaily),
                        onSelected: (_) =>
                            setState(() => _basis = PayBasis.daily),
                      ),
                    ],
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _rate,
                    label: _basis == PayBasis.monthly
                        ? s.staffSalary
                        : s.staffDayWage,
                    numeric: true,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  Text(
                    s.staffJoinedLabel,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  LoanDateField(
                    date: joined,
                    today: today,
                    onChanged: (d) => setState(() => _joined = d),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _phone,
                    label: s.staffPhone,
                    keyboardType: TextInputType.phone,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _cnic,
                    label: s.staffCnic,
                    keyboardType: TextInputType.number,
                    onChanged: changed,
                  ),
                  if (signIns.isNotEmpty) ...[
                    const SizedBox(height: BlTokens.space3),
                    DropdownButtonFormField<String?>(
                      initialValue: _userId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.staffSignIn),
                      items: [
                        DropdownMenuItem<String?>(
                          child: Text(s.staffSignInNone),
                        ),
                        for (final m in signIns)
                          DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(m.name),
                          ),
                      ],
                      onChanged: (id) => setState(() => _userId = id),
                    ),
                  ],
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _note,
                    label: s.staffNote,
                    maxLines: 2,
                    onChanged: changed,
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: BlTokens.space3),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _left != null,
                      title: Text(s.staffHasLeft),
                      subtitle: _left == null
                          ? null
                          : Text(s.staffLeftOn(_left!.value)),
                      onChanged: (on) =>
                          setState(() => _left = on ? today : null),
                    ),
                    if (_left != null)
                      LoanDateField(
                        date: _left!,
                        today: today,
                        onChanged: (d) => setState(() => _left = d),
                      ),
                    const SizedBox(height: BlTokens.space4),
                    BlButton(
                      label: s.staffHide,
                      icon: Icons.delete_outline,
                      kind: BlButtonKind.danger,
                      onPressed: () => unawaited(_hide(existing)),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: t.surface,
              padding: EdgeInsets.only(
                left: BlTokens.space4,
                right: BlTokens.space4,
                top: BlTokens.space3,
                bottom:
                    BlTokens.space3 +
                    (MediaQuery.viewInsetsOf(context).bottom > 0
                        ? 0
                        : MediaQuery.viewPaddingOf(context).bottom),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null) ...[
                    Text(
                      _failure!,
                      style: TextStyle(color: t.danger, fontSize: 14),
                    ),
                    const SizedBox(height: BlTokens.space2),
                  ],
                  BlButton(
                    label: s.staffSave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy ? null : () => unawaited(_save(joined)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
