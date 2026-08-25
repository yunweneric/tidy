import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// A quiet line under a card saying what the numbers above it do not cover.
///
/// There are several of these and they are requirements rather than polish. The
/// page reports money it did not spend, over logs it did not write, priced from
/// a table that will age — `docs/ui.md` §9 says none of that may be left to a
/// tooltip, so each one is on screen, in `caption`, under the thing it
/// qualifies.
class UsageNote extends StatelessWidget {
  const UsageNote(this.text, {super.key, this.icon, this.tone});

  final String text;
  final IconData? icon;

  /// Overrides the muted default where the note is a warning rather than a
  /// footnote.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = tone ?? colors.textMuted;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 13, color: color),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              text,
              style: context.text.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
