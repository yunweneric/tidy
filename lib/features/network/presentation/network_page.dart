import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/network/data/models/network_series.dart';
import 'package:tidy/features/network/data/models/network_units.dart';
import 'package:tidy/features/network/data/services/network_service.dart';
import 'package:tidy/features/network/logic/network_bloc.dart';
import 'package:tidy/features/network/presentation/widgets/widgets.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/active_destination.dart';

/// The Network module.
///
/// Not a [ScanView], deliberately, and for the reason `docs/feature.md` §1
/// gives: the scan contract's verb is find → select → remove, and nothing here
/// is any of those. There is nothing to select and nothing to delete — this
/// page answers "how much have I used, and when", which is a report rather than
/// a job of work.
///
/// The one thing every number on it has to keep honest: **Tidy records only
/// while Tidy is running.** A period with no bucket is a period the app was
/// quit for, and it is drawn as a gap and said out loud in the footer, never
/// rendered as a confident zero.
class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) =>
              NetworkBloc(locator<NetworkService>())..add(const LoadNetwork()),
      child: const _NetworkView(),
    );
  }
}

class _NetworkView extends StatefulWidget {
  const _NetworkView();

  @override
  State<_NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<_NetworkView> with WidgetsBindingObserver {
  /// Whether the window itself is in the foreground. A live chart nobody can
  /// see is a wake-up a second for nothing — the history keeps recording
  /// natively either way, so closing the tap costs no data.
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

  /// Opens or closes the live tap to match [visible].
  ///
  /// Deferred to after the frame because an event cannot be added during build.
  /// The visibility itself is read *in* build, where depending on the shell's
  /// inherited destination is legal and actually registers the dependency —
  /// the same shape as `PerformancePage._syncMonitor`.
  void _syncLive(bool visible) {
    if (visible == context.read<NetworkBloc>().state.live) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<NetworkBloc>();
      if (visible != bloc.state.live) {
        bloc.add(NetworkVisibilityChanged(visible: visible));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncLive(
      _appResumed && ActiveDestination.isVisible(context, AppDestination.network),
    );

    final units = locator<AppSettings>().networkUnits;

    return BlocBuilder<NetworkBloc, NetworkState>(
      builder: (context, state) {
        final bloc = context.read<NetworkBloc>();

        return ModuleScaffold(
          title: AppDestination.network.label,
          subtitle: AppDestination.network.blurb,
          scrollable: false,
          actions: [
            TextButton.icon(
              onPressed:
                  state.isLoading
                      ? null
                      : () => bloc.add(const LoadNetwork(refresh: true)),
              icon: const Icon(AppIcons.refresh, size: 15),
              label: const Text('Refresh'),
            ),
          ],
          child:
              state.hasNoHistory
                  ? _emptyState(context)
                  : _body(context, state, units),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: EmptyState(
      icon: AppIcons.network,
      title: 'Nothing recorded yet',
      message:
          'Tidy has just started watching your interfaces. Rates appear '
          'straight away; the daily and monthly charts fill in as you use '
          'your Mac.',
    ),
  );

  Widget _body(BuildContext context, NetworkState state, NetworkUnits units) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetworkNowCard(state: state, units: units),
        const SizedBox(height: AppSpacing.lg),
        NetworkStatTiles(
          state: state,
          units: units,
          onRange: (range) => context.read<NetworkBloc>().add(
            NetworkRangeChanged(range),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Expanded(child: _history(context, state)),
      ],
    );
  }

  Widget _history(BuildContext context, NetworkState state) {
    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SectionLabel(label: 'Usage over time', padding: EdgeInsets.zero),
              const Spacer(),
              NetworkLegend(
                downBytes: state.series.totalDownBytes,
                upBytes: state.series.totalUpBytes,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs(
              labels: [for (final range in _ranges) range.label],
              selectedIndex: _ranges.indexOf(state.range).clamp(0, _ranges.length - 1),
              onChanged:
                  (index) => context.read<NetworkBloc>().add(
                    NetworkRangeChanged(_ranges[index]),
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: FadeThrough(
              trigger: state.range.index,
              child:
                  state.series.isEmpty
                      ? Center(
                        child: Text(
                          state.isLoading
                              ? 'Reading the history…'
                              : 'Nothing recorded in this period.',
                          style: context.text.caption,
                        ),
                      )
                      : NetworkUsageChart(series: state.series),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          NetworkInterfaceTable(
            totals: state.series.byInterface,
            live: state.sample.interfaces,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(_coverage(state), style: context.text.caption),
        ],
      ),
    );
  }

  /// The honesty line.
  ///
  /// Every total above it is bounded by when this Mac started recording, and by
  /// how much of the period Tidy was actually running for. Saying so in one
  /// sentence is cheaper than a footnote on four tiles, and it is the difference
  /// between "you used nothing on Sunday" and "we were not there on Sunday".
  String _coverage(NetworkState state) {
    final startedAt = state.headline.startedAt;
    if (startedAt == null) return 'Recorded while Tidy is running.';

    final since = '${startedAt.day} ${_months[startedAt.month - 1]}';
    if (state.rangeOutrunsHistory) {
      return 'Recorded while Tidy is running — and only since $since, which is '
          'inside this period. Gaps in the chart are time Tidy was quit, not '
          'time you used nothing.';
    }
    return 'Recorded while Tidy is running, since $since. Gaps in the chart '
        'are time Tidy was quit, not time you used nothing.';
  }

  /// The hour range is deliberately absent from the tab bar: the card at the
  /// top of the page already shows the last five minutes live, and two
  /// short-window views a screen apart would be answering the same question
  /// twice.
  static const List<NetworkRange> _ranges = [
    NetworkRange.day,
    NetworkRange.week,
    NetworkRange.month,
    NetworkRange.sixMonths,
    NetworkRange.year,
    NetworkRange.all,
  ];

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}
