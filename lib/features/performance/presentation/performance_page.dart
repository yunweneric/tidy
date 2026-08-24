import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/performance/data/services/launch_items_service.dart';
import 'package:mac_uninstaller/features/performance/data/services/maintenance_service.dart';
import 'package:mac_uninstaller/features/performance/data/services/performance_bridge.dart';
import 'package:mac_uninstaller/features/performance/data/services/process_monitor_service.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_bloc.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_event.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_state.dart';
import 'package:mac_uninstaller/features/performance/logic/process_monitor_bloc.dart';
import 'package:mac_uninstaller/features/performance/presentation/widgets/widgets.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';
import 'package:mac_uninstaller/features/shell/presentation/active_destination.dart';

/// The four things Performance covers.
enum _Section {
  loginItems('Login Items'),
  backgroundItems('Background Items'),
  heavyConsumers('Heavy Consumers'),
  maintenance('Maintenance');

  const _Section(this.label);

  final String label;
}

/// The Performance module.
///
/// Not a [ScanView], deliberately. The scan contract is built around
/// find → select → remove, and none of these four are that: a login item is
/// turned off rather than deleted, a maintenance task is run, a process is
/// asked to quit. Wrapping any of it in a byte counter and a "Move to Trash"
/// button would be reusing the pipeline for the wrong verb, and the size of a
/// 2 KB plist is not a number anyone should be shown.
class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => PerformanceBloc(
            launchItems: locator<LaunchItemsService>(),
            maintenance: locator<MaintenanceService>(),
          )..add(const LoadPerformance()),
        ),
        BlocProvider(
          create: (_) => ProcessMonitorBloc(locator<ProcessMonitorService>()),
        ),
      ],
      child: const _PerformanceView(),
    );
  }
}

class _PerformanceView extends StatefulWidget {
  const _PerformanceView();

  @override
  State<_PerformanceView> createState() => _PerformanceViewState();
}

class _PerformanceViewState extends State<_PerformanceView>
    with WidgetsBindingObserver {
  _Section _section = _Section.loginItems;

  /// Whether the window itself is in the foreground. Sampling every process on
  /// the Mac while the app is hidden is a background battery cost with nothing
  /// on screen to justify it.
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    setState(() => _appResumed = resumed);
  }

  void _select(_Section section) => setState(() => _section = section);

  /// Starts or stops sampling to match [visible].
  ///
  /// Deferred to after the frame because an event cannot be added during build.
  /// The visibility itself is read *in* build, where depending on the shell's
  /// inherited destination is legal and actually registers the dependency — a
  /// read from inside the callback would be dropped on the next build.
  void _syncMonitor(bool visible) {
    if (visible == context.read<ProcessMonitorBloc>().state.running) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<ProcessMonitorBloc>();
      if (visible && !bloc.state.running) {
        bloc.add(const MonitorStarted());
      } else if (!visible && bloc.state.running) {
        bloc.add(const MonitorStopped());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncMonitor(
      _section == _Section.heavyConsumers &&
          _appResumed &&
          ActiveDestination.isVisible(context, AppDestination.performance),
    );

    return BlocBuilder<PerformanceBloc, PerformanceState>(
      builder: (context, state) {
        final bloc = context.read<PerformanceBloc>();

        return ModuleScaffold(
          title: AppDestination.performance.label,
          subtitle: AppDestination.performance.blurb,
          scrollable: false,
          actions: [
            TextButton.icon(
              onPressed: state.status == PerformanceStatus.loading
                  ? null
                  : () => bloc.add(const LoadPerformance(silent: true)),
              icon: const Icon(AppIcons.refresh, size: 15),
              label: const Text('Refresh'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs(
                  labels: [for (final section in _Section.values) section.label],
                  counts: _counts(state),
                  selectedIndex: _section.index,
                  onChanged: (index) => _select(_Section.values[index]),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (state.notice != null && _section != _Section.heavyConsumers) ...[
                NoticeBar(
                  notice: state.notice!,
                  onDismiss: () => bloc.add(const DismissNotice()),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Expanded(
                child: FadeThrough(
                  trigger: _section.index,
                  child: _body(context, state),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Counts appear only where they mean something. Heavy Consumers has none:
  /// every Mac runs a few hundred processes and the number says nothing, while
  /// a "0" there would read as "nothing is running".
  List<int?> _counts(PerformanceState state) {
    if (state.status != PerformanceStatus.ready) return const <int?>[];
    return [
      state.loginItems.length,
      state.backgroundItems.length,
      null,
      state.tasks.length,
    ];
  }

  Widget _body(BuildContext context, PerformanceState state) {
    if (state.status == PerformanceStatus.failed) {
      return EmptyState(
        icon: AppIcons.error,
        accent: context.colors.risky,
        title: 'That did not work',
        message: state.error,
        action: ElevatedButton(
          onPressed: () =>
              context.read<PerformanceBloc>().add(const LoadPerformance()),
          child: const Text('Try again'),
        ),
      );
    }

    // Heavy Consumers has its own bloc and its own loading state, so it does not
    // wait on the launchd read.
    if (_section == _Section.heavyConsumers) {
      return const HeavyConsumersSection();
    }

    if (state.status != PerformanceStatus.ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return switch (_section) {
      _Section.loginItems => LaunchItemsSection(
        state: state,
        items: state.loginItems,
        explanation:
            'These start themselves when you log in, or sit waiting in the '
            'background for something to ask for them. Turning one off is '
            'reversible and survives a restart.',
        emptyTitle: 'Nothing of yours starts at login',
        emptyMessage:
            'No app has set itself up to launch from your account. That is a '
            'good sign, not a failed check.',
        footer: const _LoginItemsFooter(),
      ),
      _Section.backgroundItems => LaunchItemsSection(
        state: state,
        items: state.backgroundItems,
        explanation:
            'These are set up for every account on this Mac, which is why they '
            'live somewhere only an administrator can change. Tidy lists and '
            'explains them; turning one off needs rights it does not have yet.',
        emptyTitle: 'Nothing runs machine-wide',
        emptyMessage:
            'No third-party software has installed anything that runs for '
            'every account on this Mac.',
      ),
      _Section.maintenance => MaintenanceSection(state: state),
      _Section.heavyConsumers => const HeavyConsumersSection(),
    };
  }
}

/// macOS will not let one app enumerate another's modern login items, so the
/// honest move is to say so and hand the user to the list that does show them.
///
/// The alternative — quietly listing only launch agents and calling it "Login
/// Items" — would leave someone hunting for the app they know starts at login
/// and concluding the feature is broken.
class _LoginItemsFooter extends StatelessWidget {
  const _LoginItemsFooter();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 17, color: colors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Some login items are not listed here', style: context.text.titleS),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Since macOS 13, apps register login items in a way no other '
                  'app is allowed to read. Tidy shows everything in your '
                  'LaunchAgents folder, which is most of it — for the rest, '
                  'System Settings has the full list.',
                  style: context.text.bodyM,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton(
            onPressed: PerformanceBridge.openLoginItemsSettings,
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
