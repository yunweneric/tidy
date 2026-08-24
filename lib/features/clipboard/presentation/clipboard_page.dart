import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/feedback/feedback.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/clipboard/data/models/clipboard_entry.dart';
import 'package:mac_uninstaller/features/clipboard/data/services/clipboard_service.dart';
import 'package:mac_uninstaller/features/clipboard/logic/clipboard_bloc.dart';
import 'package:mac_uninstaller/features/clipboard/presentation/widgets/widgets.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';

/// The clipboard history.
///
/// A plain page rather than a [ScanView], for the reason Performance and
/// Recycle Bin are: the scan contract's verb is find → select → remove, and
/// nothing here is found on disk, measured in reclaimable bytes, or removed to
/// free space. The verb is *get it back*.
///
/// Recording is native and runs whether or not this page — or any window — is
/// open. See `ClipboardBridge` for why the history does not live in Dart.
class ClipboardPage extends StatelessWidget {
  const ClipboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ClipboardBloc(locator<ClipboardService>())..add(const LoadClipboard()),
      child: const _ClipboardView(),
    );
  }
}

class _ClipboardView extends StatefulWidget {
  const _ClipboardView();

  @override
  State<_ClipboardView> createState() => _ClipboardViewState();
}

class _ClipboardViewState extends State<_ClipboardView> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppSettings get _settings => locator<AppSettings>();
  ClipboardService get _service => locator<ClipboardService>();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ClipboardBloc, ClipboardState>(
      listenWhen: (previous, current) =>
          current.notice != null && previous.notice != current.notice,
      listener: (context, state) {
        final notice = state.notice!;
        context.showToast(message: notice.message, tone: notice.tone);
        context.read<ClipboardBloc>().add(const DismissClipboardNotice());
      },
      builder: (context, state) {
        final recording = _settings.clipboardEnabled;

        return ModuleScaffold(
          title: AppDestination.clipboard.label,
          subtitle: AppDestination.clipboard.blurb,
          scrollable: false,
          actions: recording && !state.isEmpty
              ? [
                  AppSearchField(
                    width: 260,
                    hintText: 'Search what you have copied…',
                    controller: _search,
                    onChanged: (value) =>
                        context.read<ClipboardBloc>().add(SearchClipboard(value)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _confirmClear(context, state),
                    icon: const Icon(AppIcons.delete, size: 16),
                    label: const Text('Clear History'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.risky,
                      side: BorderSide(
                        color: context.colors.risky.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ]
              : const [],
          child: _body(context, state, recording: recording),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    ClipboardState state, {
    required bool recording,
  }) {
    if (!recording) return _optIn(context);

    if (state.status == ClipboardHistoryStatus.failed) {
      return EmptyState(
        icon: AppIcons.error,
        accent: context.colors.risky,
        title: 'That did not work',
        message: state.error,
        action: ElevatedButton(
          onPressed: () =>
              context.read<ClipboardBloc>().add(const LoadClipboard()),
          child: const Text('Try again'),
        ),
      );
    }

    if (state.status == ClipboardHistoryStatus.initial ||
        state.status == ClipboardHistoryStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.isEmpty) {
      return EmptyState(
        icon: AppIcons.clipboard,
        accent: context.colors.safe,
        title: 'Nothing copied yet',
        message:
            '${Brand.name} is watching the clipboard. Copy something and it '
            'will appear here — text, links, images and files all count.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipboardQuickSettings(
          settings: _settings,
          entryCount: state.entries.length,
          pinnedCount: state.entries.where((entry) => entry.pinned).length,
          onClear: () => _confirmClear(context, state),
          onOpenSettings: () => context.go(AppDestination.settings.path),
        ),
        const SizedBox(height: AppSpacing.lg),
        ClipboardFilterBar(
          state: state,
          onChanged: (kind) =>
              context.read<ClipboardBloc>().add(FilterClipboard(kind)),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(child: _table(context, state)),
      ],
    );
  }

  /// The first thing anyone sees, and deliberately a choice rather than a list.
  ///
  /// Recording the clipboard means writing everything copied to an unencrypted
  /// file — including the occasional password the guard does not catch. That is
  /// a fine thing to ask for and a poor thing to assume, so it is off until
  /// this button is pressed, and the sentence above it says plainly what it
  /// turns on.
  Widget _optIn(BuildContext context) {
    return EmptyState(
      icon: AppIcons.clipboard,
      accent: context.colors.review,
      title: 'Keep a history of what you copy',
      message:
          'With this on, ${Brand.name} records what you copy — text, links, '
          'images and files — so you can get any of it back later. It is kept '
          'on this Mac only, in an unencrypted file in your Application '
          'Support folder, and nothing is sent anywhere. Copies from password '
          'managers are never recorded, and anything that looks like a secret '
          'is hidden in the list.',
      action: GradientButton(
        label: 'Start Recording',
        icon: AppIcons.run,
        onPressed: () => setState(() => _settings.clipboardEnabled = true),
      ),
    );
  }

  Widget _table(BuildContext context, ClipboardState state) {
    final colors = context.colors;
    final lines = _lines(state);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.surfaceGradient,
        ),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DataTableHeader(
            columnLabels: [],
            trailingWidth: ClipboardTableLayout.actions,
            columns: [
              TableColumn('ITEM', flex: ClipboardTableLayout.contentFlex),
              TableColumn('FROM', width: ClipboardTableLayout.from),
              TableColumn(
                'USED',
                width: ClipboardTableLayout.copies,
                align: TextAlign.right,
              ),
              TableColumn(
                'COPIED',
                width: ClipboardTableLayout.when,
                align: TextAlign.right,
              ),
            ],
          ),
          Expanded(
            child: lines.isEmpty
                ? _nothingMatches(context, state)
                // Built lazily: a week of ordinary use is several hundred rows.
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      if (line is String) {
                        return _Heading(label: line);
                      }
                      return _row(
                        context,
                        line as ClipboardEntry,
                        state,
                        isLast: index == lines.length - 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ClipboardEntry entry,
    ClipboardState state, {
    required bool isLast,
  }) {
    final bloc = context.read<ClipboardBloc>();

    return ClipboardRow(
      key: ValueKey(entry.id),
      entry: entry,
      service: _service,
      revealed: state.isRevealed(entry),
      busy: state.isBusy(entry.id),
      isLast: isLast,
      onCopy: () => bloc.add(CopyEntry(entry)),
      onTogglePin: () => bloc.add(TogglePinEntry(entry)),
      onDelete: () => bloc.add(DeleteEntries([entry.id])),
      onReveal: () => entry.sensitive && !state.isRevealed(entry)
          ? bloc.add(RevealSensitiveEntry(entry.id))
          : bloc.add(RevealEntrySource(entry)),
      onOpen: () => ClipboardPreviewDialog.show(
        context,
        entry: entry,
        service: _service,
        onCopy: () => bloc.add(CopyEntry(entry)),
      ),
    );
  }

  Widget _nothingMatches(BuildContext context, ClipboardState state) {
    final query = state.query.trim();
    return EmptyState(
      icon: AppIcons.nothingFound,
      title: query.isEmpty
          ? 'Nothing of that kind yet'
          : 'Nothing matches “$query”',
      message: query.isEmpty
          ? 'There is plenty in the history — try the other tabs.'
          : 'Search looks at the preview and the app it came from. Hidden '
              'items match on their app only, never their contents.',
    );
  }

  /// Flattens the list into headings and rows so it can still be built lazily.
  ///
  /// Pinned first under their own heading, then the rest grouped by day. A day
  /// is a better handle on "the thing I copied this morning" than a timestamp.
  List<Object> _lines(ClipboardState state) {
    final lines = <Object>[];

    final pinned = state.pinned;
    if (pinned.isNotEmpty) {
      lines
        ..add('Pinned')
        ..addAll(pinned);
    }

    String? heading;
    for (final entry in state.unpinned) {
      final day = _dayLabel(entry.lastCopiedAt);
      if (day != heading) {
        heading = day;
        lines.add(day);
      }
      lines.add(entry);
    }
    return lines;
  }

  static String _dayLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final difference = today.difference(day).inDays;

    if (difference <= 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return 'Earlier this week';
    if (difference < 30) return 'Earlier this month';
    return 'Older';
  }

  // ─── Asking first ─────────────────────────────────────────────────────────

  Future<void> _confirmClear(BuildContext context, ClipboardState state) async {
    final pinned = state.entries.where((entry) => entry.pinned).length;
    final total = state.entries.length;
    final losing = total - pinned;

    final bloc = context.read<ClipboardBloc>();
    final confirmed = await TidyAlert.confirm(
      context,
      title: 'Clear the clipboard history?',
      message: pinned == 0
          ? 'This removes all $total item${total == 1 ? '' : 's'}, and the '
              'images and files stored with them. It cannot be undone.'
          : 'This removes $losing item${losing == 1 ? '' : 's'}. Your $pinned '
              'pinned item${pinned == 1 ? '' : 's'} will be kept. It cannot be '
              'undone.',
      confirmLabel: 'Clear History',
      tone: FeedbackTone.danger,
      icon: AppIcons.delete,
      destructive: true,
    );
    if (!confirmed) return;
    bloc.add(const ClearClipboard(keepPinned: true));
  }
}

/// A day, or the pinned group. Sits flush with the rows rather than floating,
/// so the table still reads as one surface.
class _Heading extends StatelessWidget {
  const _Heading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 32,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Text(label.toUpperCase(), style: context.text.overline),
    );
  }
}
