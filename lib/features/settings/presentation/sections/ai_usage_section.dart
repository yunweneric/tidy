import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_service.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// Which AI CLIs the usage page reads, and the way out if its numbers look
/// wrong.
class AiUsageSection extends StatefulWidget {
  const AiUsageSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<AiUsageSection> createState() => _AiUsageSectionState();
}

class _AiUsageSectionState extends State<AiUsageSection> {
  bool _rebuilding = false;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Says what is read before offering to read more of it. These files
        // hold prompts and file paths, so "Tidy looks at your Claude Code
        // history" deserves a plain answer about what it takes from them.
        TidyCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.info,
                size: 17,
                color: context.colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${Brand.name} reads the session logs these tools already '
                  'write to your home folder, and takes four things from each '
                  'reply: when it happened, which model answered, how many '
                  'tokens it used, and which folder you were working in. The '
                  'text of your prompts is never read, nothing is sent '
                  'anywhere, and Full Disk Access is not needed to read any '
                  'of it.',
                  style: context.text.bodyM,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'What to read',
          children: [
            SettingsSwitchRow(
              title: 'Claude Code',
              detail: _detail(AiProvider.claudeCode, 'projects'),
              value: settings.aiUsageIncludeClaude,
              onChanged:
                  (value) => setState(() {
                    settings.aiUsageIncludeClaude = value;
                  }),
            ),
            SettingsSwitchRow(
              title: 'Codex',
              detail: _detail(AiProvider.codex, 'sessions'),
              value: settings.aiUsageIncludeCodex,
              onChanged:
                  (value) => setState(() {
                    settings.aiUsageIncludeCodex = value;
                  }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Cache',
          children: [
            SettingsActionRow(
              title: 'Rebuild from scratch',
              detail:
                  'Every log is re-read and every total recomputed. Worth '
                  'doing if a figure looks wrong — nothing is lost, because '
                  'the cache only ever holds sums ${Brand.name} worked out '
                  'from files it does not own.',
              actionLabel: _rebuilding ? 'Rebuilding…' : 'Rebuild',
              onPressed: _rebuilding ? null : _rebuild,
            ),
          ],
        ),
      ],
    );
  }

  /// Names the folder and says whether it is actually there.
  ///
  /// "Codex: not installed" and "Codex: nothing used" look identical on the
  /// usage page unless somewhere says which, and this is that somewhere.
  String _detail(AiProvider provider, String subdirectory) {
    final home = Platform.environment['HOME'];
    final root = '~/${provider.defaultRoot}/$subdirectory';
    if (home == null) return 'Reads $root.';

    final exists =
        Directory('$home/${provider.defaultRoot}/$subdirectory').existsSync();
    return exists
        ? 'Reads $root.'
        : 'Reads $root, which is not on this Mac — nothing to read yet.';
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    try {
      final report = await locator<AiUsageService>().rebuild();
      if (!mounted) return;
      context.toastSuccess(
        '${report.filesScanned} session logs re-read',
        title: 'Usage rebuilt',
      );
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }
}
