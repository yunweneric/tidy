import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/updates/logic/update_bloc.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/gradient_button.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/core/widgets/version_badge.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// What version is running, and whether there is a newer one.
///
/// Reads the shell's [UpdateBloc] rather than owning one: the check runs at
/// launch whether or not anyone opens this page, and the toast that announces a
/// new version is the shell's. Two views of one instance.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpdateBloc, UpdateState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.hasUpdate) ...[
              _UpdateCard(state: state),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (state.status == UpdateStatus.failed && state.error != null) ...[
              _FailureCard(state: state),
              const SizedBox(height: AppSpacing.lg),
            ],
            SettingsGroup(
              children: [
                SettingsRow(
                  title: 'Version',
                  detail: _checkedLine(state),
                  control: VersionBadge(
                    version:
                        state.currentVersion.isEmpty
                            ? '—'
                            : state.currentVersion,
                  ),
                ),
                SettingsActionRow(
                  title: 'Check for updates',
                  detail:
                      'Asks GitHub whether a newer release of ${Brand.name} '
                      'has been published.',
                  actionLabel: _checkLabel(state),
                  onPressed:
                      state.isBusy
                          ? null
                          : () => context.read<UpdateBloc>().add(
                            const CheckForUpdates(manual: true),
                          ),
                ),
                SettingsSwitchRow(
                  title: 'Check automatically',
                  detail:
                      'Once a day, and shortly after ${Brand.name} opens. The '
                      'request asks for the latest release and sends nothing '
                      'about you or your Mac.',
                  value: settings.updateChecksEnabled,
                  onChanged: (value) => settings.updateChecksEnabled = value,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _checkLabel(UpdateState state) => switch (state.status) {
    UpdateStatus.checking => 'Checking…',
    UpdateStatus.upToDate => 'Check again',
    _ => 'Check now',
  };

  static String _checkedLine(UpdateState state) {
    if (state.status == UpdateStatus.upToDate) {
      return '${Brand.name} is up to date.';
    }
    final at = state.lastCheckedAt;
    if (at == null) return 'The version of ${Brand.name} you are running.';
    return 'Last checked ${_ago(at)}.';
  }

  static String _ago(DateTime time) {
    final elapsed = DateTime.now().difference(time);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) {
      return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
    }
    final days = elapsed.inDays;
    return '$days day${days == 1 ? '' : 's'} ago';
  }
}

/// The offer: what the release is, and the one button that moves it forward.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final release = state.release!;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors.accentGradient,
                  ),
                  borderRadius: AppRadii.mdAll,
                ),
                child: Icon(
                  AppIcons.downloads,
                  size: 18,
                  color: colors.textOnAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${Brand.name} ${release.version.display}',
                      style: context.text.titleM,
                    ),
                    Text(
                      _subtitle(state),
                      style: context.text.bodyM.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            // Plain text, deliberately. Release notes are a handful of bullet
            // points, and a markdown renderer to set them in bold would be a
            // dependency bigger than the feature it serves.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  release.notes,
                  style: context.text.bodyS.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
          if (state.status == UpdateStatus.downloading) ...[
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: AppRadii.pillAll,
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 6,
                backgroundColor: colors.surfaceHover,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              _action(context, state),
              const SizedBox(width: AppSpacing.md),
              if (state.status == UpdateStatus.downloading)
                TextButton(
                  onPressed:
                      () => context.read<UpdateBloc>().add(
                        const CancelDownload(),
                      ),
                  child: const Text('Cancel'),
                )
              else if (state.status == UpdateStatus.available)
                TextButton(
                  onPressed:
                      () => context.read<UpdateBloc>().add(
                        const SkipThisVersion(),
                      ),
                  child: const Text('Skip this version'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _action(BuildContext context, UpdateState state) {
    final bloc = context.read<UpdateBloc>();
    return switch (state.status) {
      UpdateStatus.available => GradientButton(
        label: 'Download',
        icon: AppIcons.downloads,
        onPressed: () => bloc.add(const DownloadUpdate()),
      ),
      UpdateStatus.downloading => const GradientButton(
        label: 'Downloading…',
        onPressed: null,
      ),
      UpdateStatus.verifying => const GradientButton(
        label: 'Checking…',
        onPressed: null,
      ),
      UpdateStatus.readyToInstall => GradientButton(
        label: 'Install and Relaunch',
        icon: AppIcons.restore,
        onPressed: () => bloc.add(const InstallUpdate()),
      ),
      UpdateStatus.installing => const GradientButton(
        label: 'Installing…',
        onPressed: null,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  static String _subtitle(UpdateState state) {
    final release = state.release!;
    return switch (state.status) {
      UpdateStatus.downloading when state.totalBytes > 0 =>
        '${formatBytes(state.receivedBytes)} of '
            '${formatBytes(state.totalBytes)}',
      UpdateStatus.downloading => 'Downloading…',
      UpdateStatus.verifying => 'Checking the download is genuine…',
      UpdateStatus.readyToInstall =>
        '${Brand.name} will restart to finish installing.',
      UpdateStatus.installing => 'Restarting…',
      _ =>
        release.zipBytes > 0
            ? 'A new version is available — ${formatBytes(release.zipBytes)}.'
            : 'A new version is available.',
    };
  }
}

/// A refusal, with a way out where there is one.
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dmg = state.release?.dmgUrl;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.risky, size: 18, color: colors.risky),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.error!, style: context.text.bodyM),
                // Only when installing by hand would actually work. An offer to
                // download the disk image after a rejected signature would be
                // an offer to install the thing that just failed its check.
                if (state.canRetryManually && dmg != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The disk image for this release is at $dmg',
                    style: context.text.bodyS.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
