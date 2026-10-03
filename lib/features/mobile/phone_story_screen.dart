import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../attachments/attachment_strip.dart';
import '../sales/receipt_screen.dart';
import 'imei_words.dart';
import 'mobile_providers.dart';
import 'pta.dart';
import 'qist_plan_screen.dart';

/// A phone's whole story (M50): where it came from and at what cost, who
/// it went to on which bill, what came back, its warranty and the claims
/// made on it, what PTA said of it, and — for one bought used over the
/// counter — who sold it, by CNIC, with the photographs.
///
/// The page a shop opens when the police, PTA or a customer with a dead
/// screen asks about one phone.
class PhoneStoryScreen extends ConsumerWidget {
  const PhoneStoryScreen({super.key, required this.lotId, required this.title});

  final String lotId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final story = ref.watch(phoneStoryProvider(lotId));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: story.when(
        loading: () => const BlSkeletonList(rows: 4),
        error: (e, _) => BlError(
          title: s.commonSomethingWentWrong,
          message: '$e',
          onRetry: () => ref.invalidate(phoneStoryProvider(lotId)),
        ),
        data: (story) => story == null
            ? BlEmpty(title: s.mobileStoryGone)
            : _Story(story: story),
      ),
    );
  }
}

class _Story extends ConsumerWidget {
  const _Story({required this.story});

  final PhoneStory story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mobile = ref.watch(appServicesProvider).mobile;
    final today = mobile.today;
    final unit = story.unit;
    final seller = story.seller;
    final until = story.warrantyUntil;

