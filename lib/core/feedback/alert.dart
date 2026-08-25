import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback_tone.dart';
import 'package:tidy/core/widgets/ambient_background.dart';
import 'package:tidy/core/widgets/gradient_button.dart';

/// Shows a modal that wears the app's chrome instead of Material's.
///
/// [showDialog] is fine, but its transition and barrier are Material's rather
/// than ours: a scrim that is not `colors.overlay` and a duration that ignores
/// Reduce Motion. Everything modal in the app goes through here so both come
/// from tokens.
///
/// It also carries the module's colour across the Navigator. A dialog route is
/// pushed *above* `AmbientBackground`, so nothing inside it can see which
/// module opened it — which is why a dialog used to come out neutral navy on
/// an amber page, and why its primary button fell back to the brand ramp. The
/// palette is captured here, from a context that is still inside the module,
/// and re-provided around the dialog.
Future<T?> showTidyDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final colors = context.colors;
  final motion = context.motion;
  final palette = ModuleTint.read(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: colors.overlay,
    transitionDuration: motion.normal,
    pageBuilder: (dialogContext, _, _) {
      final dialog = Builder(builder: builder);
      return palette == null
          ? dialog
          : ModuleTint(palette: palette, child: dialog);
    },
    transitionBuilder: (dialogContext, animation, _, child) {
      // Scale from very close to 1: a dialog that springs in from small reads
      // as a phone alert, not a macOS sheet.
      final curved = CurvedAnimation(
        parent: animation,
        curve: motion.standard,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The modal frame: medallion, title, scrolling body, footer.
///
/// Use this directly whenever a dialog is more than a question — the uninstall
/// preview is a [TidyDialog] with a file list in it. For a question, reach for
/// [TidyAlert], which is this widget with the body filled in.
class TidyDialog extends StatelessWidget {
  const TidyDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.tone,
    this.icon,
    this.child,
    this.actions = const [],
    this.actionsLeading,
    this.width = 480,
    this.maxContentHeight = 360,
    this.showClose = true,
    this.onClose,
  });

  final String title;

  /// One line under the title. The place to say what the action actually does
  /// before the body gets into specifics.
  final String? subtitle;

  /// Draws the medallion. Left null there is no medallion — right for a
  /// working dialog whose title is enough.
  final FeedbackTone? tone;

  /// Overrides the tone's glyph.
  final IconData? icon;

  final Widget? child;

  /// Footer buttons, in reading order. The last one is the default action.
  final List<Widget> actions;

  /// Sits at the far left of the footer — a running total, a checkbox, a note.
  final Widget? actionsLeading;

  final double width;

  /// How tall the body may grow before it scrolls. The dialog is separately
  /// capped against the window, so this never pushes the footer off screen.
  final double maxContentHeight;

  final bool showClose;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dismiss = onClose ?? () => Navigator.of(context).maybePop();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            // Leaves room at the 1100×720 minimum window size.
            maxHeight: MediaQuery.sizeOf(context).height - AppSpacing.huge,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              decoration: BoxDecoration(
                // Solid, because it has to hide what is behind it — but made
                // of the module it was opened from, not of neutral grey. See
                // `AppColorTokens.floatingSurface`.
                color: colors.floatingSurface(ModuleTint.of(context)),
                borderRadius: AppRadii.xlAll,
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 48,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, colors, dismiss),
                  if (child != null)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: maxContentHeight,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xxl,
                            AppSpacing.lg,
                            AppSpacing.xxl,
                            AppSpacing.xl,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  if (actions.isNotEmpty || actionsLeading != null)
                    _footer(context, colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppColorTokens colors,
    VoidCallback dismiss,
  ) {
    final accent = tone?.color(colors);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        showClose ? AppSpacing.md : AppSpacing.xxl,
        child == null ? AppSpacing.sm : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (accent != null) ...[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: AppRadii.lgAll,
              ),
              child: Icon(icon ?? tone!.icon, size: 20, color: accent),
            ),
            const SizedBox(width: AppSpacing.lg),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(title, style: context.text.titleM),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: context.text.bodyM),
                ],
              ],
            ),
          ),
          if (showClose) ...[
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(AppIcons.close, size: 15),
              color: colors.textMuted,
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              onPressed: dismiss,
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppColorTokens colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        // Only when there is a body: the line is there to mark where scrolling
        // content stops, and without one it is a rule across nothing.
        border:
            child == null
                ? null
                : Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Whatever sits on the left claims the whole gap, so the actions land
          // against the right edge. A Flexible beside a Spacer would share the
          // free width with it and leave them short of it.
          if (actionsLeading != null)
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: actionsLeading!,
              ),
            )
          else
            const Spacer(),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            actions[i],
          ],
        ],
      ),
    );
  }
}

/// How a footer button is drawn.
enum TidyActionStyle {
  /// Cancel, Close, Not now. Reads as a way out, not a second choice.
  quiet,

  /// The action the dialog exists for. Wears the module's ramp.
  primary,

  /// The action the dialog exists for, when it removes something. Solid
  /// `risky` — a gradient makes a delete button look inviting.
  destructive,
}

