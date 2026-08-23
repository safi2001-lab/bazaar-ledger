import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Add a customer, or change one.
class PartyEditorScreen extends ConsumerStatefulWidget {
  const PartyEditorScreen({super.key, this.party, this.initialName});

  final PartySummary? party;
  final String? initialName;

  @override
  ConsumerState<PartyEditorScreen> createState() => _PartyEditorScreenState();
}

class _PartyEditorScreenState extends ConsumerState<PartyEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.party?.name ?? widget.initialName ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.party?.phone ?? '',
  );
  final _opening = TextEditingController();
  late final TextEditingController _creditLimit = TextEditingController(
    text: widget.party?.creditLimit?.amountOnly ?? '',
  );

  bool _busy = false;
  String? _failure;

  bool get _isEdit => widget.party != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _opening.dispose();
    _creditLimit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final services = ref.read(appServicesProvider);
      final draft = PartyDraft(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        // An opening balance is what they already owed before the shop
        // started using this app. Set once, at creation; afterwards the
        // balance is whatever the documents say it is, and no form may
        // overwrite it.
        openingBalance: _isEdit
            ? Money.zero
            : Money.tryParse(_opening.text) ?? Money.zero,
        creditLimit: Money.tryParse(_creditLimit.text),
      );

      final actor = services.actorNow();
      if (_isEdit) {
        await services.catalogue.updateParty(actor, widget.party!.id, draft);
      } else {
        await services.catalogue.addParty(actor, draft);
      }

      if (!mounted) return;
      ref.bumpRefresh();
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(_isEdit ? s.actionEdit : s.partiesAdd)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BlTokens.space4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                // Re-validated as the shopkeeper types, once they have
                // touched the form. Without this a field validated on Save
                // keeps its red border and its error message after the text
                // is corrected — the message only refreshes on the next
                // `validate()` call. Found by hand on the handset: "Aap ka
                // naam" read "Yeh khana zaroori hai" in red while holding
                // "Malik Sahib". For an audience where 60% national and 52%
                // rural literacy is the design constraint, an error that
                // will not go away is a dead end.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BlField(
                      controller: _name,
                      label: s.partyName,
                      autofocus: !_isEdit,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? s.commonRequired : null,
                    ),
                    const SizedBox(height: BlTokens.space4),
                    BlField(
                      controller: _phone,
                      label: s.partyPhone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: BlTokens.space4),
                    if (!_isEdit) ...[
                      BlField(
                        controller: _opening,
                        label: s.partyOpeningBalance,
                        numeric: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: BlTokens.space4),
                    ],
                    BlField(
                      controller: _creditLimit,
                      label: s.partyCreditLimit,
                      numeric: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_busy) _save();
                      },
                    ),
                    if (_failure != null) ...[
                      const SizedBox(height: BlTokens.space4),
                      Text(
                        _failure!,
                        style: TextStyle(fontSize: 13, color: t.danger),
                      ),
                    ],
                    const SizedBox(height: BlTokens.space6),
                    BlButton(
                      label: s.actionSave,
                      icon: Icons.check,
                      big: true,
                      busy: _busy,
                      onPressed: _busy ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
