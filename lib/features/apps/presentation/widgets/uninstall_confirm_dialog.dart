import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/features/apps/data/models/leftover_item.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';
import 'package:tidy/features/apps/data/models/removal_progress.dart';
import 'package:tidy/features/apps/data/services/leftover_scanner.dart';
import 'package:tidy/features/apps/logic/app_bloc.dart';
import 'package:tidy/features/apps/logic/app_event.dart';
import 'package:tidy/features/apps/logic/app_states.dart';
import 'package:tidy/features/apps/presentation/widgets/app_icon.dart';
import 'package:tidy/core/widgets/status_chip.dart';
import 'package:tidy/features/apps/utils/size_utils.dart';

/// What the user approved in the preview.
class UninstallPlan {
  const UninstallPlan({
    required this.apps,
    required this.paths,
    required this.totalBytes,
    required this.toTrash,
  });

  final List<MacApp> apps;
  final List<String> paths;
  final int totalBytes;
  final bool toTrash;
}

/// Safe-preview dialog: scans for everything an uninstall would remove, lets
/// the user deselect individual items, then runs it without going away.
///
/// It used to hand a plan back and close on the button press, which left the
/// window looking like nothing had happened for however long trashing a 12 GB
/// bundle takes — the only sign was a row quietly disappearing later. Now the
/// dialog dispatches the removal itself, stays up showing what is being
/// removed, and closes only once the work is finished. The result is then a
/// toast, because a finished uninstall is news rather than a decision.
class UninstallConfirmDialog extends StatefulWidget {
  const UninstallConfirmDialog({super.key, required this.apps, this.scanner});

  final List<MacApp> apps;
  final LeftoverScanner? scanner;

  /// Resolves once the dialog has gone — either cancelled, or the removal ran
  /// to completion. Callers use it to tidy up their own selection.
  static Future<UninstallPlan?> show(BuildContext context, List<MacApp> apps) {
    final removable = apps.where((app) => !app.isSystem).toList();
    if (removable.isEmpty) return Future.value(null);

    // The dialog goes on the root navigator, above the shell that provides
    // AppsBloc, so it cannot find the bloc for itself. Hand it down.
    final bloc = context.read<AppsBloc>();

    return showTidyDialog<UninstallPlan>(
      context,
      // A scan is running behind this dialog and the checkboxes are a real
      // decision — a stray click on the scrim should not throw either away.
      // Once removal starts there is nothing left to dismiss safely either.
      barrierDismissible: false,
      builder:
          (_) => BlocProvider<AppsBloc>.value(
            value: bloc,
            child: UninstallConfirmDialog(apps: removable),
          ),
    );
  }

  @override
  State<UninstallConfirmDialog> createState() => _UninstallConfirmDialogState();
}

class _UninstallConfirmDialogState extends State<UninstallConfirmDialog> {
  late final LeftoverScanner _scanner = widget.scanner ?? LeftoverScanner();

  /// Leftovers per app, in the order the apps were passed in.
  final Map<String, List<LeftoverItem>> _leftovers = {};
  final Set<String> _deselected = {};

  bool _scanning = true;
  bool _toTrash = true;

  /// Set once the user commits. From here the dialog is a progress view: the
  /// checkboxes stop mattering, the buttons go, and it closes itself when the
  /// bloc reports an outcome.
  UninstallPlan? _running;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _start() {
    final bloc = context.read<AppsBloc>();
    final plan = UninstallPlan(
      apps: widget.apps,
      paths: _selectedPaths,
      totalBytes: _selectedBytes,
      toTrash: _toTrash,
    );

    final event = UninstallAppsEvent(
      apps: plan.apps,
      paths: plan.paths,
      toTrash: plan.toTrash,
      expectedBytes: plan.totalBytes,
    );

    // The handler ignores the event unless the list is loaded, and the progress
    // view has no close button — entering it against a bloc that will never
    // report an outcome would strand the user in a dialog they cannot leave.
    // That should not happen from this screen, but "should not" is not a state
    // machine.
    if (bloc.state is! AppsLoaded) {
      bloc.add(event);
      Navigator.of(context).pop(plan);
      return;
    }

    setState(() => _running = plan);
    bloc.add(event);
  }

  Future<void> _scan() async {
    for (final app in widget.apps) {
      final items = await _scanner.scan(app);
      if (!mounted) return;
      setState(() => _leftovers[app.path] = items);
    }
    if (mounted) setState(() => _scanning = false);
  }

  bool _isSelected(String path) => !_deselected.contains(path);

