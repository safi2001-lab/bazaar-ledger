import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../attachments/attachment_strip.dart';
import 'imei_words.dart';
import 'phone_story_screen.dart';
import 'pta.dart';

/// The phone models a used phone can be bought in as: items kept by serial
/// number, the shop's phones.
final _phoneModelsProvider = FutureProvider.autoDispose<List<ItemSummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  final items = await ref
      .watch(appServicesProvider)
      .queries
      .searchItems(firm.id, limit: 500);
  return [
    for (final i in items)
      if (i.tracksSerial) i,
  ];
});

/// Buying a used phone over the counter (M50).
///
/// A man walks in with a phone to sell. The shop writes down who he is —
/// name, CNIC, a number to reach him — what the phone is by its IMEIs and
/// what PTA says of it, what state it is in, and what was paid; photographs
/// his CNIC and the phone; and puts it on the shelf. One save is a delivery
/// like any other (the phone onto the shelf at what was paid, the cash out
/// of the drawer) and a row in the used phones register the police and the
/// market association ask for.
class UsedPhoneScreen extends ConsumerStatefulWidget {
  const UsedPhoneScreen({super.key});

  @override
  ConsumerState<UsedPhoneScreen> createState() => _UsedPhoneScreenState();
}

class _UsedPhoneScreenState extends ConsumerState<UsedPhoneScreen> {
  final _name = TextEditingController();
  final _cnic = TextEditingController();
  final _phone = TextEditingController();
  final _imei1 = TextEditingController();
  final _imei2 = TextEditingController();
  final _condition = TextEditingController();
  final _price = TextEditingController();

  String? _itemId;
  PtaStatus _pta = PtaStatus.unknown;
  String? _accountId;

  /// A seller who has sold the shop a phone before, found by CNIC.
  UsedPhoneSeller? _known;
  bool _busy = false;
  String? _failure;

  /// What the save wrote, once it has: the photographs go on it.
  ({String documentId, String docNo, String partyId, String lotId})? _done;

