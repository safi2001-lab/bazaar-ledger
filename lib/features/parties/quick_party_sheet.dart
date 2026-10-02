import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../subscription/plans_screen.dart';

/// A new customer, or a new supplier, without leaving the bill (M32).
///
/// "In Vyapar, when we make a bill and the person is new, it gets added
/// automatically." Until this, a cashier with a new customer at the counter
/// had to abandon the payment sheet, go to Customers, add them, and come back
/// to a bill they then had to find again — so most did not, and the sale went
/// down as a walk-in with the udhaar written on a slip of paper. This is the
/// short form: the name already typed, a mobile, and, for a customer, which
/// price they pay and how much credit they get. Everything else waits for the
/// full form in Customers.
///
/// It writes through the same `catalogue.addParty` the full form uses, so the
/// writer's own checks and the plan gate on price lists apply exactly as they
/// do there. What it adds is the warning the full form never had: somebody
/// already in the khata under the same name or the same mobile is shown
/// before a second khata is opened for them. Two khatas for one person is
/// two balances, and the one a shopkeeper chases is never the one that is
/// owed.
Future<PartySummary?> showQuickPartySheet(
  BuildContext context, {
  required String name,
  required String partyType,
}) => showModalBottomSheet<PartySummary>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => QuickPartySheet(initialName: name, partyType: partyType),
);

/// A Pakistani mobile number as the khata keeps it from here: `0300 4471203`.
///
/// Read through [whatsappNumber], the one place the app already decides what
/// a Pakistani mobile is, so a number this form accepts is always one a
/// reminder can be sent to. Null when [raw] cannot be one — a landline, a
/// number a digit short — and the form then refuses it rather than keeping a
/// number nobody can be reached on. A landline still goes in from the full
/// customer form, which takes a phone exactly as typed.
String? khataMobile(String raw) {
  final number = whatsappNumber(raw);
  if (number == null) return null;
  final national = number.substring(2);
  return '0${national.substring(0, 3)} ${national.substring(3)}';
}

/// Who in the khata this new name might already be.
///
/// The same name once capitals, spaces and punctuation are set aside — the
/// normalisation every party's search key is stored under — or the same
/// mobile however it was written: `0300-4471203`, `+92 300 4471203` and
/// `03004471203` are one phone in one pocket. Read with the khata's own
/// search, so nothing here is a second idea of who a party is.
///
/// Hidden parties are not looked at. A customer the shop hid has their own
/// way back, from Settings, with their history; offering them here would
/// put a bill on a khata the owner closed.
Future<List<PartySummary>> partyTwins(
  AppQueries queries,
  String firmId, {
  required String name,
  String? phone,
}) async {
  final found = <String, PartySummary>{};
  final key = PartyDraft(name: name).searchKey;
  if (key.isNotEmpty) {
    for (final p in await queries.searchParties(
      firmId,
      query: name,
      limit: 20,
    )) {
      if (PartyDraft(name: p.name).searchKey == key) found[p.id] = p;
    }
  }
  final mobile = whatsappNumber(phone);
  if (mobile != null) {
    // The search matches a phone by substring, and the last seven digits are
    // the part every way of writing a Pakistani mobile keeps together.
    final tail = mobile.substring(mobile.length - 7);
    for (final p in await queries.searchParties(
      firmId,
      query: tail,
      limit: 20,
    )) {
      if (whatsappNumber(p.phone) == mobile) found[p.id] = p;
    }
  }
  return found.values.toList();
}

/// The words for a refusal, rather than an exception's class name.
String refusalWords(Object error) => switch (error) {
  PlanRequired(:final reason) => reason,
  PermissionDenied(:final reason) => reason,
  StateError(:final message) => message,
  _ => '$error',
};

class QuickPartySheet extends ConsumerStatefulWidget {
  const QuickPartySheet({
    super.key,
    required this.initialName,
    this.partyType = 'customer',
  });

  /// What was typed in the picker, so it is never typed twice.
  final String initialName;

  /// `customer` from the counter, `supplier` from a delivery.
  final String partyType;

  @override
  ConsumerState<QuickPartySheet> createState() => _QuickPartySheetState();
}

