import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/space_lens/data/models/space_level.dart';
import 'package:tidy/features/space_lens/data/services/space_lens_service.dart';
import 'package:tidy/features/space_lens/presentation/widgets/space_bubble_map.dart';
import 'package:tidy/features/space_lens/presentation/widgets/space_entry_list.dart';
import 'package:tidy/features/space_lens/presentation/widgets/space_selection_card.dart';

/// Space Lens: where the disk actually went.
///
/// A plain page rather than a [ScanView], for the reason the Recycle Bin is
/// one: the scan contract's verb is find → select → remove, and nothing here is
/// *found*. Every file on the map is a file the user put there. What the map
/// does is answer "what is big", which is a question about the whole disk that
/// no list of findings can answer, and the removal it offers is a consequence
/// of looking rather than the point of it.
///
/// A `StatefulWidget` and not a bloc, which the other read-and-act pages use.
/// The state is one folder, one selection and a progress line — a bloc for that
/// would be three files of ceremony around a single `setState`, and
/// `docs/feature.md` §2 asks for one only when the state has outgrown that.
class SpaceLensPage extends StatefulWidget {
  const SpaceLensPage({super.key});

  @override
  State<SpaceLensPage> createState() => _SpaceLensPageState();
}

class _SpaceLensPageState extends State<SpaceLensPage> {
  final SpaceLensService _service = locator<SpaceLensService>();

  SpaceRoot _root = SpaceRoot.home;

  /// Where we are, and how we got here. A stack rather than a path string so
  /// the crumbs know which parts of the trail were actually walked — the trail
  /// back out of `~/Library/Caches` is `~` then `Library`, and only those two
  /// have been measured.
  List<String> _trail = const [];

  SpaceLevel? _level;

  /// The capped, grouped list the map draws, worked out once per folder.
  ///
  /// Held rather than called from `build`, because `SpaceLevel.visible` returns
  /// a fresh list every time and the map keys its packing off list identity —
  /// so calling it inline would re-pack the circles, and drop whatever the
  /// pointer was over, every time anything on the page changed.
  List<SpaceEntry> _visible = const [];

  SpaceProgress? _progress;
  SpaceEntry? _selected;
  bool _busy = false;

  String? get _path => _trail.isEmpty ? null : _trail.last;

  @override
  void initState() {
    super.initState();
    _openRoot(_root);
  }

  Future<void> _openRoot(SpaceRoot root) async {
    final path = root.path;
    setState(() {
      _root = root;
      _trail = path == null ? const [] : [path];
      _selected = null;
    });
    if (path != null) await _load(path);
  }

  /// Measures [path] and puts it on screen.
  ///
  /// The level is cleared first so a folder that takes ten seconds shows the
  /// gauge rather than the previous folder's bubbles with a spinner over them —
  /// a map that is still the last answer while it claims to be measuring is the
  /// one thing a map must not be.
  Future<void> _load(String path, {bool refresh = false}) async {
    final cached = _service.cached(path);
    if (cached != null && !refresh) {
      setState(() {
        _level = cached;
        _visible = cached.visible();
        _progress = null;
      });
      return;
    }

    setState(() {
      _level = null;
      _visible = const [];
      _progress = const SpaceProgress(measured: 0, total: 0);
    });

    final level = await _service.measure(
      path,
      refresh: refresh,
      onProgress: (progress) {
        if (mounted && _path == path) setState(() => _progress = progress);
      },
    );

    if (!mounted || _path != path) return;
    setState(() {
      _level = level;
      _visible = level.visible();
      _progress = null;
    });
  }

  void _open(SpaceEntry entry) {
    if (!entry.isDrillable) return;
    setState(() {
      _trail = [..._trail, entry.path];
      _selected = null;
    });
    _load(entry.path);
  }

  /// Back to [index] in the trail. Everything past it is dropped, because a
  /// crumb trail that keeps the branch you walked out of is a history, not a
  /// path.
  void _upTo(int index) {
    if (index >= _trail.length - 1) return;
    setState(() {
      _trail = _trail.sublist(0, index + 1);
      _selected = null;
    });
    _load(_trail.last);
  }

  Future<void> _rescan() async {
    final path = _path;
    if (path == null) return;
    setState(() => _selected = null);
    await _load(path, refresh: true);
  }

  Future<void> _trash(SpaceEntry entry) async {
    final confirmed = await TidyAlert.confirm(
      context,
      title: 'Move ${entry.name} to the Trash?',
      message:
          '${formatBytes(entry.sizeBytes)} of ${entry.isDirectory ? 'folder' : 'file'} '
          'goes to the Trash, where you can put it back. The space comes back '
          'when you empty it.',
      confirmLabel: 'Move to Trash',
      tone: FeedbackTone.danger,
      destructive: true,
      icon: AppIcons.delete,
      details: [AlertDetail(title: _short(entry.path), detail: 'Where it is')],
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final removed = await _service.moveToTrash(entry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (removed) _selected = null;
    });

    if (removed) {
      context.toastSuccess(
        '${entry.name} — ${formatBytes(entry.sizeBytes)}',
        title: 'Moved to Trash',
      );
      // The folder it came out of is now wrong by exactly its size, and so is
      // every total above it. The service has already forgotten them, so this
      // re-measures rather than doing arithmetic on a picture.
      final path = _path;
      if (path != null) await _load(path, refresh: true);
    } else {
      context.toastError(
        'macOS would not move ${entry.name}. It may be in use, or owned by '
        'another account.',
        title: 'Could not move it',
      );
    }
  }

