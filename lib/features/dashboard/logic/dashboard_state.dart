import 'package:equatable/equatable.dart';
import 'package:tidy/core/insights/dashboard_repository.dart';
import 'package:tidy/core/insights/health_insight.dart';
import 'package:tidy/core/insights/health_score.dart';
import 'package:tidy/core/models/clipboard_entry.dart';
import 'package:tidy/core/models/network_series.dart';
import 'package:tidy/core/models/trash_item.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/vitals/process_sample.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// How far back the trend charts look.
enum TrendRange {
  week('Week', Duration(days: 7), Granularity.day),
  month('Month', Duration(days: 30), Granularity.day),
  year('Year', Duration(days: 365), Granularity.day);

  const TrendRange(this.label, this.span, this.granularity);

  final String label;
  final Duration span;
  final Granularity granularity;

  DateTime get from => DateTime.now().subtract(span);

  NetworkRange get networkRange => switch (this) {
    TrendRange.week => NetworkRange.week,
    TrendRange.month => NetworkRange.month,
    TrendRange.year => NetworkRange.year,
  };
}

/// Each section of the page loads and fails on its own.
///
/// One page-wide flag would hold the whole Dashboard behind its slowest read —
/// disk usage answers in milliseconds while a Trash sweep across every mounted
/// volume takes seconds, and a single spinner over both means the fast nine
/// sections wait for the slow one for no reason the user can see.
enum SectionStatus { idle, loading, ready, failed }

class DashboardState extends Equatable {
  const DashboardState({
    this.vitalsStatus = SectionStatus.idle,
    this.storageStatus = SectionStatus.idle,
    this.trashStatus = SectionStatus.idle,
    this.clipsStatus = SectionStatus.idle,
    this.networkStatus = SectionStatus.idle,
    this.appsStatus = SectionStatus.idle,
    this.launchStatus = SectionStatus.idle,
    this.historyStatus = SectionStatus.idle,
    this.disk,
    this.vitals,
    this.processes,
    this.trash,
    this.clips,
    this.networkHeadline,
    this.networkSeries,
    this.apps = AppInventory.empty,
    this.launchItems = LaunchItemFacts.empty,
    this.junkBytes,
    this.fullDiskAccess,
    this.range = TrendRange.month,
    this.reclaimBuckets = const [],
    this.diskFreeBuckets = const [],
    this.recentOperations = const [],
    this.removedByCategory = const [],
    this.reclaimTotals = ReclaimTotals.empty,
    this.recordingSince,
    this.refreshing = false,
  });

  final SectionStatus vitalsStatus;
  final SectionStatus storageStatus;
  final SectionStatus trashStatus;
  final SectionStatus clipsStatus;
  final SectionStatus networkStatus;
  final SectionStatus appsStatus;
  final SectionStatus launchStatus;
  final SectionStatus historyStatus;

  final DiskUsage? disk;
  final SystemVitals? vitals;
  final ProcessSnapshot? processes;
  final TrashSnapshot? trash;
  final List<ClipboardEntry>? clips;
  final NetworkHeadline? networkHeadline;
  final NetworkSeries? networkSeries;
  final AppInventory apps;
  final LaunchItemFacts launchItems;

  /// Null means **no scan has run**, which is not the same as no junk. Rendered
  /// as "Not scanned yet", never as `0 B`: a cleaner that reports zero from a
  /// scan it never ran is telling the user something it does not know.
  final int? junkBytes;

  final bool? fullDiskAccess;

  final TrendRange range;
  final List<ReclaimBucket> reclaimBuckets;
  final List<MetricBucket> diskFreeBuckets;
  final List<OperationSummary> recentOperations;
  final List<CategoryTotal> removedByCategory;
  final ReclaimTotals reclaimTotals;

  /// When the store started keeping records. Charts before this point are blank
  /// because nothing was watching, and they say so rather than drawing zero.
  final DateTime? recordingSince;

  final bool refreshing;

  /// The Mac's health, from whatever has actually been measured.
  HealthScore get health => HealthScore.of(
    disk: disk,
    vitals: vitals,
    junkBytes: junkBytes,
    trashBytes: trash?.totalBytes,
    brokenLaunchItems:
        launchStatus == SectionStatus.ready ? launchItems.broken : null,
    unusedApps: apps.isKnown ? apps.unusedCount : null,
    fullDiskAccess: fullDiskAccess,
  );