  @override
  void dispose() {
    for (final c in [
      _name,
      _cnic,
      _phone,
      _imei1,
      _imei2,
      _condition,
      _price,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cnicChanged(String text) async {
    setState(() => _failure = null);
    if (!cnicWellFormed(text)) {
      if (_known != null) setState(() => _known = null);
      return;
    }
    final seller = await ref
        .read(appServicesProvider)
        .mobile
        .sellerByCnic(text);
    if (!mounted || seller == null) return;
    setState(() {
      _known = seller;
      if (_name.text.trim().isEmpty) _name.text = seller.name;
      if (_phone.text.trim().isEmpty) _phone.text = seller.phone ?? '';
    });
  }

  Future<void> _save(List<ItemSummary> models) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final item = models.where((m) => m.id == _itemId).firstOrNull;
    final price = Money.tryParse(_price.text) ?? Money.zero;
    final problem = _name.text.trim().isEmpty
        ? s.mobileSellerNameNeeded
        : !cnicWellFormed(_cnic.text)
        ? s.mobileCnicBad
        : item == null
        ? s.mobileModelNeeded
        : imeiFieldProblem(s, _imei1.text) ??
              imeiFieldProblem(s, _imei2.text, optional: true) ??
              (!price.isPositive ? s.mobilePriceNeeded : null);
    if (problem != null) {
      setState(() => _failure = problem);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final firm = await ref.read(firmProvider.future);
      final accounts = await services.queries.paymentAccounts(firm!.id);
      final account =
          accounts.where((a) => a.id == _accountId).firstOrNull ??
          accounts.where((a) => a.modeLabel == 'cash').firstOrNull;
      if (account == null) {
        setState(() {
          _failure = s.tenderNoAccount;
          _busy = false;
        });
        return;
      }
      final done = await services.mobile.buyUsedPhone(
        UsedPhoneBuyDraft(
          sellerName: _name.text,
          sellerCnic: _cnic.text,
          sellerPhone: _phone.text,
          conditionNote: _condition.text,
          itemId: item!.id,
          itemName: item.name,
          unitId: item.unitId,
          unitCode: item.unitCode,
          phone: PhoneUnitDraft(
            imei1: _imei1.text,
            imei2: _imei2.text,
            pta: _pta,
          ),
          price: price,
          paymentAccountId: account.id,
        ),
      );
      container.bumpRefresh();
      if (!mounted) return;
      setState(() {
        _done = done;
        _busy = false;
      });
    } on ImeiRefused catch (refused) {
      if (!mounted) return;
      setState(() {
        _failure = imeiProblemWords(s, refused.problem);
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = '${s.mobileBuyFailed}\n\n$error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final done = _done;
    return Scaffold(
      appBar: AppBar(title: Text(s.mobileBuyUsedTitle)),
      body: done == null ? _form(context) : _photos(context, done),
    );
  }

  Widget _photos(
    BuildContext context,
    ({String documentId, String docNo, String partyId, String lotId}) done,
  ) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return ListView(
      padding: const EdgeInsets.all(BlTokens.space4),
      children: [
        BlCard(
          accent: true,
          child: Text(
            s.mobileBuyDone(done.docNo),
            style: TextStyle(fontSize: 15, color: t.ink),
          ),
        ),
        const SizedBox(height: BlTokens.space4),
        BlSectionHeader(s.mobileCnicPhoto),
        AttachmentStrip(owner: AttachmentOwner.party(done.partyId)),
        BlSectionHeader(s.mobilePhonePhoto),
        AttachmentStrip(owner: AttachmentOwner.document(done.documentId)),
        Text(
          s.mobilePhotosStayHere,
          style: TextStyle(fontSize: 12, color: t.inkMuted),
        ),
        const SizedBox(height: BlTokens.space5),
        BlButton(
          label: s.mobileOpenStory,
          icon: Icons.history,
          kind: BlButtonKind.secondary,
          onPressed: () => unawaited(
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) =>
                    PhoneStoryScreen(lotId: done.lotId, title: _imei1.text),
              ),
            ),
          ),
        ),
        const SizedBox(height: BlTokens.space2),
        BlButton(
          label: s.actionDone,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final models = ref.watch(_phoneModelsProvider).valueOrNull;
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
    final known = _known;
    return ListView(
      padding: const EdgeInsets.all(BlTokens.space4),
      children: [
        BlSectionHeader(s.mobileSellerTitle),
        const SizedBox(height: BlTokens.space2),
        BlField(
          controller: _cnic,
          label: s.mobileSellerCnic,
          hint: '35202-1234567-1',
          keyboardType: TextInputType.number,
          onChanged: (v) => unawaited(_cnicChanged(v)),
        ),
        if (known != null)
          Padding(
            padding: const EdgeInsets.only(top: BlTokens.space1),
            child: Text(
              s.mobileSellerKnown(known.name),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          ),
        const SizedBox(height: BlTokens.space3),
        BlField(controller: _name, label: s.mobileSellerName),
        const SizedBox(height: BlTokens.space3),
        BlField(
          controller: _phone,
          label: s.mobileSellerPhone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: BlTokens.space2),
        Text(
          s.mobilePhotosStayHere,
          style: TextStyle(fontSize: 12, color: t.inkMuted),
        ),
        const SizedBox(height: BlTokens.space4),

        BlSectionHeader(s.mobilePhoneTitle),
        const SizedBox(height: BlTokens.space2),
        if (models != null && models.isEmpty)
          Text(
            s.mobileNoModels,
            style: TextStyle(fontSize: 13, color: t.warning),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _itemId,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.mobileModel),
            items: [
              for (final m in models ?? const <ItemSummary>[])
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: (v) => setState(() => _itemId = v),
          ),
        const SizedBox(height: BlTokens.space3),
        BlField(
          controller: _imei1,
          label: s.mobileImei1,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _failure = null),
        ),
        const SizedBox(height: BlTokens.space3),
        BlField(
          controller: _imei2,
          label: s.mobileImei2,
          hint: s.mobileImei2Hint,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _failure = null),
        ),
        const SizedBox(height: BlTokens.space3),
        // Wrapped, not a row: at a large text size the two buttons go under
        // the chip rather than off the edge of a small phone.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: BlTokens.space2,
          children: [
            PtaChip(status: _pta),
            TextButton(
              onPressed: imeiProblem(_imei1.text) != null
                  ? null
                  : () => unawaited(checkOn8484(context, _imei1.text)),
              child: Text(s.mobilePtaCheck),
            ),
            TextButton(
              onPressed: () async {
                final status = await askPtaAnswer(context, current: _pta);
                if (status != null && mounted) setState(() => _pta = status);
              },
              child: Text(s.mobilePtaWriteAnswer),
            ),
          ],
        ),
        const SizedBox(height: BlTokens.space3),
        BlField(
          controller: _condition,
          label: s.mobileCondition,
          hint: s.mobileConditionHint,
          maxLines: 2,
        ),
        const SizedBox(height: BlTokens.space4),

        BlSectionHeader(s.mobilePaidTitle),
        const SizedBox(height: BlTokens.space2),
        BlField(controller: _price, label: s.mobilePricePaid, numeric: true),
        if (accounts.length > 1) ...[
          const SizedBox(height: BlTokens.space3),
          DropdownButtonFormField<String>(
            initialValue:
                _accountId ??
                accounts.where((a) => a.modeLabel == 'cash').firstOrNull?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.mobilePaidFrom),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        ],
        if (_failure != null) ...[
          const SizedBox(height: BlTokens.space3),
          Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
        ],
        const SizedBox(height: BlTokens.space5),
        BlButton(
          label: s.mobileBuySave,
          icon: Icons.check,
          big: true,
          busy: _busy,
          onPressed: _busy || models == null
              ? null
              : () => unawaited(_save(models)),
        ),
      ],
    );
  }
}