/// A footer button.
///
/// This is where the “one `GradientButton` per screen” rule is kept for
/// modals: a dialog gets exactly one [TidyActionStyle.primary], and if the
/// action destroys something it gets a solid red one instead.
class TidyDialogAction extends StatelessWidget {
  const TidyDialogAction({
    super.key,
    required this.label,
    this.onPressed,
    this.style = TidyActionStyle.quiet,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final TidyActionStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return switch (style) {
      TidyActionStyle.quiet => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colors.textSecondary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
        child: Text(label, style: context.text.label),
      ),
      TidyActionStyle.primary => GradientButton(
        label: label,
        icon: icon,
        onPressed: onPressed,
      ),
      TidyActionStyle.destructive => ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.risky,
          foregroundColor: colors.textOnAccent,
          disabledBackgroundColor: colors.surface,
          disabledForegroundColor: colors.textMuted,
        ),
      ),
    };
  }
}

/// One line in an alert's detail list — usually a path and why it failed.
@immutable
class AlertDetail {
  const AlertDetail({
    required this.title,
    this.detail,
    this.tone,
    this.monospace = true,
  });

  final String title;

  /// The explanation under it. Wears [tone]'s colour when one is given.
  final String? detail;

  final FeedbackTone? tone;

  /// Filesystem paths are monospace so a column of them lines up. Turn it off
  /// for prose.
  final bool monospace;
}

/// A rich modal: medallion, message, optional detail list, one or two buttons.
///
/// Prefer the named constructors — [TidyAlert.confirm] for a question,
/// [TidyAlert.notify] for a report — over pushing this yourself.
class TidyAlert extends StatelessWidget {
  const TidyAlert({
    super.key,
    required this.title,
    this.message,
    this.tone = FeedbackTone.info,
    this.icon,
    this.details = const [],
    this.content,
    this.confirmLabel,
    this.cancelLabel,
    this.destructive = false,
    this.width = 460,
  });

  final String title;
  final String? message;
  final FeedbackTone tone;
  final IconData? icon;

  /// Rendered as a bordered block under the message. For "here is exactly what
  /// went wrong, path by path".
  final List<AlertDetail> details;

  /// Anything the message and the details cannot say — a checkbox, a preview.
  final Widget? content;

  /// The affirmative button. Omitted, the alert is a report with one way out.
  final String? confirmLabel;

  /// The way out. Omitted on a report, where the confirm button is the way out.
  final String? cancelLabel;

  /// Draws the confirm button solid red rather than as the module gradient.
  final bool destructive;

  final double width;

  /// Asks a question and resolves to what the user chose.
  ///
  /// Dismissing — Escape, the close button, a click on the scrim — counts as
  /// no, which is why [barrierDismissible] stays true for anything reversible
  /// and should be passed false only when a half-finished job is behind it.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Continue',
    String cancelLabel = 'Cancel',
    FeedbackTone tone = FeedbackTone.warning,
    bool destructive = false,
    IconData? icon,
    List<AlertDetail> details = const [],
    Widget? content,
    double width = 460,
    bool barrierDismissible = true,
  }) async {
    final result = await showTidyDialog<bool>(
      context,
      barrierDismissible: barrierDismissible,
      builder:
          (_) => TidyAlert(
            title: title,
            message: message,
            tone: tone,
            icon: icon,
            details: details,
            content: content,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            destructive: destructive,
            width: width,
          ),
    );
    return result ?? false;
  }

  /// Reports something that already happened. One button, and it closes.
  static Future<void> notify(
    BuildContext context, {
    required String title,
    String? message,
    FeedbackTone tone = FeedbackTone.info,
    IconData? icon,
    List<AlertDetail> details = const [],
    Widget? content,
    String dismissLabel = 'Close',
    double width = 520,
  }) {
    return showTidyDialog<void>(
      context,
      builder:
          (_) => TidyAlert(
            title: title,
            message: message,
            tone: tone,
            icon: icon,
            details: details,
            content: content,
            confirmLabel: dismissLabel,
            width: width,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBody = message != null || details.isNotEmpty || content != null;

    final body =
        hasBody
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message != null) Text(message!, style: context.text.bodyM),
                if (details.isNotEmpty) ...[
                  if (message != null) const SizedBox(height: AppSpacing.lg),
                  _DetailBlock(details: details),
                ],
                if (content != null) ...[
                  if (message != null || details.isNotEmpty)
                    const SizedBox(height: AppSpacing.lg),
                  content!,
                ],
              ],
            )
            : null;

    return TidyDialog(
      title: title,
      tone: tone,
      icon: icon,
      width: width,
      maxContentHeight: 340,
      actions: [
        if (cancelLabel != null)
          TidyDialogAction(
            label: cancelLabel!,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        if (confirmLabel != null)
          TidyDialogAction(
            label: confirmLabel!,
            style:
                destructive
                    ? TidyActionStyle.destructive
                    : TidyActionStyle.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
      child: body,
    );
  }
}

/// The detail list: one raised block, hairline-separated rows.
class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.details});

  final List<AlertDetail> details;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < details.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    details[i].title,
                    style:
                        details[i].monospace
                            ? context.text.mono
                            : context.text.titleS,
                  ),
                  if (details[i].detail != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      details[i].detail!,
                      style: context.text.caption.copyWith(
                        color: details[i].tone?.color(colors),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
