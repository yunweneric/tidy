import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/stat_tile.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// What was looked at, what stood out, and what could not be checked.
///
/// The third tile is the reason all three exist. The middle one is the only
/// number anybody reads, and a page that showed it alone would be claiming that
/// everything not listed was examined and found ordinary — which is exactly the
/// claim this module refuses to make.
class ProtectionSummary extends StatelessWidget {
  const ProtectionSummary({
    super.key,
    required this.checked,
    required this.notable,
    required this.unverified,
    required this.busy,
  });

  final int checked;
  final int notable;
  final int unverified;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Checked',
            value: busy && checked == 0 ? '—' : '$checked',
            icon: AppIcons.protection,
            color: colors.textSecondary,
            detail: 'startup items, apps and extensions',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            label: 'Worth a look',
            value: busy && checked == 0 ? '—' : '$notable',
            icon: AppIcons.review,
            color: notable == 0 ? colors.textSecondary : colors.review,
            detail: 'unsigned, unknown developer, broad access',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            label: 'Not checked',
            value: busy && checked == 0 ? '—' : '$unverified',
            icon: AppIcons.locked,
            color: unverified == 0 ? colors.textSecondary : colors.textMuted,
            detail: 'needs Full Disk Access or an administrator',
          ),
        ),
      ],
    );
  }
}

/// The standing caveat, which is not dismissible.
///
/// A caveat somebody can close is a caveat you did not mean. This one is the
/// difference between what the page does and what a reader coming from any
/// other "security" app will assume it does.
class ProtectionCaveat extends StatelessWidget {
  const ProtectionCaveat({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 17, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '${Brand.name} has no list of known bad software, and never '
              'downloads one. Everything here is a fact about a file already on '
              'this Mac: who signed it, where it was installed from, and what it '
              'can reach. A quiet page is not a clean bill of health.',
              style: context.text.bodyM,
            ),
          ),
        ],
      ),
    );
  }
}
