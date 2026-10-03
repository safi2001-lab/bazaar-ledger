import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/bill_design_preview.dart';
import '../printing/pdf_font.dart';
import '../printing/printing_providers.dart';
import '../sales/receipt_screen.dart' show PaperPreview;
import 'shop_pictures.dart';

/// How the shop's bills look (M51): the layout, the colour, the page, the
/// logo, the payment QR, the khata block and the footer, with the look
/// shown as it is chosen.
///
/// Vyapar's theme picker is the first thing its users mention after the
/// bill itself, and its reviews from Pakistan say the same two things: the
/// Urdu must stay readable, and the shop wants its own name and colour on
/// the paper, not the app's. Eight layouts (M70 added a landscape page for
/// wholesale, the ruled bill book, a serif page and a bare one), each shown
/// as a picture of its page with the shop's own name on it, six colours, a
/// logo and a footer in any script cover both, and every one of them goes
/// through the same renderer the bills do. A quotation, a challan and a
/// purchase order may each have a layout of their own (M70).
///
/// The till roll is not designed here. It is 48 columns of the printer's
/// own font on every shop's counter; what the owner decides for it is how
/// tight it is or how large its total (M70), whether the khata block, the
/// footer and the QR go on it, and the second preview shows exactly the
/// strings the printer will be handed.
class BillDesignScreen extends ConsumerStatefulWidget {
  const BillDesignScreen({super.key});

  @override
  ConsumerState<BillDesignScreen> createState() => _BillDesignScreenState();
}

enum _Look { pdf, slip }

class _BillDesignScreenState extends ConsumerState<BillDesignScreen> {
  BillDesign? _draft;
  final _footer = TextEditingController();
  _Look _look = _Look.pdf;
  bool _busy = false;
  bool _sharing = false;
  String? _failure;

  /// Lines a shop can drop into its footer with one tap, in the three ways
  /// shops write them. Paper words, not the app's: the footer is printed as
  /// typed.
  static const _presets = [
    BillDesign.defaultThanks,
    'Bika hua maal wapas ya tabdeel nahi hoga',
    'Goods once sold will not be taken back or exchanged',
    'Tabdeeli sirf 7 din mein, bill ke saath',
    'شکریہ! پھر تشریف لائیں',
    'بکا ہوا مال واپس یا تبدیل نہیں ہوگا',
  ];

  @override
  void dispose() {
    _footer.dispose();
    super.dispose();
  }

  BillDesign get _design {
    final draft = _draft ?? const BillDesign();
    return draft.copyWith(
      footerLines: BillDesign.tidyFooter(_footer.text.split('\n')),
    );
  }

  void _set(BillDesign Function(BillDesign) change) =>
      setState(() => _draft = change(_draft ?? const BillDesign()));

