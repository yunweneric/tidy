import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_service.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_bloc.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/widgets.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/active_destination.dart';

/// The AI Usage module.
///
/// A plain page rather than a [ScanView], for the reason `docs/feature.md` §1
/// gives: the scan contract's verb is find → select → remove, and there is
/// nothing here to select and nothing to delete. It reads logs the AI CLIs
/// write for their own purposes and reports what they add up to.
///
/// Three things every number on it has to keep honest, all of them said on
/// screen rather than in a tooltip:
///
/// 1. **The money was not spent.** Claude Code and Codex run on flat-fee
///    subscriptions. Every figure here is what the same tokens would cost
///    through the API, which is a useful number and not a bill.
/// 2. **Some of it cannot be priced at all.** OpenAI meters Codex in credits,
///    not dollars per token, so Codex tokens are counted and its cost is left
///    blank. A plausible guess would be worse than the blank.
/// 3. **A missing day is usually a real zero, and sometimes is not.** The CLIs
///    write these logs whether or not Tidy is running, so an empty day inside
///    the covered span means the tool went unused. Before the earliest log
///    there is nothing to say, and that draws as a gap.
class AiUsagePage extends StatelessWidget {
  const AiUsagePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create:
        (_) => AiUsageBloc(locator<AiUsageService>())..add(const LoadAiUsage()),
    child: const _AiUsageView(),
  );
}

class _AiUsageView extends StatefulWidget {
  const _AiUsageView();

  @override
  State<_AiUsageView> createState() => _AiUsageViewState();
}

class _AiUsageViewState extends State<_AiUsageView> {
  bool _wasVisible = false;

