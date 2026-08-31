import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/scanning/logic/scan_bloc.dart';
import 'package:tidy/core/scanning/logic/scan_event.dart';
import 'package:tidy/core/scanning/logic/scan_state.dart';
import 'package:tidy/core/scanning/presentation/removal_summary.dart';
import 'package:tidy/core/scanning/presentation/result_tiles.dart';
import 'package:tidy/core/scanning/presentation/result_tree_view.dart';
import 'package:tidy/core/scanning/presentation/scan_hero.dart';
import 'package:tidy/core/scanning/presentation/scan_progress_panel.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/empty_state.dart';
import 'package:tidy/core/widgets/gradient_button.dart';
import 'package:tidy/core/widgets/module_scaffold.dart';
import 'package:tidy/core/widgets/permission_banner.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// A complete module page, driven entirely by a [ScanBloc].
///
/// Every scanner reuses this: pass a module and the whole
/// scan → tiles → review → clean → report loop comes for free. Building a new
/// module is writing a data source, not another screen.
class ScanView extends StatelessWidget {
  const ScanView({
    super.key,
    required this.title,
    required this.subtitle,
    this.idleHeadline,
    this.idleMessage,
    this.actionLabel = 'Scan',
    this.onGrantAccess,
    this.headerActions = const [],
    this.banner,
  });

  final String title;
  final String subtitle;

  final String? idleHeadline;
  final String? idleMessage;
  final String actionLabel;

  final VoidCallback? onGrantAccess;
  final List<Widget> headerActions;

  /// Shown under the header. Use it to say something the results cannot — what
  /// a composite scan does and does not cover, for instance.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScanBloc, ScanState>(
      builder: (context, state) {
        final bloc = context.read<ScanBloc>();
        final focused = state.focusedNode;

        return ModuleScaffold(
          title: focused?.title ?? title,
          subtitle: focused?.detail ?? subtitle,
          scrollable: false,
          banner: _banner(context, state),
          actions: [
            if (focused != null)
              TextButton.icon(
                onPressed: () => bloc.add(const FocusCategory(null)),
                icon: const Icon(AppIcons.back, size: 16),
                label: const Text('All categories'),
              ),
            if (state.phase == ScanPhase.results && focused == null) ...[
              // Back to the hero, discarding what was found. The bloc has
              // always had `ResetScan`; nothing reached it until Stop started
              // working, because before that the only way out of results was
              // to run another scan.
              TextButton(
                onPressed: () => bloc.add(const ResetScan()),
                child: const Text('Start over'),
              ),
              TextButton(
                onPressed: () => bloc.add(const StartScan()),
                child: const Text('Rescan'),
              ),
            ],
            ...headerActions,
          ],
          child: _body(context, state, bloc),
        );
      },
    );
  }

  /// Every banner can matter at once — a stopped scan that was also missing
  /// permissions and only covering half the modules — so they stack rather
  /// than compete.
  Widget? _banner(BuildContext context, ScanState state) {
    final shown = <Widget>[
      // First, because it changes what the numbers underneath mean: results
      // from a stopped sweep are a floor, not a total.
      //
      // Results only. The flag survives into `cleaning` and `finished`, where
      // the screen is about the removal rather than the scan and saying "you
      // stopped this" again would be answering a question nobody is asking.
      if (state.interrupted && state.phase == ScanPhase.results)
        const _InterruptedBanner(),
      if (state.permissionLimited && onGrantAccess != null)
        PermissionBanner(onOpenSettings: onGrantAccess!),
      if (banner != null) banner!,
    ];

    if (shown.isEmpty) return null;
    if (shown.length == 1) return shown.first;

    return Column(
      children: [
        for (final (index, widget) in shown.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          widget,
        ],
      ],
    );
  }

  Widget _body(BuildContext context, ScanState state, ScanBloc bloc) {
    switch (state.phase) {
      case ScanPhase.idle:
        return ScanHero(
          headline: idleHeadline ?? 'Ready when you are',
          message: idleMessage ?? bloc.module.id.description,
          icon: bloc.module.icon,
          actionLabel: actionLabel,
          onAction: () => bloc.add(const StartScan()),
        );

      case ScanPhase.scanning:
        // The panel below owns the rolling path now, so the hero does not also
        // carry a status line — two views of the same thing, one of them
        // changing too fast to read, is worse than one.
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: ScanHero(
                  headline: 'Looking through your Mac…',
                  message:
                      state.totalBytes > 0
                          ? 'Found so far — this gets more accurate as it runs.'
                          : 'This takes a moment the first time.',
                  bytes: state.totalBytes > 0 ? state.totalBytes : null,
                  icon: bloc.module.icon,
                  fraction: state.fraction,
                  scanning: true,
                  actionLabel: 'Stop',
                  onAction: () => bloc.add(const CancelScan()),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ScanProgressPanel(state: state),
          ],
        );

      case ScanPhase.clean:
        return ScanHero.allClear(
          context,
          headline: 'Nothing to clean up',
          message:
              'No reclaimable ${title.toLowerCase()} found. '
              'That is a good sign, not a failed scan.',
          onRescan: () => bloc.add(const StartScan()),
        );

      case ScanPhase.failed:
        return EmptyState(
          icon: AppIcons.error,
          accent: context.colors.risky,
          title: 'That scan could not finish',
          message: state.error,
          action: ElevatedButton(
            onPressed: () => bloc.add(const StartScan()),
            child: const Text('Try again'),
          ),
        );

      case ScanPhase.cleaning:
        return ScanHero(
          headline: 'Removing…',
          message:
              'Moving ${state.selectedCount} item'
              '${state.selectedCount == 1 ? '' : 's'} to the Trash.',
          icon: bloc.module.icon,
          scanning: true,
          actionLabel: 'Removing…',
          onAction: null,
        );

      case ScanPhase.finished:
        return RemovalSummary(
          outcome: state.outcome!,
          onDone: () => bloc.add(const StartScan()),
        );

      case ScanPhase.results:
        return _Results(state: state, bloc: bloc);
    }
  }
}

