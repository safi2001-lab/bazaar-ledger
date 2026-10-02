import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pk_domain/pk_domain.dart' show quantityWords;
import 'package:pk_money/pk_money.dart';

import '../l10n/app_strings.dart';
import 'tokens.dart';

/// The component library.
///
/// Every screen composes from these. Nothing is bespoke, which is what makes
/// sixty screens look like one product instead of twelve, and what makes the
/// accessibility work happen once rather than sixty times.

// ---------------------------------------------------------------------------
// Money and quantity
// ---------------------------------------------------------------------------

/// An amount, in tabular figures, with a screen-reader label that reads the
/// whole value.
///
/// Colour is never the only signal: a negative amount carries a minus sign as
/// well as a colour, because roughly one in twelve men in this market cannot
/// tell the red from the green.
class BlMoney extends StatelessWidget {
  const BlMoney(
    this.amount, {
    super.key,
    this.size = 16,
    this.weight = FontWeight.w600,
    this.colour,
    this.showSign = false,
    this.withSymbol = false,
    this.semanticPrefix,
  });

  final Money amount;
  final double size;
  final FontWeight weight;
  final Color? colour;

  /// Draw an explicit + or − in front. Used in ledgers, not on a bill total.
  final bool showSign;

  final bool withSymbol;
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final resolved =
        colour ??
        (amount.isNegative
            ? t.moneyOut
            : showSign && amount.isPositive
            ? t.money
            : t.ink);

    final text = showSign
        ? amount.signed
        : withSymbol
        ? amount.toString()
        : amount.amountOnly;

    // The screen-reader rendering is localised like everything else. An
    // accessibility layer that only speaks English is an accessibility layer
    // for people who can already read the screen.
    final s = AppStrings.of(context);
    final spoken = amount.isNegative
        ? s.a11yOwing(amount.abs.amountOnly)
        : s.a11yRupees(amount.amountOnly);

    return Semantics(
      label: semanticPrefix == null ? spoken : '$semanticPrefix $spoken',
      excludeSemantics: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: resolved,
          fontFeatures: BlTokens.tabular,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// A quantity, which never renders a fraction as a whole number.
///
/// The previous build printed `quantity.toInt()` in the cart, so 0.750 kg of
/// mutton showed the cashier a zero while the arithmetic underneath was right.
class BlQty extends StatelessWidget {
  const BlQty(this.qty, {super.key, this.unit, this.size = 15, this.colour});

  final Qty qty;
  final String? unit;
  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    // Kilos with grams in them read as kilos and grams, "1 kg 500 g", the
    // way the shop says them (M56); everything else as the number and its
    // unit.
    final label = unit == null ? qty.display : quantityWords(qty, unit!);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Text(
        label,
        // One line, always. Wrapped onto two inside a fixed-height row this
        // paints straight over whatever is beneath it, and a quantity broken
        // across lines is a quantity the cashier misreads.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w500,
          color: colour ?? context.bl.ink,
          fontFeatures: BlTokens.tabular,
        ),
      ),
    );
  }
}

/// A label on the left and a figure hard against the right margin.
///
/// Every screen that shows a total was building this by hand as
/// `Row(children: [Text(label), Spacer(), FittedBox(child: BlMoney(...))])`,
/// and every one of them was broken in the same way. A non-flex child of a
/// `Row` is laid out with UNBOUNDED width, so the `FittedBox` sized itself to
/// the figure's natural width and `BoxFit.scaleDown` never scaled anything.
/// The protection those call sites were written to provide did not exist.
///
/// At 200% text on a 360dp screen the bill total was painted 93dp past the
/// right edge of the display. `BlCard` does not clip, and `Text` raises no
/// overflow assertion, so in release there was no ellipsis and no stripe —
/// "Rs 12,500.00" simply read as "Rs 12,500." and the cashier said the wrong
/// number out loud to the customer.
///
/// Two `Flexible` children give the figure a bounded width, so `scaleDown`
/// does its job: the number shrinks but is never cut. It is given twice the
/// label's share because it is the part that must survive — a label may
/// ellipsis, an amount may not.
class BlAmountRow extends StatelessWidget {
  const BlAmountRow({
    super.key,
    required this.label,
    required this.child,
    this.labelStyle,
    this.padding,
  });

  final String label;

  /// The figure. Usually a [BlMoney], but a [BlQty] or a chip works too.
  final Widget child;

  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            style: labelStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: BlTokens.space2),
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: child,
          ),
        ),
      ],
    );
    return padding == null ? row : Padding(padding: padding!, child: row);
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum BlButtonKind { primary, secondary, ghost, danger }

/// The one button.
///
/// One height, from one token. The design mock this was built from used three
/// different primary heights on three different screens.
class BlButton extends StatelessWidget {
  const BlButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = BlButtonKind.primary,
    this.icon,
    this.expand = false,
    this.big = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BlButtonKind kind;
  final IconData? icon;
  final bool expand;

