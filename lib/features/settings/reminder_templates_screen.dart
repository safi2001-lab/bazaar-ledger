import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/reminder_queue_screen.dart' show reminderLanguageName;
import '../parties/quick_party_sheet.dart' show refusalWords;

/// The words a reminder goes out in, one set per language, the owner's to
/// change (M39).
///
/// Each language's message is shown as it is now — the shop's own words
/// until somebody writes theirs — with the placeholders a tap away and the
/// message filled in below exactly as a customer would read it. "Back to
/// the shop's words" puts the original back; nothing typed is lost to a
/// mistake that cannot be undone.
class ReminderTemplatesScreen extends ConsumerStatefulWidget {
  const ReminderTemplatesScreen({super.key});

  @override
  ConsumerState<ReminderTemplatesScreen> createState() =>
      _ReminderTemplatesScreenState();
}

class _ReminderTemplatesScreenState
    extends ConsumerState<ReminderTemplatesScreen> {
  ReminderLanguage _language = ReminderLanguage.romanUrdu;
  final _controllers = {
    for (final l in ReminderLanguage.values) l: TextEditingController(),
  };
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final udhaar = ref.read(appServicesProvider).udhaar;
    for (final l in ReminderLanguage.values) {
      _controllers[l]!.text = await udhaar.reminderTemplate(l);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController get _text => _controllers[_language]!;

  /// Puts [placeholder] where the cursor is, or at the end.
  void _insert(String placeholder) {
    final value = _text.value;
    final at = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final end = value.selection.isValid ? value.selection.end : at;
    final text = value.text.replaceRange(at, end, placeholder);
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + placeholder.length),
    );
    setState(() {});
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .udhaar
          .saveReminderTemplate(_language, _text.text);
      messenger.showSnackBar(SnackBar(content: Text(s.templatesSaved)));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(refusalWords(error))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reset() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final udhaar = ref.read(appServicesProvider).udhaar;
      await udhaar.resetReminderTemplate(_language);
      _text.text = await udhaar.reminderTemplate(_language);
      messenger.showSnackBar(SnackBar(content: Text(s.templatesResetDone)));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(refusalWords(error))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final firm = ref.watch(firmProvider).valueOrNull;
    final today = ref.watch(appServicesProvider).udhaar.today;
    final rtl = _language == ReminderLanguage.urdu;
    final preview = fillReminder(
      _text.text,
      ReminderFacts(
        name: s.templatesSampleName,
        amount: const Money.rupees(4500),
        shop: firm?.name ?? s.appName,
        dueDateLocal: BusinessDate(today).addDays(-3).value,
        oldestBillDateLocal: BusinessDate(today).addDays(-33).value,
        shopPhone: firm?.phone,
        wallet: walletLine(
          raastAlias: firm?.raastAlias,
          bankName: firm?.bankName,
          accountTitle: firm?.bankAccountTitle,
          iban: firm?.bankIban,
        ),
      ),
      _language,
    );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.templatesTitle)),
      body: SafeArea(
        child: !_loaded
            ? const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              )
            : ListView(
                padding: const EdgeInsets.all(BlTokens.space4),
                children: [
                  Text(
                    s.templatesHint,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      for (final l in ReminderLanguage.values)
                        ChoiceChip(
                          selected: _language == l,
                          label: Text(reminderLanguageName(s, l)),
                          onSelected: (_) => setState(() => _language = l),
                        ),
                    ],
                  ),
                  const SizedBox(height: BlTokens.space3),
                  TextField(
                    key: ValueKey(_language),
                    controller: _text,
                    minLines: 6,
                    maxLines: 12,
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 15, color: t.ink),
                    decoration: InputDecoration(labelText: s.templatesField),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      for (final p in reminderPlaceholders)
                        ActionChip(label: Text(p), onPressed: () => _insert(p)),
                    ],
                  ),
                  const SizedBox(height: BlTokens.space4),
                  Text(
                    s.templatesPreview,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.inkMuted,
                    ),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  BlCard(
                    child: Text(
                      preview,
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: TextStyle(fontSize: 14, color: t.ink),
                    ),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  BlButton(
                    label: s.actionSave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy ? null : () => unawaited(_save()),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  BlButton(
                    label: s.templatesReset,
                    icon: Icons.restore,
                    kind: BlButtonKind.ghost,
                    onPressed: _busy ? null : () => unawaited(_reset()),
                  ),
                ],
              ),
      ),
    );
  }
}
