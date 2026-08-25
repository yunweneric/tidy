import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tidy/features/ai_usage/presentation/ai_usage_page.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/fade_through.dart';
import 'package:tidy/features/apps/presentation/screens/applications_page.dart';
import 'package:tidy/features/cleanup/presentation/cleanup_page.dart';
import 'package:tidy/features/dashboard/presentation/dashboard_page.dart';
import 'package:tidy/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tidy/features/performance/presentation/performance_page.dart';
import 'package:tidy/features/clipboard/presentation/clipboard_page.dart';
import 'package:tidy/features/network/presentation/network_page.dart';
import 'package:tidy/features/recycle_bin/presentation/recycle_bin_page.dart';
import 'package:tidy/features/settings/domain/settings_section.dart';
import 'package:tidy/features/settings/presentation/settings_page.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/shell_scaffold.dart';
import 'package:tidy/features/smart_care/presentation/smart_care_page.dart';
import 'package:tidy/features/shell/presentation/widgets/coming_soon_page.dart';

/// Routes that live outside the shell.
abstract final class Routes {
  static const String onboarding = '/onboarding';
}

/// The app's router.
///
/// Every destination is a *branch* of a [StatefulShellRoute.indexedStack]
/// rather than a plain route. Plain routes would rebuild a module from scratch
/// each time you returned to it, which for this app means discarding an
/// in-flight scan — branches keep each module's navigator and state alive while
/// still giving real, addressable routes.
GoRouter buildRouter({required AppSettings settings}) {
  return GoRouter(
    initialLocation: AppDestination.initial.path,
    // Onboarding completion flips a value in settings; the router has to be
    // told, or the redirect below keeps sending the user back.
    refreshListenable: settings,
    redirect: (context, state) {
      final onboarding = state.matchedLocation == Routes.onboarding;

      if (!settings.hasCompletedOnboarding) {
        return onboarding ? null : Routes.onboarding;
      }
      // Finished, but still sitting on the intro: move along.
      return onboarding ? AppDestination.initial.path : null;
    },
    routes: [
      GoRoute(
        path: Routes.onboarding,
        pageBuilder:
            (context, state) => FadePage(
              key: state.pageKey,
              child: OnboardingScreen(
                settings: settings,
                fullDiskAccess: locator<FullDiskAccessService>(),
                // Completing onboarding updates settings, which notifies the
                // router's refreshListenable and the redirect takes it from there.
                onFinished: () => context.go(AppDestination.initial.path),
              ),
            ),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (context, state, navigationShell) =>
                ShellScaffold(navigationShell: navigationShell),
        // Declared in enum order so `AppDestination.branchIndex` is the branch
        // index. `_branch` asserts that rather than trusting it.
        branches: [
          for (final destination in AppDestination.values) _branch(destination),
        ],
      ),
    ],
  );
}

StatefulShellBranch _branch(AppDestination destination) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: destination.path,
        pageBuilder:
            (context, state) => FadePage(
              key: state.pageKey,
              name: destination.name,
              child: _pageFor(destination, state),
            ),
      ),
    ],
  );
}

/// [state] is threaded through for the one destination that takes a parameter:
/// Settings can be opened straight onto a section with `?section=updates`, so
/// the "update available" toast can land the user where the button is instead
/// of on the General tab.
Widget _pageFor(
  AppDestination destination,
  GoRouterState state,
) => switch (destination) {
  AppDestination.dashboard => const DashboardPage(),
  AppDestination.aiUsage => const AiUsagePage(),
  AppDestination.cleanup => const CleanupPage(),
  AppDestination.applications => const ApplicationsPage(),
  AppDestination.settings => SettingsPage(
    initialSection: SettingsSection.fromName(
      state.uri.queryParameters['section'],
    ),
  ),
  AppDestination.smartCare => const SmartCarePage(),
  AppDestination.protection => const ComingSoonPage(
    destination: AppDestination.protection,
    planned: [
      'Flag launch agents whose binary is missing, unsigned, or hiding in /tmp',
      'Check installed apps against a list of known adware and browser hijackers',
      'Audit browser extensions for search hijacking and over-broad permissions',
      'Clear browsing traces, recent items and saved Wi-Fi networks',
    ],
  ),
  AppDestination.performance => const PerformancePage(),
  AppDestination.recycleBin => const RecycleBinPage(),
  AppDestination.clipboard => const ClipboardPage(),
  AppDestination.network => const NetworkPage(),
  AppDestination.clutter => const ComingSoonPage(
    destination: AppDestination.clutter,
    planned: [
      'Find byte-identical duplicates, and flag APFS clones that free nothing',
      'Group near-identical photos — bursts, edits, re-saves',
      'Surface large files you have not opened in months',
      'Clear one-time installers out of Downloads',
    ],
  ),
  AppDestination.spaceLens => const ComingSoonPage(
    destination: AppDestination.spaceLens,
    planned: [
      'Map the disk as nested bubbles sized by what they actually occupy',
      'Drill into any folder and remove from the map',
      'Cache results so a rescan is incremental, not a full walk',
    ],
  ),
  AppDestination.allTools => const ComingSoonPage(
    destination: AppDestination.allTools,
    planned: [
      'Every scanner listed on its own, for when the modules get in the way',
    ],
  ),
  AppDestination.activity => const ComingSoonPage(
    destination: AppDestination.activity,
    planned: [
      'A record of what was removed, and when',
      'What is worth looking at next',
    ],
  ),
  AppDestination.assistant => const ComingSoonPage(
    destination: AppDestination.assistant,
    planned: [
      'A single health reading from free space, battery, updates and findings',
      'Specific suggestions rather than a score with no next step',
    ],
  ),
};
