import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/updates/logic/update_bloc.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

/// The "there is a newer version" prompt, pinned in the rail just above
/// Settings.
///
/// The only announcement an update gets: the shell used to raise a toast as
/// well, which said the same thing over the top of this row and had to be
/// dismissed to read it. A standing reminder does not need a transient one.
///
/// It sits beside Settings because that is where the full controls (release
/// notes, skip, the automatic-check preference) live, and it is one row tall
/// because the rail already carries a card — a second block the size of
/// [StorageSummary] would make the foot of the sidebar heavier than the
/// navigation above it.
///
/// Reads the shell's [UpdateBloc] directly rather than taking the state as a
/// parameter: unlike the disk figure, nothing above it in the tree needs to
/// know, and threading a state through [NavSidebar] only to hand it back down
/// would rebuild the whole rail on every download progress tick.
class SidebarUpdateChip extends StatelessWidget {
  const SidebarUpdateChip({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpdateBloc, UpdateState>(
      builder: (context, state) {
        final showing = _shows(state);

        // Animated rather than swapped in: the check lands seconds after
        // launch, and a row appearing under the user's cursor without motion
        // reads as a glitch.
        return AnimatedSize(
          duration: context.motion.normal,
          curve: context.motion.smooth,
          alignment: Alignment.bottomCenter,
          child:
              showing
                  ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: _UpdateChip(state: state),
                  )
                  // Full width, so growing in does not also change the rail's
                  // horizontal layout.
                  : const SizedBox(width: double.infinity),
        );
      },
    );
  }

  /// A failed update is worth a row too, but only when there is a release it
  /// failed at — an unreachable manual check is the Settings page's news, not
  /// the rail's.
  static bool _shows(UpdateState state) =>
      state.hasUpdate ||
      (state.status == UpdateStatus.failed && state.release != null);
}

class _UpdateChip extends StatefulWidget {
  const _UpdateChip({required this.state});

  final UpdateState state;

  @override
  State<_UpdateChip> createState() => _UpdateChipState();
}

class _UpdateChipState extends State<_UpdateChip> {
  bool _hovered = false;

  UpdateState get _state => widget.state;

  /// What pressing the body does. Downloading, verifying and installing have
  /// no action of their own, so they open the page that narrates them.
  void _primary() {
    final bloc = context.read<UpdateBloc>();
    switch (_state.status) {
      case UpdateStatus.available:
        bloc.add(const DownloadUpdate());
      case UpdateStatus.readyToInstall:
        bloc.add(const InstallUpdate());
      default:
        _openSettings();
    }
  }

  void _openSettings() =>
      context.go('${AppDestination.settings.path}?section=updates');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone =
        _state.status == UpdateStatus.failed ? colors.risky : colors.accent;

    return Tooltip(
      message: _tooltip(_state),
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _primary,
          child: AnimatedContainer(
            duration: context.motion.fast,
            curve: context.motion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: _hovered ? 0.2 : 0.12),
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(_icon(_state), size: 15, color: tone),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _label(_state),
                        overflow: TextOverflow.ellipsis,
                        style: context.text.caption.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ..._trailing(context, tone),
                  ],
                ),
                if (_showsProgress(_state)) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadii.xsAll,
                    child: LinearProgressIndicator(
                      // Null while the size is unknown and throughout the
                      // verify step, which is what makes the bar sweep instead
                      // of sitting at zero.
                      value:
                          _state.status == UpdateStatus.verifying
                              ? null
                              : _state.progress,
                      minHeight: 4,
                      backgroundColor: colors.surfaceHover,
                      valueColor: AlwaysStoppedAnimation(tone),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A second, smaller target beside the label: the way out of a download, or
  /// the way through to the release notes and the skip button.
  List<Widget> _trailing(BuildContext context, Color tone) {
    final (icon, onTap, semantics) = switch (_state.status) {
      UpdateStatus.downloading => (
        AppIcons.close,
        () => context.read<UpdateBloc>().add(const CancelDownload()),
        'Cancel the download',
      ),
      UpdateStatus.available || UpdateStatus.failed => (
        AppIcons.forward,
        _openSettings,
        'Update details',
      ),
      _ => (null, null, ''),
    };
    if (icon == null) return const [];

    return [
      const SizedBox(width: AppSpacing.xs),
      // Labelled rather than tooltipped: the whole chip already carries one,
      // and a second tooltip inside the first shows both at once.
      Semantics(
        button: true,
        label: semantics,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            // Padding rather than a bigger glyph: the row is 15px of text and
            // the tap target still wants to be pointer-sized.
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Icon(icon, size: 13, color: tone.withValues(alpha: 0.75)),
          ),
        ),
      ),
    ];
  }

  static bool _showsProgress(UpdateState state) =>
      state.status == UpdateStatus.downloading ||
      state.status == UpdateStatus.verifying;

  static IconData _icon(UpdateState state) => switch (state.status) {
    UpdateStatus.readyToInstall || UpdateStatus.installing => AppIcons.restore,
    UpdateStatus.failed => AppIcons.risky,
    _ => AppIcons.downloads,
  };

  static String _label(UpdateState state) {
    final version = state.release?.version.display ?? '';
    return switch (state.status) {
      UpdateStatus.downloading when state.progress != null =>
        'Downloading ${(state.progress! * 100).round()}%',
      UpdateStatus.downloading => 'Downloading…',
      UpdateStatus.verifying => 'Checking update…',
      UpdateStatus.readyToInstall => 'Restart to update',
      UpdateStatus.installing => 'Restarting…',
      UpdateStatus.failed => 'Update failed',
      _ => 'Update to $version',
    };
  }

  static String _tooltip(UpdateState state) {
    final version = state.release?.version.display ?? '';
    return switch (state.status) {
      UpdateStatus.readyToInstall =>
        '${Brand.name} $version is ready. It will restart to finish '
            'installing.',
      UpdateStatus.installing => 'Installing ${Brand.name} $version…',
      UpdateStatus.downloading =>
        'Downloading ${Brand.name} $version. The cross cancels it.',
      UpdateStatus.verifying => 'Checking the download is genuine…',
      UpdateStatus.failed => 'The update did not finish. Open the details.',
      _ =>
        'Download ${Brand.name} $version. The arrow opens the release notes.',
    };
  }
}
