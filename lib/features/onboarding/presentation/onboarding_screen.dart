import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/platform/app_data_access_service.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/status_chip.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/onboarding/presentation/widgets/onboarding_frame.dart';

/// First-run introduction, ending in the permission requests.
///
/// Two permissions, asked differently, because macOS treats them differently:
///
/// - **Full Disk Access** cannot be requested at all. The user has to add the
///   app by hand in System Settings, so the step deep-links there, says what
///   the permission unlocks, and warns that a relaunch is needed before the
///   grant takes effect.
/// - **Other apps' data** (`kTCCServiceSystemPolicyAppData`, new in Sonoma) can
///   only be requested by *using* it — the first access is the prompt. So it
///   gets a button that triggers macOS's own dialog on purpose.
///
/// The second one is the reason this screen exists in its current shape. That
/// dialog used to appear at launch, unbidden, because the Full Disk Access
/// probe listed `~/Library/Containers` as a fallback. An app that sends people
/// to a privacy pane with no explanation is indistinguishable from malware;
/// one that throws "would like to access data from other apps" at them before
/// it has introduced itself is worse.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.settings,
    required this.fullDiskAccess,
    required this.appDataAccess,
    required this.onFinished,
  });

  final AppSettings settings;
  final FullDiskAccessService fullDiskAccess;
  final AppDataAccessService appDataAccess;
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const int _stepCount = 4;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.fullDiskAccess.refresh();
    // Silent unless the question has already been put — see
    // `AppDataAccessService.refresh`, which is a no-op until then. Onboarding
    // must not be the thing that springs the dialog.
    widget.appDataAccess.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user goes to System Settings and comes back; re-probe rather than
    // making them find the Re-check button.
    if (state == AppLifecycleState.resumed) {
      widget.fullDiskAccess.refresh();
      widget.appDataAccess.refresh();
    }
  }

  void _next() {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() {
    widget.settings.completeOnboarding();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      0 => _welcome(),
      1 => _howItWorks(),
      2 => _clipboard(),
      _ => _permissions(),
    };
  }

  OnboardingFrame _welcome() {
    return OnboardingFrame(
      stepIndex: 0,
      stepCount: _stepCount,
      title: 'Welcome to ${Brand.name}',
      subtitle:
          'A cleaner and file manager for macOS. It finds space you can get '
          'back, removes apps properly, and shows you what is actually filling '
          'your disk.',
      primaryLabel: 'Get started',
      onPrimary: _next,
      secondaryLabel: 'Skip intro',
      onSecondary: _finish,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Feature(
            icon: AppIcons.cleanup,
            title: 'Reclaim space, safely',
            detail:
                'Caches, logs and window-restore data your apps rebuild on '
                'their own. None of it is your work.',
          ),
          _Feature(
            icon: AppIcons.applications,
            title: 'Uninstall completely',
            detail:
                'Dragging an app to the Trash leaves preferences, caches and '
                'launch agents behind. ${Brand.name} finds them.',
          ),
          _Feature(
            icon: AppIcons.spaceLens,
            title: 'See where the space went',
            detail:
                'A map of your disk, so “storage almost full” becomes a list '
                'of things you can act on.',
          ),
        ],
      ),
    );
  }

  OnboardingFrame _howItWorks() {
    final colors = context.colors;

    return OnboardingFrame(
      stepIndex: 1,
      stepCount: _stepCount,
      title: 'Nothing goes without your say-so',
      subtitle:
          'Cleaners have a bad reputation for a reason. Here is how this one '
          'behaves.',
      primaryLabel: 'Continue',
      onPrimary: _next,
      onBack: () => setState(() => _step--),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Feature(
            icon: AppIcons.safe,
            iconColor: colors.safe,
            title: 'You review before anything is removed',
            detail:
                'Every scan ends in a list you can uncheck. Only items that are '
                'genuinely rebuilt automatically are ticked for you.',
          ),
          _Feature(
            icon: AppIcons.restore,
            iconColor: colors.accent,
            title: 'Removal means the Trash',
            detail:
                'So you can put it back. Your disk will not report the space as '
                'free until you empty the Trash — ${Brand.name} says so rather '
                'than claiming credit early.',
          ),
          _Feature(
            icon: AppIcons.locked,
            iconColor: colors.review,
            title: 'Some things are off limits',
            detail:
                'System files, your photo and music libraries, browser logins '
                'and app data are never touched, even when they are large.',
          ),
        ],
      ),
    );
  }

  /// The clipboard opt-in.
  ///
  /// Its own step, and a choice rather than a default, because it is the one
  /// thing in the app that keeps a record of what the user does. Two buttons of
  /// equal weight: nothing here is the recommended answer.
  OnboardingFrame _clipboard() {
    final colors = context.colors;

    return OnboardingFrame(
      stepIndex: 2,
      stepCount: _stepCount,
      title: 'Keep a history of what you copy',
      subtitle:
          'macOS has room for one thing on the clipboard, so copying anything '
          'loses what was there before. ${Brand.name} can remember it all — if '
          'you want it to.',
      primaryLabel: 'Turn it on',
      onPrimary: () {
        widget.settings.clipboardEnabled = true;
        _next();
      },
      secondaryLabel: 'Not now',
      onSecondary: () {
        widget.settings.clipboardEnabled = false;
        _next();
      },
      onBack: () => setState(() => _step--),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Feature(
            icon: AppIcons.clipboard,
            iconColor: colors.accent,
            title: 'Text, links, images and files',
            detail:
                'Everything you copy is listed newest first, with the app it '
                'came from. Click any of it to put it back on the clipboard.',
          ),
          _Feature(
            icon: AppIcons.locked,
            iconColor: colors.review,
            title: 'Passwords are never recorded',
            detail:
                'Copies from password managers are skipped outright. Anything '
                'that looks like a key or a card number is hidden in the list, '
                'and can be dropped instead of stored.',
          ),
          _Feature(
            icon: AppIcons.storage,
            iconColor: colors.safe,
            title: 'On this Mac, and only for as long as you say',
            detail:
                'Kept in an unencrypted file in your Application Support '
                'folder — nothing is sent anywhere. It clears itself after a '
                'week by default, and you can change that or switch the whole '
                'thing off in Settings.',
          ),
        ],
      ),
    );
  }

  OnboardingFrame _permissions() {
    return OnboardingFrame(
      stepIndex: 3,
      stepCount: _stepCount,
      title: 'Two permissions to grant',
      subtitle:
          'macOS keeps the rest of your disk behind these. Without them '
          '${Brand.name} can only see part of it — and will say so rather than '
          'quietly under-reporting what it finds.',
      primaryLabel: 'Finish',
      onPrimary: _finish,
      onBack: () => setState(() => _step--),
      // Merged rather than nested: the two cards sit in one column and either
      // service can change while the other is mid-probe.
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.fullDiskAccess,
          widget.appDataAccess,
        ]),
        builder:
            (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FullDiskCard(service: widget.fullDiskAccess),
                const SizedBox(height: AppSpacing.lg),
                _AppDataCard(service: widget.appDataAccess),
              ],
            ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.detail,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = iconColor ?? colors.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleS),
                const SizedBox(height: AppSpacing.xxs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(detail, style: context.text.bodyM),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shell both permission cards are built from.
///
/// One shape, so the two grants read as two of the same thing rather than as
/// two features that happen to be adjacent — the tinted glyph, the live status
/// chip, one paragraph of what it unlocks, and the actions underneath.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.granted,
    required this.checking,
    required this.body,
    this.actions = const [],
  });

  final String title;

  /// Null means the question has not been answered yet — which for the app-data
  /// grant is a real state, not a loading one.
  final bool? granted;

  final bool checking;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = granted == true ? colors.safe : colors.review;

    return TidyCard(
      accent: tone,
      selected: true,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.13),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(
              granted == true ? AppIcons.unlocked : AppIcons.locked,
              size: 21,
              color: tone,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: context.text.titleM),
                    const SizedBox(width: AppSpacing.md),
                    if (checking)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (granted == true)
                      StatusChip(
                        label: 'Granted',
                        color: colors.safe,
                        icon: AppIcons.safe,
                      )
                    else if (granted == false)
                      StatusChip(
                        label: 'Not granted',
                        color: colors.review,
                        icon: AppIcons.locked,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(body, style: context.text.bodyM),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        actions[i],
                      ],
                    ],
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

