import 'package:flutter/material.dart';

import 'tokens.dart';

/// "Add 'Surf Excel 1kg' as a new item": the way on from a search that found
/// nothing (M32).
///
/// A row rather than a `BlButton`, because what it carries is a sentence with
/// the shopkeeper's own words in it. A button is one line and ellipsises, and
/// at 200% on a 360dp phone the part it cut off was the name the cashier had
/// just typed — the one thing they read it for. Here the sentence wraps, to
/// three lines if it must, and the whole row is the tap target.
class BlAddOffer extends StatelessWidget {
  const BlAddOffer({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_box_outlined,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          child: Container(
            constraints: const BoxConstraints(minHeight: BlTokens.touchMin),
            padding: const EdgeInsets.symmetric(
              horizontal: BlTokens.space3,
              vertical: BlTokens.space2,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: t.accent),
              borderRadius: BorderRadius.circular(BlTokens.radiusMd),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: t.accent),
                const SizedBox(width: BlTokens.space3),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