  void _addPreset(String line) {
    final lines = _footer.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.contains(line) || lines.length >= BillDesign.footerLinesMax) {
      return;
    }
    setState(() => _footer.text = [...lines, line].join('\n'));
  }

  Future<void> _save() async {
    // First statement: two taps in one frame both reach here.
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).saveBillDesign(_design);
      container.bumpRefresh();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(s.billDesignSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '${s.commonSomethingWentWrong}: $error';
        });
      }
    }
  }

  /// The sample bill, through the very renderer every bill goes through,
  /// in the design as it stands on screen, to the share sheet — where a
  /// PDF viewer is one tap away.
  Future<void> _samplePdf(ReceiptData sample) async {
    if (_sharing) return;
    final s = AppStrings.of(context);
    setState(() => _sharing = true);
    try {
      final services = ref.read(appServicesProvider);
      final bytes = await services.receipts.toPdf(
        sample,
        unicodeFont: await PdfUnicodeFont.bytes(),
        design: _design,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}bill-design.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: s.settingsBillDesign,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _failure = '${s.commonSomethingWentWrong}: $error');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final saved = ref.watch(billDesignProvider);
    final firm = ref.watch(firmProvider).valueOrNull;
    final logo = ref.watch(shopLogoProvider).valueOrNull?.bytes;
    final qr = ref.watch(paymentQrProvider).valueOrNull?.bytes;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.settingsBillDesign)),
      body: SafeArea(
        child: saved.when(
          // Adding a logo refreshes everything; the screen keeps its place
          // and the owner's unsaved choices rather than blinking to a
          // skeleton and back to the top.
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 6),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(billDesignProvider),
            ),
          ),
          data: (design) {
            if (_draft == null) {
              _draft = design;
              _footer.text = design.footerLines.join('\n');
            }
            final now = _design;
            final sample = firm == null
                ? null
                : sampleBill(firm, now, logo: logo, paymentQr: qr);

            return ListView(
              padding: const EdgeInsets.all(BlTokens.space4),
              children: [
                Text(
                  s.billDesignIntro,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),

                BlSectionHeader(s.billDesignLayout),
                // M70: every design as a picture of its page, the shop's own
                // name and colour on each, two to a row on a phone.
                _ThemeGrid(
                  selected: now.theme,
                  pictureOf: firm == null
                      ? null
                      : (theme) => BillDesignThumbnail(
                          design: now.copyWith(theme: theme),
                          receipt: sampleBill(
                            firm,
                            now.copyWith(theme: theme),
                            logo: logo,
                            paymentQr: qr,
                          ),
                        ),
                  onPick: (theme) => _set((d) => d.copyWith(theme: theme)),
                ),
                const SizedBox(height: BlTokens.space1),
                Text(
                  themeWords(s, now.theme).$2,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                if (now.theme == BillTheme.taxInvoice &&
                    (firm?.ntn == null || firm?.strn == null))
                  Padding(
                    padding: const EdgeInsets.only(top: BlTokens.space1),
                    child: Text(
                      s.billDesignTaxNeedsNtn,
                      style: TextStyle(fontSize: 12, color: t.warning),
                    ),
                  ),
                // M70: a registered shop is told which designs are not a
                // sales tax invoice, rather than finding out from a buyer.
                if ((firm?.isSalesTaxRegistered ?? false) &&
                    !now.theme.carriesTaxParticulars)
                  Padding(
                    padding: const EdgeInsets.only(top: BlTokens.space1),
                    child: Text(
                      s.billDesignNotTaxInvoice,
                      style: TextStyle(fontSize: 12, color: t.warning),
                    ),
                  ),

                // M70: a quotation, a challan and an order in a layout of
                // their own, if the shop wants one.
                BlSectionHeader(s.billDesignPerPaper),
                Text(
                  s.billDesignPerPaperHint,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space2),
                for (final doc in BillDesign.themedDocuments)
                  _PaperTheme(
                    label: switch (doc) {
                      'quotation' => s.billDesignDocQuotation,
                      'delivery_challan' => s.billDesignDocChallan,
                      _ => s.billDesignDocOrder,
                    },
                    chosen: now.documentThemes[doc],
                    onPick: (theme) => _set(
                      (d) => d.copyWith(
                        documentThemes: {
                          for (final e in d.documentThemes.entries)
                            if (e.key != doc) e.key: e.value,
                          doc: ?theme,
                        },
                      ),
                    ),
                  ),

                BlSectionHeader(s.billDesignColour),
                Wrap(
                  spacing: BlTokens.space3,
                  runSpacing: BlTokens.space2,
                  children: [
                    for (final accent in BillAccent.values)
                      _Swatch(
                        accent: accent,
                        label: _accentName(s, accent),
                        selected: now.accent == accent,
                        onTap: () => _set((d) => d.copyWith(accent: accent)),
                      ),
                  ],
                ),

                BlSectionHeader(s.billDesignPage),
                SegmentedButton<BillPageSize>(
                  segments: const [
                    ButtonSegment(value: BillPageSize.a5, label: Text('A5')),
                    ButtonSegment(value: BillPageSize.a4, label: Text('A4')),
                  ],
                  selected: {now.pageSize},
                  onSelectionChanged: (v) =>
                      _set((d) => d.copyWith(pageSize: v.first)),
                ),

                BlSectionHeader(s.billDesignPictures),
                const ShopPictureField(kind: ShopPicture.logo),
                const SizedBox(height: BlTokens.space2),
                const ShopPictureField(kind: ShopPicture.paymentQr),
                const SizedBox(height: BlTokens.space1),
                Text(
                  s.settingsQrNote,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: now.qrOnThermal,
                  onChanged: (on) => _set((d) => d.copyWith(qrOnThermal: on)),
                  title: Text(s.billDesignQrOnThermal),
                  subtitle: Text(s.billDesignQrOnThermalHint),
                ),

                BlSectionHeader(s.billDesignKhata),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: now.showPreviousBalance,
                  onChanged: (on) =>
                      _set((d) => d.copyWith(showPreviousBalance: on)),
                  title: Text(s.billDesignKhata),
                  subtitle: Text(s.billDesignKhataHint),
                ),

                // M70: the till roll as it always was, tight, or with the
                // total large; the slip preview below shows it.
                BlSectionHeader(s.billDesignSlip),
                Wrap(
                  spacing: BlTokens.space2,
                  runSpacing: BlTokens.space1,
                  children: [
                    for (final slip in ReceiptSlip.values)
                      ChoiceChip(
                        label: Text(slipWords(s, slip).$1),
                        selected: now.slip == slip,
                        onSelected: (_) => _set((d) => d.copyWith(slip: slip)),
                      ),
                  ],
                ),
                Text(
                  slipWords(s, now.slip).$2,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),

                BlSectionHeader(s.billDesignFooter),
                BlField(
                  controller: _footer,
                  label: s.billDesignFooterLabel,
                  hint: s.billDesignFooterHint,
                  maxLines: BillDesign.footerLinesMax,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: BlTokens.space2),
                Text(
                  s.billDesignFooterPresets,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                Wrap(
                  spacing: BlTokens.space2,
                  runSpacing: BlTokens.space1,
                  children: [
                    for (final line in _presets)
                      ActionChip(
                        label: Text(line),
                        onPressed: () => _addPreset(line),
                      ),
                  ],
                ),

                BlSectionHeader(s.billDesignPreview),
                SegmentedButton<_Look>(
                  segments: [
                    ButtonSegment(
                      value: _Look.pdf,
                      label: Text(s.billDesignPreviewPdf),
                    ),
                    ButtonSegment(
                      value: _Look.slip,
                      label: Text(s.billDesignPreviewSlip),
                    ),
                  ],
                  selected: {_look},
                  onSelectionChanged: (v) => setState(() => _look = v.first),
                ),
                const SizedBox(height: BlTokens.space3),
                if (sample != null)
                  if (_look == _Look.pdf) ...[
                    // Half a phone's height at most, so the switch above and
                    // the button below stay in reach of the thumb.
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: BillDesignPreview(design: now, receipt: sample),
                      ),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      s.billDesignPreviewNote,
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    BlButton(
                      label: s.billDesignSamplePdf,
                      icon: Icons.picture_as_pdf_outlined,
                      kind: BlButtonKind.secondary,
                      busy: _sharing,
                      onPressed: _sharing
                          ? null
                          : () => unawaited(_samplePdf(sample)),
                    ),
                  ] else
                    // The strings the printer is handed, exactly: the khata
                    // block and the footer as they will come out.
                    SizedBox(height: 420, child: PaperPreview(data: sample)),
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
                  onPressed: _busy ? null : _save,
                ),
                const SizedBox(height: BlTokens.space6),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _accentName(AppStrings s, BillAccent accent) =>
      switch (accent) {
        BillAccent.ink => s.billAccentInk,
        BillAccent.blue => s.billAccentBlue,
        BillAccent.green => s.billAccentGreen,
        BillAccent.maroon => s.billAccentMaroon,
        BillAccent.orange => s.billAccentOrange,
        BillAccent.purple => s.billAccentPurple,
      };
}

//// A layout's name and what it is for (M51; M70's four added).
(String, String) themeWords(AppStrings s, BillTheme theme) => switch (theme) {
  BillTheme.classic => (s.billThemeClassic, s.billThemeClassicHint),
  BillTheme.modern => (s.billThemeModern, s.billThemeModernHint),
  BillTheme.compact => (s.billThemeCompact, s.billThemeCompactHint),
  BillTheme.taxInvoice => (s.billThemeTax, s.billThemeTaxHint),
  BillTheme.landscape => (s.billThemeLandscape, s.billThemeLandscapeHint),
  BillTheme.ruled => (s.billThemeRuled, s.billThemeRuledHint),
  BillTheme.elegant => (s.billThemeElegant, s.billThemeElegantHint),
  BillTheme.minimal => (s.billThemeMinimal, s.billThemeMinimalHint),
};

/// A till slip's name and what it is for (M70).
(String, String) slipWords(AppStrings s, ReceiptSlip slip) => switch (slip) {
  ReceiptSlip.standard => (s.billSlipStandard, s.billSlipStandardHint),
  ReceiptSlip.compact => (s.billSlipCompact, s.billSlipCompactHint),
  ReceiptSlip.bigTotal => (s.billSlipBigTotal, s.billSlipBigTotalHint),
};

/// Every layout as a picture of its page, two to a row on a phone and four
/// on a tablet (M70). Rows that grow with their words rather than a grid of
/// fixed cells, so a name at 200% wraps instead of overflowing.
class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({
    required this.selected,
    required this.pictureOf,
    required this.onPick,
  });

  final BillTheme selected;

  /// Null until the shop is read; the names are offered meanwhile.
  final Widget Function(BillTheme theme)? pictureOf;
  final ValueChanged<BillTheme> onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final across = constraints.maxWidth >= 560 ? 4 : 2;
      const themes = BillTheme.values;
      return Column(
        children: [
          for (var i = 0; i < themes.length; i += across)
            Padding(
              padding: const EdgeInsets.only(bottom: BlTokens.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = i; j < i + across; j++) ...[
                    if (j > i) const SizedBox(width: BlTokens.space2),
                    Expanded(
                      child: j < themes.length
                          ? _ThemeThumb(
                              theme: themes[j],
                              selected: themes[j] == selected,
                              picture: pictureOf?.call(themes[j]),
                              onTap: () => onPick(themes[j]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// One layout: its page in small, and its name under it, ringed when
/// chosen so the choice is never carried by colour alone.
class _ThemeThumb extends StatelessWidget {
  const _ThemeThumb({
    required this.theme,
    required this.selected,
    required this.picture,
    required this.onTap,
  });

  final BillTheme theme;
  final bool selected;
  final Widget? picture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final (name, _) = themeWords(s, theme);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(BlTokens.space1),
          decoration: BoxDecoration(
            color: selected ? t.surfaceRaised : null,
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
            border: Border.all(
              color: selected ? t.accent : t.line,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?picture,
              const SizedBox(height: BlTokens.space1),
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: selected ? t.accent : t.inkFaint,
                  ),
                  const SizedBox(width: BlTokens.space1),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One paper's own layout (M70): its name and what it is drawn in, a tap
/// from the list to choose from. "As the bill" until the shop picks one.
class _PaperTheme extends StatelessWidget {
  const _PaperTheme({
    required this.label,
    required this.chosen,
    required this.onPick,
  });

  final String label;
  final BillTheme? chosen;
  final ValueChanged<BillTheme?> onPick;

  Future<void> _choose(BuildContext context) async {
    final s = AppStrings.of(context);
    final t = context.bl;
    // A record, so "as the bill" (null) and "closed without choosing" are
    // two different answers.
    final picked = await showModalBottomSheet<({BillTheme? theme})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BlTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: BlTokens.space2),
              for (final option in <BillTheme?>[null, ...BillTheme.values])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    option == chosen
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: option == chosen ? t.accent : t.inkFaint,
                  ),
                  title: Text(
                    option == null
                        ? s.billDesignSameAsBill
                        : themeWords(s, option).$1,
                  ),
                  onTap: () => Navigator.of(sheet).pop((theme: option)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked.theme);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final chosen = this.chosen;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: () => unawaited(_choose(context)),
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space4,
          vertical: BlTokens.space3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    chosen == null
                        ? s.billDesignSameAsBill
                        : themeWords(s, chosen).$1,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

// One colour. Named for a screen reader, and ringed when chosen, so the
/// choice is never carried by colour alone.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final BillAccent accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BlTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(BlTokens.space1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(accent.argb),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? t.ink : t.line,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 18, color: t.accentInk)
                    : null,
              ),
              const SizedBox(height: BlTokens.space1),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: t.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