/// Full Disk Access: cannot be requested, only explained and deep-linked to.
class _FullDiskCard extends StatelessWidget {
  const _FullDiskCard({required this.service});

  final FullDiskAccessService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final granted = service.granted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PermissionCard(
          title: 'Full Disk Access',
          granted: granted,
          checking: service.isChecking,
          body:
              granted == true
                  ? 'You are all set. Scans can see your whole disk.'
                  : 'Unlocks Mail and Messages attachments, iOS backups and Safari '
                      'data — a large share of what is worth reclaiming.',
          actions:
              granted == true
                  ? const []
                  : [
                    ElevatedButton(
                      onPressed: service.openSettings,
                      child: const Text('Open System Settings'),
                    ),
                    TextButton(
                      onPressed: service.isChecking ? null : service.refresh,
                      child: const Text('Re-check'),
                    ),
                  ],
        ),
        if (granted != true) ...[
          const SizedBox(height: AppSpacing.lg),
          _Steps(),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(AppIcons.info, size: 15, color: colors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You can skip both of these and grant them later from '
                  'Settings. ${Brand.name} works without them — it will just '
                  'find less.',
                  style: context.text.bodyS,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Other apps' data: the one permission Tidy can actually ask for.
///
/// macOS shows its own dialog the first time the containers directory is read,
/// so the button here does not "open settings" — it does the read, and the
/// system takes it from there. After that the answer is cached and the button
/// becomes a deep link, because a second read will not re-prompt.
class _AppDataCard extends StatelessWidget {
  const _AppDataCard({required this.service});

  final AppDataAccessService service;

  @override
  Widget build(BuildContext context) {
    final granted = service.granted;
    final asked = service.hasBeenAsked;

    return _PermissionCard(
      title: 'Other apps’ data',
      granted: granted,
      checking: service.isChecking,
      body: switch (granted) {
        true =>
          'You are all set. Leftovers inside other apps’ containers are '
              'visible to a scan.',
        false =>
          'Without it, ${Brand.name} cannot see inside other apps’ '
              'containers — where a good deal of cache and leftover data '
              'lives. It will report what it could not read rather than '
              'counting it as zero.',
        null =>
          'macOS asks for this one itself, the first time ${Brand.name} looks '
              'inside another app’s container. Getting it over with here means '
              'the dialog arrives now, with an explanation, instead of halfway '
              'through your first scan.',
      },
      actions: [
        if (!asked)
          ElevatedButton(
            onPressed: service.isChecking ? null : service.request,
            child: const Text('Ask macOS now'),
          )
        else if (granted != true) ...[
          ElevatedButton(
            onPressed: service.openSettings,
            child: const Text('Open System Settings'),
          ),
          TextButton(
            onPressed: service.isChecking ? null : service.refresh,
            child: const Text('Re-check'),
          ),
        ],
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  static const List<String> _instructions = [
    'Open System Settings → Privacy & Security → Full Disk Access.',
    'Click + and choose ${Brand.name} from Applications.',
    'Quit and reopen ${Brand.name} — macOS caches the decision for the life of '
        'the process, so it does not take effect until then.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _instructions.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == _instructions.length - 1 ? 0 : AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accentMuted,
                      borderRadius: AppRadii.pillAll,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: context.text.caption.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(_instructions[i], style: context.text.bodyM),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