  /// The billing keypad and the charge button. Used fastest, so given more.
  final bool big;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final enabled = onPressed != null && !busy;
    final height = big ? BlTokens.touchKeypad : BlTokens.touchMin;

    final (background, foreground, border) = switch (kind) {
      BlButtonKind.primary => (t.accent, t.accentInk, null),
      BlButtonKind.secondary => (t.surface, t.ink, t.lineStrong),
      BlButtonKind.ghost => (t.transparent, t.ink, null),
      BlButtonKind.danger => (t.dangerSurface, t.danger, t.danger),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: expand ? double.infinity : null,
        height: height,
        child: Material(
          color: enabled ? background : t.line,
          borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                border: border == null
                    ? null
                    : Border.all(color: enabled ? border : t.line),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BlTokens.space5,
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: enabled ? foreground : t.inkFaint,
                        ),
                      )
                    else if (icon != null)
                      Icon(
                        icon,
                        size: big ? 22 : 20,
                        color: enabled ? foreground : t.inkFaint,
                      ),
                    if (busy || icon != null)
                      const SizedBox(width: BlTokens.space2),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: big ? 17 : 15,
                          fontWeight: FontWeight.w700,
                          color: enabled ? foreground : t.inkFaint,
                        ),
                      ),
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

/// An icon-only control that always carries a label for a screen reader, and
/// always clears the 48dp floor.
///
/// The previous build had zero `Semantics` in the entire codebase and used
/// icon-only buttons as its primary navigation.
class BlIconButton extends StatelessWidget {
  const BlIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.colour,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    // IconButton's own `tooltip` already wraps the child in a Tooltip and
    // sets the semantic label. Wrapping it in a second one announced the
    // label twice to TalkBack.
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: colour ?? context.bl.ink,
      iconSize: 22,
      constraints: const BoxConstraints(
        minWidth: BlTokens.touchMin,
        minHeight: BlTokens.touchMin,
      ),
      tooltip: label,
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

class BlField extends StatelessWidget {
  const BlField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.validator,
    this.autofocus = false,
    this.focusNode,
    this.prefix,
    this.suffix,
    this.numeric = false,
    this.decimals = 2,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget? prefix;
  final Widget? suffix;
  final bool numeric;
  final int decimals;
  final int maxLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType:
          keyboardType ??
          (numeric
              ? TextInputType.numberWithOptions(decimal: decimals > 0)
              : TextInputType.text),
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      validator: validator,
      style: TextStyle(
        fontSize: 16,
        color: t.ink,
        fontWeight: numeric ? FontWeight.w600 : FontWeight.w400,
        fontFeatures: numeric ? BlTokens.tabular : null,
      ),
      textAlign: numeric ? TextAlign.right : TextAlign.start,
      inputFormatters: numeric
          ? [
              // Digits, one decimal point, and at most [decimals] after it.
              // Typing a third decimal into a price is a silent wrong price,
              // so it is refused at the keyboard rather than truncated later.
              FilteringTextInputFormatter.allow(
                RegExp(decimals > 0 ? r'[0-9.]' : r'[0-9]'),
              ),
              _DecimalLimit(decimals),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
    );
  }
}

class _DecimalLimit extends TextInputFormatter {
  const _DecimalLimit(this.decimals);

  final int decimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if ('.'.allMatches(text).length > 1) return oldValue;
    final dot = text.indexOf('.');
    if (dot >= 0 && text.length - dot - 1 > decimals) return oldValue;
    return newValue;
  }
}

// ---------------------------------------------------------------------------
// Structure
// ---------------------------------------------------------------------------

/// A bordered surface. Cards mean something here; they are not default
/// padding.
class BlCard extends StatelessWidget {
  const BlCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BlTokens.space4),
    this.onTap,
    this.accent = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final content = Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        border: Border.all(color: accent ? t.accent : t.line),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: t.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        child: content,
      ),
    );
  }
}

class BlSectionHeader extends StatelessWidget {
  const BlSectionHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space5,
        BlTokens.space4,
        BlTokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: t.inkMuted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A status chip. Always carries text, never colour alone.
class BlChip extends StatelessWidget {
  const BlChip(
    this.label, {
    super.key,
    this.tone = BlChipTone.neutral,
    this.icon,
  });

