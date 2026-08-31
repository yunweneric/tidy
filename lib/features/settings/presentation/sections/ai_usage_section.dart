import 'dart:async';
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

  /// Whether Claude Code has a sign-in on this Mac. Null while the check runs.
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSignIn());
  }

  Future<void> _checkSignIn() async {
    final signedIn = await locator<AiUsageService>().hasClaudeSignIn();
    if (mounted) setState(() => _signedIn = signedIn);
  }

  /// Turning this on should cost one request, not a sweep of every session log
  /// on the disk — which is what a full refresh here used to do for the sake of
  /// two percentages that arrive over the network.
  void _setClaudeLimits(bool value) {
    setState(() => widget.settings.aiUsageClaudeLimits = value);
    if (!value) return;
    // Forced past the client's own cache: the user has just asked for this and
    // is watching for a bar to appear.
    unawaited(locator<AiUsageService>().refreshClaudePlan(force: true));
    unawaited(_checkSignIn());
  }

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
                  'text of your prompts is never read, none of it is sent '
                  'anywhere, and Full Disk Access is not needed to read any '
                  'of it. The one exception is Claude plan limits below, '
                  'which is off until you turn it on and says what it sends.',
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
          title: 'Plan limits',
          children: [
            SettingsSwitchRow(
              title: 'Claude plan limits',
              // The only thing on this page that leaves the Mac, described as
              // exactly that. The logs say what was spent and never what the
              // budget was, so without this the weekly row is a token count
              // with no bar — which is why the reason to turn it on is stated
              // as plainly as the cost of doing so.
              detail:
                  'Reads how much of your session and weekly allowance is '
                  'left, so those bars show real percentages instead of just '
                  'totals. ${Brand.name} sends your existing Claude Code '
                  'sign-in to Anthropic and asks for the two numbers back — '
                  'nothing about your prompts, your files or your Mac goes '
                  'with it. Off means the rest of this page still works, '
                  'entirely on this machine.'
                  // A switch that can only ever fail is worse than one that
                  // says why. Checked once when the section opens, because the
                  // answer is a keychain read and does not change while
                  // somebody reads a paragraph.
                  '${_signedIn == false ? "\n\nClaude Code is not signed in "
                          "on this Mac yet, so there is nothing to read until "
                          "you run `claude` and sign in." : ""}',
              value: settings.aiUsageClaudeLimits,
              onChanged: _setClaudeLimits,
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
