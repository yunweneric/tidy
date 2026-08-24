import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/features/performance/data/models/maintenance_task.dart';
import 'package:tidy/features/performance/data/services/performance_bridge.dart';

/// The maintenance catalog, filtered down to what this Mac can actually do.
///
/// The native side answers only factual questions — is the tool installed, does
/// it need root — and the copy comes from [kMaintenanceCatalog]. A task the
/// native side does not report is not shown at all, which is how "Free up
/// memory" disappears on Apple silicon instead of sitting there as a placebo.
class MaintenanceService {
  MaintenanceService({TidyStore? store}) : _store = store;

  /// Where a task that reclaimed something is written down.
  final TidyStore? _store;

  Future<List<MaintenanceTask>> load() async {
    final raw = await PerformanceBridge.maintenanceTasks();

    final tasks = <MaintenanceTask>[];
    for (final entry in raw) {
      final id = entry['id'] as String?;
      final template = id == null ? null : kMaintenanceCatalog[id];
      // An id the native side offers but this build has no copy for would show
      // as an unlabelled button. Skip it rather than ship a mystery.
      if (template == null) continue;

      tasks.add(
        template.merge(
          available: entry['available'] as bool? ?? false,
          requiresAdmin: entry['requiresAdmin'] as bool? ?? false,
          unavailableReason: entry['unavailableReason'] as String?,
        ),
      );
    }

    // Runnable first: a list that opens with five greyed-out rows reads as a
    // broken feature rather than an honest one.
    tasks.sort((a, b) {
      final rank = _rank(a).compareTo(_rank(b));
      if (rank != 0) return rank;
      return a.title.compareTo(b.title);
    });
    return tasks;
  }

  Future<MaintenanceResult> run(MaintenanceTask task) async {
    final startedAt = DateTime.now();
    final raw = await PerformanceBridge.runMaintenanceTask(task.id);
    final result = MaintenanceResult(
      taskId: task.id,
      ok: raw['ok'] as bool? ?? false,
      message:
          raw['message'] as String? ??
          'That task finished without saying how it went.',
      freedBytes: (raw['freedBytes'] as num?)?.toInt() ?? 0,
    );

    _record(task, result, startedAt);
    return result;
  }

  /// Records a task that actually reclaimed something.
  ///
  /// Only the ones that report bytes, and only when they worked. Most
  /// maintenance tasks rebuild an index or reload a daemon and free nothing —
  /// a row saying "0 B reclaimed" would pad the history with events that never
  /// answer the question the history exists to answer.
  ///
  /// These bytes are genuinely gone rather than moved to the Trash, so they
  /// count as freed.
  void _record(
    MaintenanceTask task,
    MaintenanceResult result,
    DateTime startedAt,
  ) {
    final store = _store;
    if (store == null || !result.ok || result.freedBytes <= 0) return;

    final operationId = store.beginOperation(
      OperationDraft(
        kind: OperationKind.maintenance,
        label: task.title,
        module: task.id,
        startedAt: startedAt,
      ),
    );
    store.finishOperation(
      operationId,
      OperationOutcome(bytesDeleted: result.freedBytes, itemCount: 1),
    );
  }

  static int _rank(MaintenanceTask task) {
    if (task.runnable) return 0;
    if (task.requiresAdmin) return 1;
    return 2;
  }
}
