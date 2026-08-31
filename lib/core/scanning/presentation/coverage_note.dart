import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// States plainly which checks a sweep runs and which do not exist yet.
///
/// Composite modules have a name that sounds complete — "Smart Care", "My
/// Clutter" — while running a subset of what that name implies. A clean result
/// from a sweep that only looked at half of what the user assumed is worse than
/// no result, so every composite says its own scope out loud, in the same shape,
/// from this one widget.
///
/// Shown on the first visit to a module and never again: the information is
/// essential once and is clutter above every scan after that. Which visit counts
/// as the first is the caller's to decide — it passes [seen] and [onSeen] and
/// keeps its own flag, because dismissing one module's note says nothing about
/// whether the user has read another's.
class CoverageNote extends StatefulWidget {
  const CoverageNote({
    super.key,
    required this.covered,
    required this.notYetCovered,
    required this.seen,
    required this.onSeen,
    this.title = 'What this sweep covers',
    this.footnote,
    this.gapBelow = false,
  });

  /// Checks that run today.
  final List<String> covered;

  /// Checks the module's name implies but that are not built.
  final List<String> notYetCovered;

  /// Whether this note has already been shown once.
  final bool seen;

  /// Records that it has now been shown.
  final VoidCallback onSeen;

  final String title;

  /// An extra line under the chips, for anything the lists cannot say on their
  /// own.
  final String? footnote;

  /// Reserve space beneath the card for a sibling banner. The gap belongs to
  /// this widget rather than to the parent column so that dismissing the note
  /// takes its spacing with it, instead of leaving a hole.
  final bool gapBelow;

  @override
  State<CoverageNote> createState() => _CoverageNoteState();
}

class _CoverageNoteState extends State<CoverageNote> {
  /// Captured once, in initState, rather than read on every build: the visit is
  /// marked seen immediately, and reading the flag live would make the note
  /// vanish out from under whoever is still reading it.
  late final bool _visible = !widget.seen;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    widget.onSeen();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _dismissed) return const SizedBox.shrink();

    final colors = context.colors;
    final built = widget.covered.length;
    final total = built + widget.notYetCovered.length;

    return Container(
      margin: EdgeInsets.only(bottom: widget.gapBelow ? AppSpacing.md : 0),
      child: TidyCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentMuted,
                borderRadius: AppRadii.mdAll,
              ),
              child: Icon(AppIcons.info, size: 16, color: colors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(widget.title, style: context.text.titleS),
                      ),
                      // The ratio, up front. The chips below say which checks
                      // are missing; this says how much of the module is
                      // missing, which is the thing someone deciding whether to
                      // trust a clean result actually wants.
                      Text(
                        '$built of $total checks built',
                        style: context.text.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Built and pending checks share one aligned grid rather
                  // than sitting in two blocks: the reader's question is "is
                  // the thing I care about in here?", which is a scan down one
                  // list, and the icon carries the answer per row. Two columns
                  // while there is room, one when the window is narrow.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoUp = constraints.maxWidth >= 420;
                      final width =
                          twoUp
                              ? (constraints.maxWidth - AppSpacing.lg) / 2
                              : constraints.maxWidth;
                      return Wrap(
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final item in widget.covered)
                            SizedBox(
                              width: width,
                              child: _Check(label: item, built: true),
                            ),
                          for (final item in widget.notYetCovered)
                            SizedBox(
                              width: width,
                              child: _Check(label: item, built: false),
                            ),
                        ],
                      );
                    },
                  ),
                  if (widget.footnote case final footnote?) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      footnote,
                      style: context.text.bodyS.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _NeverAgain(
                    onChanged: () => setState(() => _dismissed = true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One check, built or not. The icon does the work: a tick for what runs, a
/// clock for what is coming. Never a cross — the check has not failed, it has
/// not shipped, and those should not look the same.
class _Check extends StatelessWidget {
  const _Check({required this.label, required this.built});

  final String label;
  final bool built;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          built ? AppIcons.check : AppIcons.pending,
          size: 14,
          color: built ? colors.safe : colors.textMuted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: context.text.bodyS.copyWith(
              color: built ? colors.textSecondary : colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The dismiss control. A checkbox rather than an X, because the question is
/// "should this come back?" and not "close this".
class _NeverAgain extends StatelessWidget {
  const _NeverAgain({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: AppRadii.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 18,
              child: Checkbox(value: false, onChanged: (_) => onChanged()),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text("Don't show this again", style: context.text.bodyS),
          ],
        ),
      ),
    );
  }
}