  /// The one time-sensitive thing worth saying, resolved through the same
  /// ladder the menu bar uses so the two can never contradict each other.
  HealthInsight? get insight {
    final vitals = this.vitals;
    final disk = this.disk;
    if (vitals == null || disk == null) return null;

    final byCpu = [...?processes?.processes]
      ..sort((a, b) => (b.cpuPercent ?? 0).compareTo(a.cpuPercent ?? 0));
    final byMemory = [...?processes?.processes]
      ..sort((a, b) => b.memoryBytes.compareTo(a.memoryBytes));

    return HealthInsight.of(
      vitals: vitals,
      disk: disk,
      junkBytes: junkBytes ?? 0,
      trashBytes: trash?.totalBytes ?? 0,
      topCpu: byCpu.isEmpty ? null : byCpu.first,
      topMemory: byMemory.isEmpty ? null : byMemory.first,
    );
  }

  /// True once the store has anything worth plotting.
  bool get hasHistory =>
      reclaimBuckets.any((b) => !b.isEmpty) ||
      diskFreeBuckets.any((b) => b.recorded);

  int get pinnedClips =>
      clips?.where((clip) => clip.pinned).length ?? 0;

  int get clipboardBytes =>
      clips?.fold<int>(0, (sum, clip) => sum + clip.byteCount) ?? 0;

  /// Items in the Trash for more than a month — the ones it is safe to stop
  /// thinking about.
  int get staleTrashCount =>
      trash?.items.where((item) => (item.daysInBin ?? 0) >= 30).length ?? 0;

  DashboardState copyWith({
    SectionStatus? vitalsStatus,
    SectionStatus? storageStatus,
    SectionStatus? trashStatus,
    SectionStatus? clipsStatus,
    SectionStatus? networkStatus,
    SectionStatus? appsStatus,
    SectionStatus? launchStatus,
    SectionStatus? historyStatus,
    DiskUsage? disk,
    SystemVitals? vitals,
    ProcessSnapshot? processes,
    TrashSnapshot? trash,
    List<ClipboardEntry>? clips,
    NetworkHeadline? networkHeadline,
    NetworkSeries? networkSeries,
    AppInventory? apps,
    LaunchItemFacts? launchItems,
    int? junkBytes,
    bool? fullDiskAccess,
    TrendRange? range,
    List<ReclaimBucket>? reclaimBuckets,
    List<MetricBucket>? diskFreeBuckets,
    List<OperationSummary>? recentOperations,
    List<CategoryTotal>? removedByCategory,
    ReclaimTotals? reclaimTotals,
    DateTime? recordingSince,
    bool? refreshing,
  }) {
    return DashboardState(
      vitalsStatus: vitalsStatus ?? this.vitalsStatus,
      storageStatus: storageStatus ?? this.storageStatus,
      trashStatus: trashStatus ?? this.trashStatus,
      clipsStatus: clipsStatus ?? this.clipsStatus,
      networkStatus: networkStatus ?? this.networkStatus,
      appsStatus: appsStatus ?? this.appsStatus,
      launchStatus: launchStatus ?? this.launchStatus,
      historyStatus: historyStatus ?? this.historyStatus,
      disk: disk ?? this.disk,
      vitals: vitals ?? this.vitals,
      processes: processes ?? this.processes,
      trash: trash ?? this.trash,
      clips: clips ?? this.clips,
      networkHeadline: networkHeadline ?? this.networkHeadline,
      networkSeries: networkSeries ?? this.networkSeries,
      apps: apps ?? this.apps,
      launchItems: launchItems ?? this.launchItems,
      junkBytes: junkBytes ?? this.junkBytes,
      fullDiskAccess: fullDiskAccess ?? this.fullDiskAccess,
      range: range ?? this.range,
      reclaimBuckets: reclaimBuckets ?? this.reclaimBuckets,
      diskFreeBuckets: diskFreeBuckets ?? this.diskFreeBuckets,
      recentOperations: recentOperations ?? this.recentOperations,
      removedByCategory: removedByCategory ?? this.removedByCategory,
      reclaimTotals: reclaimTotals ?? this.reclaimTotals,
      recordingSince: recordingSince ?? this.recordingSince,
      refreshing: refreshing ?? this.refreshing,
    );
  }

  @override
  List<Object?> get props => [
    vitalsStatus,
    storageStatus,
    trashStatus,
    clipsStatus,
    networkStatus,
    appsStatus,
    launchStatus,
    historyStatus,
    disk,
    vitals,
    processes,
    trash,
    clips,
    networkHeadline,
    networkSeries,
    apps.count,
    apps.scannedAt,
    launchItems.total,
    launchItems.broken,
    junkBytes,
    fullDiskAccess,
    range,
    reclaimBuckets.length,
    diskFreeBuckets.length,
    recentOperations,
    removedByCategory,
    reclaimTotals,
    recordingSince,
    refreshing,
  ];
}
