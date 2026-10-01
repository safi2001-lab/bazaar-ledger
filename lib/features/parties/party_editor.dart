import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../subscription/plans_screen.dart';

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
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _cnic = TextEditingController();
  late final TextEditingController _discount = TextEditingController(
    text: _percent(widget.party?.defaultDiscountBp ?? 0),
  );
  late PriceTier _tier = widget.party?.priceTier ?? PriceTier.retail;

  /// A buyer's tax standing, which decides further tax on a registered
  /// shop's bill to them.
  bool _buyerRegistered = false;
  bool _buyerOnAtl = false;

  /// The party as saved, for an edit. Everything this form does not show —
  /// their type, NTN, WhatsApp number — is written back from here. The
  /// editor used to send only what it showed, and the writer stores the
  /// whole row, so correcting a supplier's phone number turned them into a
  /// customer and wiped their NTN.
  PartyDraft? _saved;
  bool _loading = false;

  bool _busy = false;
  String? _failure;

  bool get _isEdit => widget.party != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    final saved = firm == null
        ? null
        : await services.queries.partyDraft(firm.id, widget.party!.id);
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loading = false;
      _address.text = saved?.addressLine1 ?? '';
      _city.text = saved?.city ?? '';
      _cnic.text = saved?.cnic ?? '';
      _buyerRegistered = saved?.buyerRegistrationType == 'registered';
      _buyerOnAtl = saved?.isOnAtl ?? false;
    });
  }

  static String _percent(int bp) =>
      bp == 0 ? '' : Money.paisa(bp).amountOnly.replaceAll('.00', '');

  /// A percentage as basis points: "2.5" is 250. Parsed the way money is,
  /// because a percentage to two places is exactly that shape, and never
  /// through a double.
  static int? _bp(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return 0;
    final parsed = Money.tryParse(raw);
    if (parsed == null || parsed.isNegative || parsed.inPaisa > 10000) {
      return null;
    }
    return parsed.inPaisa;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _opening.dispose();
    _creditLimit.dispose();
    _address.dispose();
    _city.dispose();
    _cnic.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // The very first thing, before the validate and before any await.
    // `onPressed: _busy ? null : _save` only takes effect once a frame has
    // been built, so two taps inside one frame both reach here — and this
    // writes a row. The tender sheet documents and guards the same hazard;
    // that guard was never copied to the editors.
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final services = ref.read(appServicesProvider);
      final saved = _saved;
      String? text(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      final draft = PartyDraft(
        name: _name.text.trim(),
        partyType: saved?.partyType ?? widget.party?.partyType ?? 'customer',
        phone: text(_phone),
        whatsapp: saved?.whatsapp,
        addressLine1: text(_address),
        city: text(_city),
        ntn: saved?.ntn,
        strn: saved?.strn,
        cnic: text(_cnic),
        buyerRegistrationType: _buyerRegistered ? 'registered' : 'unregistered',
        isOnAtl: _buyerOnAtl,
        // An opening balance is what they already owed before the shop
        // started using this app. Set once, at creation; afterwards the
        // balance is whatever the documents say it is, and no form may
        // overwrite it.
        openingBalance: _isEdit
            ? Money.zero
            : Money.tryParse(_opening.text) ?? Money.zero,
        creditLimit: Money.tryParse(_creditLimit.text),
        creditDays: saved?.creditDays,
        priceTier: _tier,
        defaultDiscountBp: _bp(_discount.text) ?? 0,
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

  /// Hides this customer or supplier from the khata.
  ///
  /// There was a writer for this and no button, so a customer who moved away
  /// sat in the list for ever. The writer refuses while money is owed either
  /// way; that refusal is shown here as it is, in words.
  Future<void> _archive() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.partyArchive),
        content: Text(s.partyArchiveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.commonYes),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final services = ref.read(appServicesProvider);
      await services.catalogue.archiveParty(
        services.actorNow(),
        widget.party!.id,
      );
      if (!mounted) return;
      ref.bumpRefresh();
      // `true` tells the khata underneath that the party it shows is gone.
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(s.partyArchived)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error is StateError ? error.message : '$error';
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
      appBar: AppBar(
        title: Text(_isEdit ? s.actionEdit : s.partiesAdd),
        actions: [
          if (_isEdit)
            BlIconButton(
              icon: Icons.archive_outlined,
              label: s.partyArchive,
              colour: t.danger,
              onPressed: _busy ? null : () => unawaited(_archive()),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              )
            : SingleChildScrollView(
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
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? s.commonRequired
                                : null,
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
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: BlTokens.space4),
                          // Which of an item's two prices they are sold at. A
                          // wholesaler's regular retailers pay the trade price and
                          // the counter used to charge them the shelf price.
                          Text(
                            s.partyPriceTier,
                            style: TextStyle(fontSize: 13, color: t.inkMuted),
                          ),
                          const SizedBox(height: BlTokens.space2),
                          Wrap(
                            spacing: BlTokens.space2,
                            children: [
                              for (final (tier, label) in [
                                (PriceTier.retail, s.partyTierRetail),
                                (PriceTier.wholesale, s.partyTierWholesale),
                                (PriceTier.vip, s.partyTierVip),
                              ])
                                ChoiceChip(
                                  selected: _tier == tier,
                                  label: Text(label),
                                  avatar: tier == PriceTier.retail
                                      ? null
                                      : const PlanLock(PlanFeature.priceLists),
                                  onSelected: (_) async {
                                    // Wholesale and VIP lists are Silver
                                    // (M21); a party already on one keeps it.
                                    if (tier != PriceTier.retail &&
                                        tier != widget.party?.priceTier &&
                                        !await ensurePlan(
                                          context,
                                          ref,
                                          PlanFeature.priceLists,
                                        )) {
                                      return;
                                    }
                                    setState(() => _tier = tier);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: BlTokens.space4),
                          BlField(
                            controller: _discount,
                            label: s.partyDiscount,
                            numeric: true,
                            textInputAction: TextInputAction.next,
                            validator: (v) => _bp(v ?? '') == null
                                ? s.partyDiscountInvalid
                                : null,
                          ),
                          const SizedBox(height: BlTokens.space4),
                          // What a legal notice, a delivery challan and a proper
                          // invoice need, and what the khata had nowhere to keep.
                          BlField(
                            controller: _address,
                            label: s.partyAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: BlTokens.space4),
                          BlField(
                            controller: _city,
                            label: s.partyCity,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: BlTokens.space4),
                          BlField(
                            controller: _cnic,
                            label: s.partyCnic,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_busy) unawaited(_save());
                            },
                          ),
                          const SizedBox(height: BlTokens.space2),
                          // Further tax is charged to a business that is not
                          // registered or not on the Active Taxpayers List.
                          SwitchListTile.adaptive(
                            value: _buyerRegistered,
                            onChanged: (v) =>
                                setState(() => _buyerRegistered = v),
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.partyTaxRegistered),
                          ),
                          SwitchListTile.adaptive(
                            value: _buyerOnAtl,
                            onChanged: (v) => setState(() => _buyerOnAtl = v),
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.partyOnAtl),
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