  final String label;
  final BlChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final (bg, fg) = switch (tone) {
      BlChipTone.neutral => (t.paper, t.inkMuted),
      BlChipTone.good => (
        t.money.withValues(alpha: t.isDark ? 0.18 : 0.10),
        t.money,
      ),
      BlChipTone.warn => (t.warningSurface, t.warning),
      BlChipTone.bad => (t.dangerSurface, t.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BlTokens.space2,
        vertical: BlTokens.space1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BlTokens.radiusSm),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          // A chip carries a khata balance more often than a word, so it
          // renders in the same tabular figures as every other money cell and
          // gives way rather than overflowing its row.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
                fontFeatures: BlTokens.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum BlChipTone { neutral, good, warn, bad }

// ---------------------------------------------------------------------------
// The five states every screen must be able to draw
// ---------------------------------------------------------------------------

/// Nothing here yet, and the action that fixes it.
///
/// Nine of the previous build's twelve screens had no empty, loading or error
/// state at all, and the three that did rendered `Center(child: Text('Error:
/// $e'))`.
class BlEmpty extends StatelessWidget {
  const BlEmpty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    // Scrollable when there is a height to overflow, and a plain column when
    // there is not.
    //
    // Both cases are real. Inside an Expanded on a short landscape viewport
    // this content is taller than its box and must scroll. Inside a ListView
    // — which is where the home screen puts the empty state, on every fresh
    // install — the box has no height at all, and an unconditional
    // SingleChildScrollView throws "Vertical viewport was given unbounded
    // height" and red-screens the first thing a new user ever sees.
    return _Fits(
      child: Padding(
        padding: const EdgeInsets.all(BlTokens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: t.inkFaint),
            const SizedBox(height: BlTokens.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: t.inkMuted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: BlTokens.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// What happened, and a retry that works.
class BlError extends StatelessWidget {
  const BlError({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.reassurance,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  /// "Nothing was saved." A shopkeeper's first question after an error is
  /// whether their books are now wrong.
  final String? reassurance;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    // Scrollable when there is a height to overflow, and a plain column when
    // there is not.
    //
    // Both cases are real. Inside an Expanded on a short landscape viewport
    // this content is taller than its box and must scroll. Inside a ListView
    // — which is where the home screen puts the empty state, on every fresh
    // install — the box has no height at all, and an unconditional
    // SingleChildScrollView throws "Vertical viewport was given unbounded
    // height" and red-screens the first thing a new user ever sees.
    return _Fits(
      child: Padding(
        padding: const EdgeInsets.all(BlTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: t.danger),
            const SizedBox(height: BlTokens.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: t.inkMuted),
            ),
            if (reassurance != null) ...[
              const SizedBox(height: BlTokens.space3),
              Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  color: t.warningSurface,
                  borderRadius: BorderRadius.circular(BlTokens.radiusSm),
                ),
                child: Text(
                  reassurance!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: t.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: BlTokens.space5),
              BlButton(
                label: retryLabel ?? AppStrings.of(context).actionRetry,
                onPressed: onRetry,
                kind: BlButtonKind.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Scrolls when it has a height to overflow, and does not when it has none.
///
/// The distinction matters because both parents are real and neither is
/// avoidable: an `Expanded` gives a bounded height that the content can exceed,
/// and a `ListView` gives no height at all, in which case a viewport inside a
/// viewport is an error rather than a fallback.
class _Fits extends StatelessWidget {
  const _Fits({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.hasBoundedHeight
        ? SingleChildScrollView(child: child)
        : child,
  );
}

/// A skeleton, not a spinner over a blank page.
class BlSkeletonList extends StatelessWidget {
  const BlSkeletonList({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    // A Column, not a ListView. A fixed handful of grey blocks never needs to
    // scroll, and a scrollable here cannot be dropped into a page that is
    // already a list — which is exactly where the home screen puts it, and
    // where a nested viewport throws "unbounded height" and takes the whole
    // screen down with it.
    //
    // It draws as many rows as there is room for, and no more. A skeleton is
    // a hint that something is coming, not content: overflowing its box to
    // show a sixth grey rectangle nobody will read is strictly worse than
    // showing four.
    return LayoutBuilder(
      builder: (context, constraints) {
        const rowHeight = 64.0 + BlTokens.space2;
        final fits = constraints.hasBoundedHeight
            ? ((constraints.maxHeight - BlTokens.space8) ~/ rowHeight).clamp(
                1,
                rows,
              )
            : rows;
        return _skeleton(context, t, fits);
      },
    );
  }

  Widget _skeleton(BuildContext context, BlTokens t, int rows) {
    return Padding(
      padding: const EdgeInsets.all(BlTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: BlTokens.space2),
            Semantics(
              label: i == 0 ? AppStrings.of(context).a11yLoading : null,
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                  border: Border.all(color: t.line),
                ),
                padding: const EdgeInsets.all(BlTokens.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 12,
                      decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A quiet, permanent statement that the app does not need the network.
///
/// Pakistan lost 9,735 hours to internet disruption in 2024, the worst in the
/// world. Offline is the product, not an error state, so this is informational
/// and never blocks anything.
class BlOfflineNote extends StatelessWidget {
  const BlOfflineNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: BlTokens.space4,
        vertical: BlTokens.space2,
      ),
      color: t.warningSurface,
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: t.warning),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: t.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