/// Says the results below are partial, because the user pressed Stop.
///
/// Its own banner rather than a line in the hero: the tiles underneath are
/// real findings the user can act on, so this has to qualify them without
/// hiding them. Neutral `info` rather than a warning colour — stopping a scan
/// is a thing the user chose, not a fault.
class _InterruptedBanner extends StatelessWidget {
  const _InterruptedBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      accent: colors.info,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.info.withValues(alpha: 0.14),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(AppIcons.info, size: 18, color: colors.info),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You stopped this scan', style: context.text.titleS),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'These are the results it had reached, so there is likely '
                  'more to find. Everything listed is still safe to clean.',
                  style: context.text.bodyM,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state, required this.bloc});

  final ScanState state;
  final ScanBloc bloc;

  @override
  Widget build(BuildContext context) {
    final focused = state.focusedNode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child:
                focused == null
                    ? ResultTiles(
                      roots: state.roots,
                      selection: state.selection,
                      onReview: (node) => bloc.add(FocusCategory(node.id)),
                      onToggle:
                          (node, select) =>
                              bloc.add(ToggleNode(node, select: select)),
                    )
                    : ResultTreeView(
                      node: focused,
                      selection: state.selection,
                      onToggle:
                          (node, select) =>
                              bloc.add(ToggleNode(node, select: select)),
                    ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _CleanBar(state: state, bloc: bloc),
      ],
    );
  }
}

/// The persistent action bar: what is selected, and the one button that acts.
class _CleanBar extends StatelessWidget {
  const _CleanBar({required this.state, required this.bloc});

  final ScanState state;
  final ScanBloc bloc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = state.selectedBytes;
    final nothingPicked = bytes == 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.surfaceGradient,
        ),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _allSelected,
            tristate: true,
            onChanged: (_) => bloc.add(ToggleAll(_allSelected != true)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              nothingPicked
                  ? 'Nothing selected'
                  : '${state.selectedCount} item'
                      '${state.selectedCount == 1 ? '' : 's'} selected',
              style: context.text.bodyM,
            ),
          ),
          Text(
            formatBytes(bytes),
            style: context.text.titleM.copyWith(
              color: nothingPicked ? colors.textMuted : colors.safe,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          GradientButton(
            label: 'Move to Trash',
            onPressed: nothingPicked ? null : () => _confirmClean(context),
          ),
        ],
      ),
    );
  }

  /// The last stop before anything moves.
  ///
  /// Every module reaches removal through this one button, so this is the only
  /// place a confirmation has to exist — and it has to exist. A scan that
  /// pre-ticks a few hundred files and then deletes them on a single click is
  /// asking the user to trust a list they were never made to read.
  ///
  /// The breakdown is by category rather than by file: nobody audits four
  /// hundred paths in a dialog, but "Caches · 182 items · 2.1 GB" is a claim
  /// somebody can actually disagree with.
  Future<void> _confirmClean(BuildContext context) async {
    final selected = state.selection.ids;
    final rows = <AlertDetail>[];
    var needsReview = false;

    for (final root in state.roots) {
      var count = 0;
      var bytes = 0;
      var worst = SafetyLevel.safe;

      for (final leaf in root.leaves) {
        if (!selected.contains(leaf.id)) continue;
        count++;
        bytes += leaf.sizeBytes;
        if (leaf.safety.index > worst.index) worst = leaf.safety;
      }
      if (count == 0) continue;

      final risky = worst != SafetyLevel.safe;
      needsReview |= risky;

      rows.add(
        AlertDetail(
          title: '${root.title} · ${_items(count)}',
          detail:
              risky
                  ? '${formatBytes(bytes)} — includes items worth a look '
                      'before they go'
                  : formatBytes(bytes),
          tone: risky ? FeedbackTone.warning : null,
          monospace: false,
        ),
      );
    }

    final confirmed = await TidyAlert.confirm(
      context,
      // Amber rather than red. This is reversible — everything lands in the
      // Trash — and a red dialog for a recoverable action spends alarm the app
      // will want later, when something genuinely cannot be undone.
      tone: FeedbackTone.warning,
      icon: AppIcons.trash,
      width: 520,
      title: 'Move ${_items(state.selectedCount)} to the Trash?',
      message:
          needsReview
              ? 'Some of this is worth a look first — it is flagged below. '
                  'Everything goes to the Trash, so you can put any of it back, '
                  'and your disk will not show ${formatBytes(state.selectedBytes)} '
                  'as free until you empty it.'
              : 'Everything goes to the Trash, so you can put any of it back. '
                  'Your disk will not show ${formatBytes(state.selectedBytes)} as '
                  'free until you empty it.',
      details: rows,
      confirmLabel: 'Move to Trash',
      destructive: true,
    );

    if (confirmed) bloc.add(const CleanSelected());
  }

  static String _items(int n) => n == 1 ? '1 item' : '$n items';

  bool? get _allSelected {
    var anySelected = false;
    var anyUnselected = false;
    for (final root in state.roots) {
      switch (state.selection.stateOf(root)) {
        case true:
          anySelected = true;
        case false:
          anyUnselected = true;
        case null:
          return null;
      }
    }
    if (anySelected && anyUnselected) return null;
    return anySelected;
  }
}