    return ListView(
      padding: const EdgeInsets.all(BlTokens.space4),
      children: [
        BlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit.itemName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: BlTokens.space2),
              SelectableText(
                unit.imei2 == null
                    ? 'IMEI: ${unit.imei1}'
                    : 'IMEI 1: ${unit.imei1}\nIMEI 2: ${unit.imei2}',
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space1,
                children: [
                  BlChip(
                    unit.onHand ? s.mobileInShop : s.mobileNotInShop,
                    tone: unit.onHand ? BlChipTone.good : BlChipTone.neutral,
                  ),
                  PtaChip(status: unit.pta),
                ],
              ),
              if (unit.imei2 == null && mobile.canBuyPhones)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(s.mobileAddImei2),
                    onPressed: () => unawaited(_addImei2(context, ref)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: BlTokens.space4),

        // What PTA said, and asking it again.
        BlSectionHeader(s.mobilePtaTitle),
        const SizedBox(height: BlTokens.space2),
        BlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit.ptaCheckedOn == null
                    ? ptaWords(s, unit.pta)
                    : s.mobilePtaCheckedOn(
                        ptaWords(s, unit.pta),
                        shortDate(
                          unit.ptaCheckedOn!.value,
                          thisYear: today.year,
                        ),
                      ),
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
              if (unit.pta?.mayBeBlocked ?? false) ...[
                const SizedBox(height: BlTokens.space2),
                Text(
                  s.mobilePtaBlockedNote,
                  style: TextStyle(fontSize: 13, color: t.danger),
                ),
              ],
              const SizedBox(height: BlTokens.space3),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  BlButton(
                    label: s.mobilePtaCheck,
                    icon: Icons.sms_outlined,
                    kind: BlButtonKind.secondary,
                    onPressed: () =>
                        unawaited(checkOn8484(context, unit.imei1)),
                  ),
                  if (mobile.canHandlePhones)
                    BlButton(
                      label: s.mobilePtaWriteAnswer,
                      icon: Icons.edit_note_outlined,
                      kind: BlButtonKind.secondary,
                      onPressed: () => unawaited(_writePta(context, ref)),
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
              Text(
                s.mobilePtaHow,
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: BlTokens.space4),

        // Its warranty and the claims made on it.
        BlSectionHeader(s.mobileWarrantyTitle),
        const SizedBox(height: BlTokens.space2),
        BlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (until == null)
                Text(
                  s.mobileWarrantyNone,
                  style: TextStyle(fontSize: 14, color: t.inkMuted),
                )
              else ...[
                Text(
                  s.mobileWarrantyTill(printedDate(until)),
                  style: TextStyle(fontSize: 14, color: t.ink),
                ),
                const SizedBox(height: BlTokens.space2),
                Wrap(
                  spacing: BlTokens.space2,
                  children: [
                    BlChip(
                      story.inWarrantyOn(today)
                          ? s.mobileInWarranty
                          : s.mobileOutOfWarranty,
                      tone: story.inWarrantyOn(today)
                          ? BlChipTone.good
                          : BlChipTone.neutral,
                    ),
                    if (story.warrantyKind case final kind?)
                      BlChip(
                        kind == WarrantyKind.brand
                            ? s.mobileWarrantyBrand
                            : s.mobileWarrantyShop,
                      ),
                  ],
                ),
              ],
              for (final claim in story.claims) ...[
                const SizedBox(height: BlTokens.space2),
                Text(
                  '${shortDate(claim.on.value, thisYear: today.year)} · '
                  '${claim.note}'
                  '${claim.byName == null ? '' : ' · ${claim.byName}'}',
                  style: TextStyle(fontSize: 13, color: t.ink),
                ),
              ],
              if (mobile.canHandlePhones)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.build_outlined),
                    label: Text(s.mobileClaimAdd),
                    onPressed: () => unawaited(_addClaim(context, ref)),
                  ),
                ),
            ],
          ),
        ),
        if (story.qistPlanId case final planId?) ...[
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.mobileQistOpenPlan,
            icon: Icons.calendar_month_outlined,
            kind: BlButtonKind.secondary,
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QistPlanScreen(planId: planId),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: BlTokens.space4),

        // Who sold it to the shop, when it was bought used.
        if (seller != null) ...[
          BlSectionHeader(s.mobileSellerTitle),
          const SizedBox(height: BlTokens.space2),
          BlCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seller.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                SelectableText(
                  'CNIC ${cnicDisplay(seller.cnic)}'
                  '${seller.phone == null ? '' : '\n${seller.phone}'}',
                  style: TextStyle(fontSize: 13, color: t.ink),
                ),
                if (seller.conditionNote case final note?)
                  Text(note, style: TextStyle(fontSize: 13, color: t.inkMuted)),
                if (seller.partyId case final partyId?)
                  AttachmentStrip(owner: AttachmentOwner.party(partyId)),
                if (story.boughtUsedOn case final documentId?)
                  AttachmentStrip(owner: AttachmentOwner.document(documentId)),
              ],
            ),
          ),
          const SizedBox(height: BlTokens.space4),
        ],

        BlSectionHeader(s.mobileStoryTitle),
        const SizedBox(height: BlTokens.space2),
        if (story.events.isEmpty)
          Text(
            s.mobileStoryEmpty,
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
        for (final e in story.events)
          _EventTile(event: e, thisYear: today.year),
      ],
    );
  }

  Future<void> _writePta(BuildContext context, WidgetRef ref) async {
    final status = await askPtaAnswer(context, current: story.unit.pta);
    if (status == null || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .mobile
          .setPta(story.unit.lotId, status);
      container.bumpRefresh();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _addImei2(BuildContext context, WidgetRef ref) async {
    final s = AppStrings.of(context);
    final field = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.mobileAddImei2),
        content: BlField(
          controller: field,
          label: 'IMEI 2',
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: Text(s.actionSave),
          ),
        ],
      ),
    );
    field.dispose();
    if (typed == null || typed.trim().isEmpty || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .mobile
          .setImei2(story.unit.lotId, typed);
      container.bumpRefresh();
    } on ImeiRefused catch (refused) {
      messenger.showSnackBar(
        SnackBar(content: Text(imeiProblemWords(s, refused.problem))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _addClaim(BuildContext context, WidgetRef ref) async {
    final s = AppStrings.of(context);
    final field = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.mobileClaimAdd),
        content: BlField(
          controller: field,
          label: s.mobileClaimNote,
          hint: s.mobileClaimHint,
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: Text(s.actionSave),
          ),
        ],
      ),
    );
    field.dispose();
    if (note == null || note.trim().isEmpty || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .mobile
          .recordWarrantyClaim(story.unit.lotId, note);
      container.bumpRefresh();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

/// One line of the story: what happened, when, with whom, on which paper.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.thisYear});

  final PhoneEvent event;
  final int thisYear;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final who = event.partyName ?? s.mobileEventWalkIn;
    final what = switch (event.kind) {
      PhoneEventKind.bought => s.mobileEventBought(who),
      PhoneEventKind.sold => s.mobileEventSold(who),
      PhoneEventKind.returned => s.mobileEventReturned(who),
      PhoneEventKind.sentBack => s.mobileEventSentBack(who),
      PhoneEventKind.moved => s.mobileEventMoved,
      PhoneEventKind.adjusted => s.mobileEventAdjusted,
    };
    final icon = switch (event.kind) {
      PhoneEventKind.bought => Icons.south_west,
      PhoneEventKind.sold => Icons.north_east,
      PhoneEventKind.returned => Icons.undo,
      PhoneEventKind.sentBack => Icons.reply_all,
      PhoneEventKind.moved => Icons.swap_horiz,
      PhoneEventKind.adjusted => Icons.tune,
    };
    final details = [
      shortDate(event.on.value, thisYear: thisYear),
      ?event.docNo,
      if (event.amount case final amount?) 'Rs ${amount.amountOnly}',
      if (event.warrantyUntil case final until?)
        s.mobileWarrantyTill(printedDate(until)),
      if (event.cancelled) s.mobileEventCancelled,
    ].join(' · ');
    final documentId = event.documentId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: event.cancelled ? t.inkFaint : t.ink),
      title: Text(
        what,
        style: TextStyle(
          decoration: event.cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(details),
      trailing: documentId == null ? null : const Icon(Icons.chevron_right),
      onTap: documentId == null
          ? null
          : () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReceiptScreen(
                    documentId: documentId,
                    docNo: event.docNo ?? '',
                  ),
                ),
              ),
            ),
    );
  }
}