  /// Re-reads when the page comes back on screen.
  ///
  /// Branches live in an `IndexedStack` and never unmount, so without this the
  /// page would still be showing whatever was true the first time it was
  /// opened. Cheap to do: the sweep takes every unchanged file from the cache,
  /// so coming back mid-session reads only the sessions being worked in.
  void _syncVisibility(bool visible) {
    if (visible == _wasVisible) return;
    _wasVisible = visible;
    if (!visible) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AiUsageBloc>().add(const LoadAiUsage(refresh: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncVisibility(
      ActiveDestination.isVisible(context, AppDestination.aiUsage),
    );

    return BlocBuilder<AiUsageBloc, AiUsageState>(
      builder: (context, state) {
        final bloc = context.read<AiUsageBloc>();

        return ModuleScaffold(
          title: AppDestination.aiUsage.label,
          subtitle: AppDestination.aiUsage.blurb,
          scrollable: false,
          actions: [
            TextButton.icon(
              onPressed:
                  state.isLoading
                      ? null
                      : () => bloc.add(const LoadAiUsage(refresh: true)),
              icon: const Icon(AppIcons.refresh, size: 15),
              label: const Text('Refresh'),
            ),
          ],
          child: _body(context, state, bloc),
        );
      },
    );
  }

  Widget _body(BuildContext context, AiUsageState state, AiUsageBloc bloc) {
    if (state.isLoading && state.report.isEmpty) {
      return _Reading(state: state);
    }
    if (state.hasNothing) return _empty(context, state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedTabs(
          labels: const ['Overview', 'Analytics'],
          selectedIndex: state.tab.index,
          onChanged: (index) => bloc.add(AiUsageTabChanged(index)),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: FadeThrough(
            trigger: state.tab,
            // A scroll view per tab, each with its own key. One shared view
            // carries its offset across the switch, and the two tabs are
            // nothing like the same height — landing halfway down a table you
            // did not ask for reads as the app losing your place.
            child: SingleChildScrollView(
              key: PageStorageKey(state.tab),
              child: switch (state.tab) {
                AiUsageTab.overview => _Overview(state: state, bloc: bloc),
                AiUsageTab.analytics => _Analytics(state: state),
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, AiUsageState state) => Center(
    child: EmptyState(
      icon: AppIcons.aiUsage,
      title: 'No AI session logs found',
      message:
          state.report.missingRoots.isEmpty
              ? 'Tidy looked in ~/.claude and ~/.codex and found nothing to read. '
                  'That is not a failed scan — it just means neither CLI has run '
                  'on this Mac, or their logs have been cleared.'
              : '${state.report.missingRoots.join(" and ")} '
                  '${state.report.missingRoots.length == 1 ? "is" : "are"} not '
                  'installed here. Turn providers on or off in Settings → AI '
                  'Usage.',
    ),
  );
}

/// The cold-read state.
///
/// Determinate on purpose. A first sweep reads every session log on the Mac,
/// which can be a gigabyte and a half — an indeterminate spinner over that
/// reads as a hang, and the file count is the one honest thing to show.
class _Reading extends StatelessWidget {
  const _Reading({required this.state});

  final AiUsageState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GaugeRing(
              progress: state.filesTotal == 0 ? null : state.progress,
              size: 120,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Reading session logs', style: text.titleM),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.filesTotal == 0
                  ? 'Looking for them first.'
                  : '${state.filesDone} of ${state.filesTotal} files',
              style: text.bodyM.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.state, required this.bloc});

  final AiUsageState state;
  final AiUsageBloc bloc;

  @override
  Widget build(BuildContext context) {
    final report = state.report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UsageHeadlineCard(state: state),
        const SizedBox(height: AppSpacing.md),
        UsageStatTiles(
          state: state,
          onRange: (range) => bloc.add(AiUsageRangeChanged(range)),
        ),
        const SizedBox(height: AppSpacing.md),
        UsageTrendChart(
          state: state,
          onRange: (range) => bloc.add(AiUsageRangeChanged(range)),
        ),
        const SizedBox(height: AppSpacing.md),
        BreakdownTable(
          title: 'By model',
          nameHeading: 'Model',
          rows: [
            for (final entry in report.modelBreakdown)
              BreakdownRow(
                name: entry.key,
                tokens: entry.value,
                priced: ModelPricing.of(entry.key) != null,
              ),
          ],
          footer: _PricingNote(report: report),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

class _Analytics extends StatelessWidget {
  const _Analytics({required this.state});

  final AiUsageState state;

  @override
  Widget build(BuildContext context) {
    final report = state.report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ActivityHeatmap(report: report),
        const SizedBox(height: AppSpacing.md),
        CacheEfficiencyCard(report: report),
        const SizedBox(height: AppSpacing.md),
        BreakdownTable(
          title: 'By project',
          nameHeading: 'Working directory',
          rows: [
            for (final entry in report.projectBreakdown.take(15))
              BreakdownRow(
                name: collapseHome(entry.key, kHomeDir),
                tokens: entry.value,
                mono: true,
                // A project mixes models, so its cost comes from the day
                // maths rather than from a rate on the row's own name.
                priced: false,
              ),
          ],
          footer: const UsageNote(
            'Grouped by the folder each session ran in. Cost is left off here '
            'because a folder is not a model — the same project can run on '
            'four of them at four rates, and per-model money is in the table '
            'on Overview.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Coverage(state: state),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

class _PricingNote extends StatelessWidget {
  const _PricingNote({required this.report});

  final AiUsageReport report;

  @override
  Widget build(BuildContext context) {
    final unpriced = report.unpricedModels;
    final lines = <String>[
      'Costs are what this usage would cost at published API rates. On a '
          'subscription you paid a flat monthly fee, not this.',
      'Rates last checked $kPricesCheckedOn.',
    ];
    if (unpriced.isNotEmpty) {
      lines.add(
        '${unpriced.length} ${unpriced.length == 1 ? "model has" : "models have"} '
        'no published per-token rate (${unpriced.join(", ")}). Their tokens '
        'are counted; their cost is not.',
      );
    }
    return UsageNote(lines.join(' '), icon: AppIcons.info);
  }
}

/// What was read, what was not, and how long ago.
class _Coverage extends StatelessWidget {
  const _Coverage({required this.state});

  final AiUsageState state;

  @override
  Widget build(BuildContext context) {
    final report = state.report;
    final colors = context.colors;

    final found = report.providersFound.map((p) => p.label).toList()..sort();
    final lines = <String>[
      found.isEmpty
          ? 'Nothing read.'
          : 'Read ${report.filesScanned} session logs from ${found.join(" and ")}.',
      if (report.coversFrom case final from?)
        'Covering ${_date(from)} onwards — ${formatCount(report.tokens.total)} '
            'tokens in total.',
      for (final missing in report.missingRoots)
        '$missing is not installed on this Mac, so none of its usage is here.',
    ];

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(
            label: 'What this covers',
            padding: EdgeInsets.zero,
          ),
          for (final line in lines) UsageNote(line),
          if (report.unreadableFiles > 0)
            UsageNote(
              '${report.unreadableFiles} '
              '${report.unreadableFiles == 1 ? "file" : "files"} could not be '
              'read, so the totals above are short by whatever was in '
              '${report.unreadableFiles == 1 ? "it" : "them"}.',
              icon: AppIcons.risky,
              tone: colors.review,
            ),
        ],
      ),
    );
  }
}

const List<String> _months = [
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

String _date(DateTime at) => '${at.day} ${_months[at.month - 1]} ${at.year}';