  void _toggle(String path, bool selected) {
    setState(() {
      if (selected) {
        _deselected.remove(path);
      } else {
        _deselected.add(path);
      }
    });
  }

  /// Bundle paths are always included — an uninstall that leaves the app in
  /// place is not an uninstall.
  List<String> get _selectedPaths => [
    for (final app in widget.apps) app.path,
    for (final entry in _leftovers.entries)
      for (final item in entry.value)
        if (_isSelected(item.path)) item.path,
  ];

  int get _selectedBytes {
    var total = 0;
    for (final app in widget.apps) {
      total += app.sizeBytes;
    }
    for (final items in _leftovers.values) {
      for (final item in items) {
        if (_isSelected(item.path)) total += item.sizeBytes;
      }
    }
    return total;
  }

  int get _leftoverCount =>
      _leftovers.values.fold<int>(0, (sum, items) => sum + items.length);

  @override
  Widget build(BuildContext context) {
    // Only listens once removal is under way. The outcome is the signal that
    // the work is done — the page is listening for the same emission and turns
    // it into the toast, so this only has to get out of the way.
    return BlocListener<AppsBloc, AppsState>(
      listenWhen:
          (_, current) =>
              _running != null &&
              current is AppsLoaded &&
              current.lastOutcome != null,
      listener: (context, _) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(_running);
        }
      },
      child: _running == null ? _preview(context) : _progress(context),
    );
  }

  /// The removal in flight: the same dialog frame, no buttons, and a line
  /// naming what is going right now.
  Widget _progress(BuildContext context) {
    final plan = _running!;
    final trashing = plan.toTrash;

    return BlocBuilder<AppsBloc, AppsState>(
      builder: (context, state) {
        final progress = state is AppsLoaded ? state.removal : null;
        final fallback = RemovalProgress(
          completed: 0,
          total: plan.paths.length,
          movedToTrash: trashing,
        );
        final live = progress ?? fallback;

        return TidyDialog(
          tone: FeedbackTone.warning,
          icon: trashing ? AppIcons.trash : AppIcons.delete,
          width: 620,
          maxContentHeight: 200,
          // No close button and no actions: there is no safe way to stop
          // half-way through, so the dialog does not pretend to offer one.
          showClose: false,
          title:
              trashing
                  ? 'Moving to the Trash\u2026'
                  : 'Deleting permanently\u2026',
          subtitle:
              live.total <= 1
                  ? 'This can take a moment for a large application.'
                  : '${live.completed} of ${live.total} items done.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: AppRadii.xsAll,
                child: LinearProgressIndicator(
                  // A single path is one step, so a determinate bar would sit
                  // at zero and then jump. Sweep instead.
                  value: live.isIndeterminate ? null : live.fraction,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                live.currentLabel == null
                    ? 'Finishing up\u2026'
                    : 'Removing ${live.currentLabel}',
                style: context.text.bodyM,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                trashing
                    ? 'Everything goes to the Trash, so you can put it back. '
                        'Your disk will not show the space as free until the '
                        'Trash is emptied.'
                    : 'These are being removed for good. Nothing can be put '
                        'back afterwards.',
                style: context.text.bodyS,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _preview(BuildContext context) {
    final multiple = widget.apps.length > 1;

    return TidyDialog(
      // Amber, not red: nothing has been removed yet, and this is the screen
      // where the user is meant to look rather than flinch.
      tone: FeedbackTone.warning,
      icon: AppIcons.trash,
      width: 620,
      maxContentHeight: 380,
      title:
          multiple
              ? 'Uninstall ${widget.apps.length} applications?'
              : 'Uninstall \u201C${widget.apps.first.name}\u201D?',
      subtitle:
          _scanning
              ? 'Looking for the files these apps left around the system\u2026'
              : _leftoverCount == 0
              ? 'Nothing was left behind \u2014 only the app itself will go.'
              : 'Found ${_leftoverCount == 1 ? '1 leftover item' : '$_leftoverCount leftover items'}. '
                  'Uncheck anything you want to keep.',
      actionsLeading: Text.rich(
        TextSpan(
          text: _toTrash ? 'Moves ' : 'Removes ',
          style: context.text.bodyM,
          children: [
            TextSpan(
              text: formatBytes(_selectedBytes),
              style: context.text.titleM.copyWith(color: context.colors.safe),
            ),
          ],
        ),
      ),
      actions: [
        TidyDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TidyDialogAction(
          label: _toTrash ? 'Move to Trash' : 'Delete permanently',
          icon: _toTrash ? AppIcons.trash : AppIcons.delete,
          style: TidyActionStyle.destructive,
          onPressed: _scanning ? null : _start,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scanning) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: AppSpacing.lg),
          ],
          _buildItemList(),
          const SizedBox(height: AppSpacing.lg),
          _buildModeSelector(),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final app in widget.apps) ...[
          _PreviewRow(
            title: app.name,
            subtitle: app.path,
            sizeBytes: app.sizeBytes,
            selected: true,
            locked: true,
            category: LeftoverCategory.appBundle,
            // The bundle row shows the app's real icon rather than a category
            // glyph. It is the one row here the user already recognises, and
            // it anchors the rest of the list as belonging to that app.
            app: app,
            onChanged: (_) {},
          ),
          for (final item in _leftovers[app.path] ?? const <LeftoverItem>[])
            _PreviewRow(
              title: item.displayName,
              subtitle: item.location,
              sizeBytes: item.sizeBytes,
              selected: _isSelected(item.path),
              requiresAdmin: item.requiresAdmin,
              category: item.category,
              onChanged: (value) => _toggle(item.path, value),
              onReveal: () => SystemBridge.revealInFinder(item.path),
            ),
        ],
      ],
    );
  }

  Widget _buildModeSelector() {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            _toTrash ? AppIcons.restore : AppIcons.risky,
            size: 17,
            color: _toTrash ? colors.safe : colors.risky,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _toTrash
                  ? 'Everything moves to the Trash, so you can put it back. '
                      'Your disk will not show the space as free until the '
                      'Trash is emptied.'
                  : 'Removed immediately. Nothing can be recovered.',
              style: context.text.bodyS,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('Delete permanently', style: context.text.caption),
          Switch(
            value: !_toTrash,
            activeThumbColor: colors.risky,
            onChanged: (value) => setState(() => _toTrash = !value),
          ),
        ],
      ),
    );
  }
}

