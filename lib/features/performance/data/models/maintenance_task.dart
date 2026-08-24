import 'package:equatable/equatable.dart';

/// One routine upkeep job.
///
/// The prose lives here rather than in Swift: copy is part of the design system
/// and gets reviewed with the rest of it. The native side answers only the
/// factual questions — is the tool present, does it need root.
class MaintenanceTask extends Equatable {
  const MaintenanceTask({
    required this.id,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.requiresAdmin,
    required this.available,
    this.unavailableReason,
  });

  final String id;
  final String title;

  /// What it does and what the user gets, in one sentence, without jargon.
  final String description;

  final String actionLabel;

  /// Needs root. Listed and explained; not runnable until the privileged
  /// helper exists.
  final bool requiresAdmin;

  /// The tool that performs it is present on this Mac.
  final bool available;

  final String? unavailableReason;

  bool get runnable => available && !requiresAdmin;

  MaintenanceTask merge({
    required bool available,
    required bool requiresAdmin,
    String? unavailableReason,
  }) {
    return MaintenanceTask(
      id: id,
      title: title,
      description: description,
      actionLabel: actionLabel,
      requiresAdmin: requiresAdmin,
      available: available,
      unavailableReason: unavailableReason,
    );
  }

  @override
  List<Object?> get props => [id, available, requiresAdmin, unavailableReason];
}

/// What running a task did.
class MaintenanceResult extends Equatable {
  const MaintenanceResult({
    required this.taskId,
    required this.ok,
    required this.message,
    this.freedBytes = 0,
  });

  final String taskId;
  final bool ok;
  final String message;

  /// Only Mail's index reports a figure. Everything else did work that has no
  /// number attached, and inventing one would be the kind of overclaiming this
  /// app is trying not to do.
  final int freedBytes;

  @override
  List<Object?> get props => [taskId, ok, message, freedBytes];
}

/// The copy for every task the native side can offer, keyed by its id.
///
/// A task the native side does not report is simply not shown — that is how
/// `freeRam` disappears on Apple Silicon and `periodicScripts` on releases that
/// dropped them.
const Map<String, MaintenanceTask> kMaintenanceCatalog = {
  'rebuildLaunchServices': MaintenanceTask(
    id: 'rebuildLaunchServices',
    title: 'Rebuild the “Open With” menu',
    description:
        'Right-clicking a file and seeing the same app listed four times means '
        'macOS’s record of installed apps has drifted. This rebuilds it.',
    actionLabel: 'Rebuild',
    requiresAdmin: false,
    available: true,
  ),
  'flushFontCaches': MaintenanceTask(
    id: 'flushFontCaches',
    title: 'Clear font caches',
    description:
        'Fixes garbled or missing text in apps after installing fonts. macOS '
        'rebuilds the caches as fonts are used again.',
    actionLabel: 'Clear',
    requiresAdmin: false,
    available: true,
  ),
  'speedUpMail': MaintenanceTask(
    id: 'speedUpMail',
    title: 'Speed up Mail',
    description:
        'Compacts the index Mail uses to search your messages. Your mail is not '
        'touched — only the index gets smaller and quicker. Quit Mail first.',
    actionLabel: 'Compact',
    requiresAdmin: false,
    available: true,
  ),
  'flushDns': MaintenanceTask(
    id: 'flushDns',
    title: 'Flush the DNS cache',
    description:
        'Makes your Mac look up website addresses again from scratch. Worth a '
        'try when a site loads everywhere except here.',
    actionLabel: 'Flush',
    requiresAdmin: true,
    available: true,
  ),
  'reindexSpotlight': MaintenanceTask(
    id: 'reindexSpotlight',
    title: 'Rebuild the Spotlight index',
    description:
        'Fixes Spotlight not finding files it should. Rebuilding takes a while '
        'and your Mac will feel busy until it finishes.',
    actionLabel: 'Rebuild',
    requiresAdmin: true,
    available: true,
  ),
  'thinSnapshots': MaintenanceTask(
    id: 'thinSnapshots',
    title: 'Thin Time Machine snapshots',
    description:
        'Local snapshots are the “purgeable” space macOS reports as free but '
        'will not hand over. This asks Time Machine to release some.',
    actionLabel: 'Thin',
    requiresAdmin: true,
    available: true,
  ),
  'periodicScripts': MaintenanceTask(
    id: 'periodicScripts',
    title: 'Run macOS’s own upkeep scripts',
    description:
        'The daily, weekly and monthly housekeeping macOS normally runs '
        'overnight. Useful if your Mac is usually asleep at that hour.',
    actionLabel: 'Run',
    requiresAdmin: true,
    available: true,
  ),
  'freeRam': MaintenanceTask(
    id: 'freeRam',
    title: 'Free up memory',
    description:
        'Forces macOS to release cached memory back to the pool. Only worth '
        'doing on Intel Macs — on Apple silicon it does nothing useful.',
    actionLabel: 'Free',
    requiresAdmin: true,
    available: true,
  ),
};
