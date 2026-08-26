import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// A card of related settings, optionally under a small uppercase heading.
///
/// The heading is left off when a section holds a single group: the detail
/// pane already names the section, and repeating it one line lower is noise.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.title});

  final String? title;

  /// Rows, laid out with a divider between each pair.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divider = Divider(
      height: AppSpacing.xxl,
      color: context.colors.border,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(title!.toUpperCase(), style: context.text.overline),
          ),
        TidyCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) divider,
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The title-and-explanation half of a settings row, dimmed when the control
/// beside it is not available.
class SettingsLabel extends StatelessWidget {
  const SettingsLabel({
    super.key,
    required this.title,
    required this.detail,
    this.enabled = true,
  });

  final String title;
  final String detail;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              enabled
                  ? context.text.titleS
                  : context.text.titleS.copyWith(color: muted),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          detail,
          style:
              enabled
                  ? context.text.bodyS
                  : context.text.bodyS.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// Label on the left, whatever control the setting needs on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    required this.detail,
    required this.control,
    this.enabled = true,
  });

  final String title;
  final String detail;
  final Widget control;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SettingsLabel(title: title, detail: detail, enabled: enabled),
        ),
        const SizedBox(width: AppSpacing.lg),
        control,
      ],
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// False greys the row out rather than hiding it: a setting that vanishes
  /// when its parent is off is a setting people cannot find again.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      detail: detail,
      enabled: enabled,
      control: Switch(value: value, onChanged: enabled ? onChanged : null),
    );
  }
}

/// A labelled row of mutually exclusive choices.
///
/// A `SegmentedButton` over presets rather than a number field, wherever the
/// value is a rough preference: "keep the last 500" is a decision someone makes
/// in a second, and a free-form box invites picking 137 and then wondering
/// whether it took.
class SettingsChoiceRow<T> extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.title,
    required this.detail,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.stacked,
  });

  final String title;
  final String detail;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool enabled;

  /// Put the control on a line of its own instead of beside the label.
  ///
  /// Null decides by how much text the options carry, which is the thing that
  /// actually breaks the row: a segmented button sizes *every* segment to its
  /// widest label, so four options averaging fourteen characters is some six
  /// hundred points of control. Beside it the explanation gets a column three
  /// words wide and eight lines tall, and the row ends up taller than the card
  /// it sits in. Past that much text the control has outgrown the row, and the
  /// fix is a line of its own rather than a smaller font.
  final bool? stacked;

  /// Total characters across every option label, past which the control moves
  /// down. Two or three short options stay on the line; four long ones do not.
  static const int _stackAbove = 34;

  /// A comfortable measure for the explanation once it is no longer boxed in by
  /// the control. Full width would be 130 characters a line.
  static const double _detailWidth = 560;

  bool get _isStacked =>
      stacked ??
      options.values.fold<int>(0, (sum, label) => sum + label.length) >
          _stackAbove;

  @override
  Widget build(BuildContext context) {
    final control = SegmentedButton<T>(
      segments: [
        for (final entry in options.entries)
          ButtonSegment(
            value: entry.key,
            label: Text(entry.value),
            enabled: enabled,
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged:
          enabled ? (selection) => onChanged(selection.first) : null,
    );

    if (!_isStacked) {
      return SettingsRow(
        title: title,
        detail: detail,
        enabled: enabled,
        control: control,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _detailWidth),
          child: SettingsLabel(title: title, detail: detail, enabled: enabled),
        ),
        const SizedBox(height: AppSpacing.md),
        // At its own width, not the card's. Stretched across the row, four
        // options would put two hundred points of nothing between one and the
        // next, and the group of them would stop reading as one control.
        Align(alignment: Alignment.centerLeft, child: control),
      ],
    );
  }
}

/// A row whose control is a button — the settings that *do* something rather
/// than store something.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onPressed,
    this.destructive = false,
  });

  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback? onPressed;

  /// Paints the button in the risky colour. For anything that removes data.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final risky = context.colors.risky;

    return SettingsRow(
      title: title,
      detail: detail,
      control: OutlinedButton(
        onPressed: onPressed,
        style:
            destructive
                ? OutlinedButton.styleFrom(
                  foregroundColor: risky,
                  side: BorderSide(color: risky.withValues(alpha: 0.45)),
                )
                : null,
        child: Text(actionLabel),
      ),
    );
  }
}