  String _short(String path) => collapseHome(path, kHomeDir);

  @override
  Widget build(BuildContext context) {
    final level = _level;

    return ModuleScaffold(
      title: AppDestination.spaceLens.label,
      subtitle: AppDestination.spaceLens.blurb,
      scrollable: false,
      actions: [
        SegmentedTabs(
          labels: [for (final root in SpaceRoot.values) root.label],
          selectedIndex: SpaceRoot.values.indexOf(_root),
          onChanged:
              _progress != null
                  ? (_) {}
                  : (index) => _openRoot(SpaceRoot.values[index]),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlineActionButton(
          icon: AppIcons.refresh,
          label: 'Rescan',
          onPressed: _progress == null && !_busy ? _rescan : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Crumbs(trail: _trail, onTap: _upTo, short: _short),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _map(level)),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SpaceSelectionCard(
                        entry: _selected,
                        level: level,
                        busy: _busy,
                        onOpen: _open,
                        onReveal:
                            (entry) => SystemBridge.revealInFinder(entry.path),
                        onTrash: _trash,
                        short: _short,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Expanded(
                        child: SpaceEntryList(
                          level: level,
                          selectedPath: _selected?.path,
                          onSelect:
                              (entry) => setState(() => _selected = entry),
                          onOpen: _open,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(SpaceLevel? level) {
    final progress = _progress;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: switch ((progress, level)) {
        (final SpaceProgress progress, _) => _Measuring(progress: progress),
        (_, null) => EmptyState(
          icon: AppIcons.spaceLens,
          title: 'Nothing to map',
          message:
              _root.path == null
                  ? 'This Mac reports no home folder, which is the one place '
                      'Space Lens knows to start from.'
                  : 'Pick somewhere to look.',
        ),
        (_, final SpaceLevel level) when level.isEmpty => EmptyState(
          icon: AppIcons.spaceLens,
          title: 'This folder is empty',
          message:
              level.unreadable > 0
                  ? 'macOS would not let Tidy look inside it.'
                  : 'Nothing in here is using any space.',
        ),
        (_, final SpaceLevel level) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MapHeader(level: level, shown: _visible.length),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: SpaceBubbleMap(
                entries: _visible,
                selectedPath: _selected?.path,
                onSelect: (entry) => setState(() => _selected = entry),
                onOpen: _open,
              ),
            ),
          ],
        ),
      },
    );
  }
}

/// The trail back out, one crumb per folder actually walked into.
class _Crumbs extends StatelessWidget {
  const _Crumbs({
    required this.trail,
    required this.onTap,
    required this.short,
  });

  final List<String> trail;
  final ValueChanged<int> onTap;
  final String Function(String path) short;

  @override
  Widget build(BuildContext context) {
    final last = trail.length - 1;

    // Wrapped rather than scrolled sideways. A horizontal scroller that shows
    // the *end* of the trail has to be reversed, and a reversed one pushes a
    // short trail over to the right-hand edge of the page — so the fix for the
    // long case breaks every short one, which is nearly all of them.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.xxs,
      children: [
        for (var i = 0; i < trail.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text('/', style: context.text.bodyS),
            ),
          _Crumb(
            // The first crumb is the root and is named in full; the rest are
            // one folder each, because `~/Library/Application Support` spelled
            // out three times over is a trail you cannot read the end of.
            label: i == 0 ? short(trail[i]) : trail[i].split('/').last,
            current: i == last,
            onTap: i == last ? null : () => onTap(i),
          ),
        ],
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.current, this.onTap});

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style =
        current
            ? context.text.titleS.copyWith(color: colors.textPrimary)
            : context.text.bodyM.copyWith(color: colors.textSecondary);

    if (onTap == null) return Text(label, style: style);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(label, style: style),
      ),
    );
  }
}

/// What the folder adds up to, over the map of it.
class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.level, required this.shown});

  final SpaceLevel level;

  /// How many bubbles are actually on the map, which is not how many things are
  /// in the folder once the tail has been gathered into one.
  final int shown;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hidden = level.entries.length - shown;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IN THIS FOLDER',
                style: context.text.overline.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                formatBytes(level.totalBytes),
                style: context.text.displayL.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${level.entries.length} '
              '${level.entries.length == 1 ? 'item' : 'items'}'
              // Said out loud rather than left for the reader to notice that
              // forty circles are standing in for four hundred.
              '${hidden > 0 ? ' · $hidden gathered into one bubble' : ''}',
              style: context.text.bodyM,
            ),
            Text(
              'Click to select · double-click a folder to open it',
              style: context.text.caption,
            ),
          ],
        ),
      ],
    );
  }
}

/// The gauge while a folder is being walked.
class _Measuring extends StatelessWidget {
  const _Measuring({required this.progress});

  final SpaceProgress progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GaugeRing(
            // Indeterminate until the folder has been listed, because until
            // then the total is not a small number — it is not a number.
            progress: progress.total == 0 ? null : progress.fraction,
            size: 150,
            child: Text(
              progress.total == 0
                  ? '—'
                  : '${(progress.fraction * 100).round()}%',
              style: context.text.titleL,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Measuring what is inside',
            style: context.text.titleS.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            progress.currentName == null
                ? 'Every folder is walked to the bottom, so the figure is what '
                    'it occupies rather than what it says.'
                : '${progress.measured} of ${progress.total} · '
                    '${progress.currentName}',
            textAlign: TextAlign.center,
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}
