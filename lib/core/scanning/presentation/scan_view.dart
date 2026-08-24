import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_bloc.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_event.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_state.dart';
import 'package:mac_uninstaller/core/scanning/presentation/removal_summary.dart';
import 'package:mac_uninstaller/core/scanning/presentation/result_tiles.dart';
import 'package:mac_uninstaller/core/scanning/presentation/result_tree_view.dart';
import 'package:mac_uninstaller/core/scanning/presentation/scan_hero.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/empty_state.dart';
import 'package:mac_uninstaller/core/widgets/module_scaffold.dart';
import 'package:mac_uninstaller/core/widgets/permission_banner.dart';

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
  });

  final String title;
  final String subtitle;

  final String? idleHeadline;
  final String? idleMessage;
  final String actionLabel;

  final VoidCallback? onGrantAccess;
  final List<Widget> headerActions;

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
          banner: state.permissionLimited && onGrantAccess != null
              ? PermissionBanner(onOpenSettings: onGrantAccess!)
              : null,
          actions: [
            if (focused != null)
              TextButton.icon(
                onPressed: () => bloc.add(const FocusCategory(null)),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('All categories'),
              ),
            if (state.phase == ScanPhase.results && focused == null)
              TextButton(
                onPressed: () => bloc.add(const StartScan()),
                child: const Text('Rescan'),
              ),
            ...headerActions,
          ],
          child: _body(context, state, bloc),
        );
      },
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
        return ScanHero(
          headline: 'Looking through your Mac…',
          message: state.totalBytes > 0
              ? 'Found so far — keep going, this gets more accurate as it runs.'
              : 'This takes a moment the first time.',
          bytes: state.totalBytes > 0 ? state.totalBytes : null,
          icon: bloc.module.icon,
          fraction: state.fraction,
          scanning: true,
          statusLine: state.currentPath == null
              ? null
              : shortenPath(state.currentPath!),
          actionLabel: 'Stop',
          onAction: () => bloc.add(const CancelScan()),
        );

      case ScanPhase.clean:
        return ScanHero.allClear(
          context,
          headline: 'Nothing to clean up',
          message: 'No reclaimable ${title.toLowerCase()} found. '
              'That is a good sign, not a failed scan.',
          onRescan: () => bloc.add(const StartScan()),
        );

      case ScanPhase.failed:
        return EmptyState(
          icon: Icons.error_outline_rounded,
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
          message: 'Moving ${state.selectedCount} item'
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
            child: focused == null
                ? ResultTiles(
                    roots: state.roots,
                    selection: state.selection,
                    onReview: (node) => bloc.add(FocusCategory(node.id)),
                    onToggle: (node, select) =>
                        bloc.add(ToggleNode(node, select: select)),
                  )
                : ResultTreeView(
                    node: focused,
                    selection: state.selection,
                    onToggle: (node, select) =>
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
        color: colors.surface,
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
          ElevatedButton(
            onPressed: nothingPicked
                ? null
                : () => bloc.add(const CleanSelected()),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
  }

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