class _QuickPartySheetState extends ConsumerState<QuickPartySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName.trim(),
  );
  final _phone = TextEditingController();
  final _limit = TextEditingController();
  PriceTier _tier = PriceTier.retail;

  bool _busy = false;
  String? _failure;

  /// Who this might already be, once Save has looked. Empty until then, and
  /// emptied again the moment the name or the number is changed.
  List<PartySummary> _twins = const [];

  bool get _forCustomer => widget.partyType == 'customer';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _edited() {
    if (_twins.isEmpty && _failure == null) return;
    setState(() {
      _twins = const [];
      _failure = null;
    });
  }

  /// Saves the party and hands it back to the picker, which puts it on the
  /// bill. [anyway] is the shopkeeper saying that the namesake shown is
  /// somebody else: two Muhammad Alis in one mohalla is ordinary.
  Future<void> _save({bool anyway = false}) async {
    // Before the validate and before any await, as every editor here does:
    // two taps inside one frame both reach this line, and it writes a row.
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final firm = await ref.read(firmProvider.future);
      if (firm == null) throw StateError('This phone has no shop yet.');
      final phone = _phone.text.trim().isEmpty
          ? null
          : khataMobile(_phone.text);
      final draft = PartyDraft(
        name: _name.text.trim(),
        partyType: widget.partyType,
        phone: phone,
        creditLimit: _forCustomer && _limit.text.trim().isNotEmpty
            ? Money.tryParse(_limit.text)
            : null,
        priceTier: _forCustomer ? _tier : PriceTier.retail,
      );

      if (!anyway) {
        final twins = await partyTwins(
          services.queries,
          firm.id,
          name: draft.name,
          phone: phone,
        );
        if (twins.isNotEmpty) {
          if (mounted) {
            setState(() {
              _twins = twins;
              _busy = false;
            });
          }
          return;
        }
      }

      final id = await services.catalogue.addParty(services.actorNow(), draft);
      final party = await services.queries.partyById(firm.id, id);
      // Through the container, not `ref`: the sheet may already be on its
      // way out, and the khata lists must still learn there is a new name.
      container.bumpRefresh();
      navigator.pop(party);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = refusalWords(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);

    // Which price a new customer pays is offered to whoever may see what the
    // goods cost (M9's `seeCosts`: the owner, a manager, the munshi). A trade
    // or VIP price is a standing discount by another name, set against what
    // the goods cost the shop; a counter boy who cannot see the cost is not
    // the one to put a stranger on it, and M22 already keeps his own
    // discounts to his ceiling. His new customers start on retail, and the
    // owner can move them from the full form.
    final mayPriceList = _forCustomer && services.can(Permission.seeCosts);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _forCustomer ? s.partiesAdd : s.quickSupplierTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                BlIconButton(
                  icon: Icons.close,
                  label: s.actionClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _name,
              label: s.partyName,
              autofocus: _name.text.isEmpty,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _edited(),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? s.commonRequired : null,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _phone,
              label: s.quickPartyMobile,
              hint: s.quickPartyMobileHint,
              keyboardType: TextInputType.phone,
              // The name came from the picker, so the number is the next
              // thing to type.
              autofocus: _name.text.isNotEmpty,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _edited(),
              validator: (v) =>
                  (v ?? '').trim().isEmpty || khataMobile(v!) != null
                  ? null
                  : s.quickPartyMobileInvalid,
            ),
            if (_forCustomer) ...[
              const SizedBox(height: BlTokens.space3),
              // A limit only ever stops credit. Left blank, the customer has
              // none set — which is how every khata began before M3 had one.
              BlField(
                controller: _limit,
                label: s.quickPartyCreditLimit,
                numeric: true,
                textInputAction: TextInputAction.done,
              ),
            ],
            if (mayPriceList) ...[
              const SizedBox(height: BlTokens.space4),
              Text(
                s.partyPriceTier,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
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
                        // Wholesale and VIP lists are Silver (M21), here as
                        // in the full form; the writer refuses them too.
                        if (tier != PriceTier.retail &&
                            !await ensurePlan(
                              context,
                              ref,
                              PlanFeature.priceLists,
                            )) {
                          return;
                        }
                        if (mounted) setState(() => _tier = tier);
                      },
                    ),
                ],
              ),
            ],
            if (_twins.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space4),
              _Twins(
                twins: _twins,
                busy: _busy,
                onUse: (party) => Navigator.of(context).pop(party),
                onAddAnyway: () => unawaited(_save(anyway: true)),
              ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                _failure!,
                style: TextStyle(fontSize: 13, color: t.danger),
              ),
            ],
            const SizedBox(height: BlTokens.space5),
            BlButton(
              label: s.actionSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The people this might already be, each a tap from being used instead.
///
/// Not a dialog. The shopkeeper is looking at the form, and the names belong
/// where the Save button they just pressed is.
class _Twins extends StatelessWidget {
  const _Twins({
    required this.twins,
    required this.busy,
    required this.onUse,
    required this.onAddAnyway,
  });

  final List<PartySummary> twins;
  final bool busy;
  final ValueChanged<PartySummary> onUse;
  final VoidCallback onAddAnyway;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Container(
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.quickPartyTwins,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.warning,
            ),
          ),
          const SizedBox(height: BlTokens.space1),
          Text(
            s.quickPartyTwinsHint,
            style: TextStyle(fontSize: 13, color: t.warning),
          ),
          const SizedBox(height: BlTokens.space2),
          for (final party in twins)
            _TwinRow(
              title: party.phone == null
                  ? party.name
                  : '${party.name} · ${party.phone}',
              onTap: () => onUse(party),
            ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.quickAddAnyway,
            kind: BlButtonKind.secondary,
            onPressed: busy ? null : onAddAnyway,
          ),
        ],
      ),
    );
  }
}

/// One namesake: a name, and the way to use it.
class _TwinRow extends StatelessWidget {
  const _TwinRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BlTokens.radiusSm),
      child: Container(
        constraints: const BoxConstraints(minHeight: BlTokens.touchMin),
        padding: const EdgeInsets.symmetric(vertical: BlTokens.space2),
        child: Row(
          children: [
            Icon(Icons.person_outline, size: 20, color: t.ink),
            const SizedBox(width: BlTokens.space2),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}