/// One line in the preview: what it is, where it lives, how big it is.
/// The category glyph, on the same 26pt footprint as the app icon so every row
/// in the list lines up whichever kind it is.
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category});

  final LeftoverCategory category;

  /// Mapped here rather than on [LeftoverCategory] itself: the enum lives in
  /// the data layer, and giving it an `IconData` would drag Flutter in with it.
  static IconData glyphFor(LeftoverCategory category) => switch (category) {
    LeftoverCategory.appBundle => AppIcons.applications,
    LeftoverCategory.applicationSupport => AppIcons.folder,
    LeftoverCategory.caches => AppIcons.cleanup,
    LeftoverCategory.preferences => AppIcons.settings,
    LeftoverCategory.logs => AppIcons.document,
    LeftoverCategory.containers => AppIcons.archive,
    LeftoverCategory.savedState => AppIcons.snapshot,
    LeftoverCategory.launchAgents => AppIcons.loginItems,
    LeftoverCategory.other => AppIcons.document,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.smAll,
      ),
      child: Icon(glyphFor(category), size: 14, color: colors.textSecondary),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.title,
    required this.subtitle,
    required this.sizeBytes,
    required this.selected,
    required this.category,
    required this.onChanged,
    this.app,
    this.locked = false,
    this.requiresAdmin = false,
    this.onReveal,
  });

  final String title;
  final String subtitle;
  final int sizeBytes;
  final bool selected;
  final LeftoverCategory category;
  final ValueChanged<bool> onChanged;

  /// Set only on the app-bundle row, which shows the real icon instead.
  final MacApp? app;
  final bool locked;
  final bool requiresAdmin;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Checkbox(
              value: selected,
              onChanged: locked ? null : (value) => onChanged(value ?? false),
            ),
          ),
          // A glyph per category, so the list is scannable by shape before it
          // is read. Twelve rows of identical text is how a preview stops being
          // looked at, and this preview is the whole safety story.
          if (app != null)
            AppIcon(app: app!, size: 26)
          else
            _CategoryIcon(category: category),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: context.text.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusChip(
                      label: category.label,
                      color: context.colors.textMuted,
                    ),
                    if (requiresAdmin) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Tooltip(
                        message:
                            'Needs administrator rights — this one may fail',
                        child: Icon(
                          AppIcons.locked,
                          size: 13,
                          color: context.colors.review,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: context.text.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatBytes(sizeBytes), style: context.text.bodyM),
          if (onReveal != null)
            IconButton(
              icon: const Icon(AppIcons.revealInFinder, size: 15),
              color: context.colors.textMuted,
              tooltip: 'Reveal in Finder',
              visualDensity: VisualDensity.compact,
              onPressed: onReveal,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}
