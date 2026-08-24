import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// One figure worth reading before the table underneath it.
///
/// Promoted out of Recycle Bin's `bin_summary.dart` when Network wanted the same
/// shape: `docs/feature.md` §2 puts a widget two features use in `core/`, and
/// two pages quietly drifting apart on tile height and headline size is exactly
/// what the design system exists to stop.
///
/// This is the one place `docs/ui.md` allows a card to carry a colour — the tile
/// *is* the figure, so the colour is the information rather than decoration.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.detail,
    this.onTap,
    this.selected = false,
  });

  final String label;

  /// The headline. `displayL` carries tabular figures, so a value that ticks
  /// does not shuffle the ones beside it.
  final String value;

  final IconData icon;
  final Color color;

  /// An optional second line under the label — a date, a share, a caveat.
  final String? detail;

  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TidyCard(
      onTap: onTap,
      accent: color,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatIconTile(icon: icon, color: color),
          const SizedBox(height: AppSpacing.md),
          Text(value, style: context.text.displayL.copyWith(color: color)),
          const SizedBox(height: AppSpacing.xxs),
          Text(label, style: context.text.bodyS),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              detail!,
              style: context.text.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// The glyph on a summary tile, on its own gradient chip.
class StatIconTile extends StatelessWidget {
  const StatIconTile({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: AppRadii.mdAll,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
