import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';
import 'package:tidy/features/apps/data/models/removal_progress.dart';
import 'package:tidy/features/apps/data/services/junk_scanner.dart';

/// Result of a removal, surfaced once as a toast rather than replacing the
/// list with an error screen.
class RemovalOutcome {
  const RemovalOutcome({
    required this.removedCount,
    required this.freedBytes,
    required this.failures,
    this.movedToTrash = true,
  });

  final int removedCount;
  final int freedBytes;
  final List<RemovalFailure> failures;
  final bool movedToTrash;

  bool get hasFailures => failures.isNotEmpty;
}

abstract class AppsState {}

class AppsInitial extends AppsState {}

class AppsLoading extends AppsState {}

class AppsLoaded extends AppsState {
  AppsLoaded({
    required this.apps,
    this.disk = DiskUsage.empty,
    this.junk = JunkReport.empty,
    this.isRefreshing = false,
    this.isScanningJunk = false,
    this.removal,
    this.lastOutcome,
    this.scannedAt,
  });

  final List<MacApp> apps;
  final DiskUsage disk;
  final JunkReport junk;

  /// A background rescan is in flight while the current list stays on screen.
  final bool isRefreshing;

  /// The junk sweep is slower than the app scan and finishes separately.
  final bool isScanningJunk;

  /// Non-null only while a removal is running. The confirm dialog stays open
  /// and renders this, so the user watches the work instead of watching a
  /// dialog vanish and nothing visibly happen.
  final RemovalProgress? removal;

  /// Set for exactly one emission after a removal.
  final RemovalOutcome? lastOutcome;

  final DateTime? scannedAt;

  /// Apps the user is allowed to remove (everything outside /System).
  List<MacApp> get removableApps => apps.where((app) => !app.isSystem).toList();

  AppsLoaded copyWith({
    List<MacApp>? apps,
    DiskUsage? disk,
    JunkReport? junk,
    bool? isRefreshing,
    bool? isScanningJunk,
    RemovalProgress? removal,
    RemovalOutcome? lastOutcome,
    DateTime? scannedAt,
    bool clearOutcome = false,
    bool clearRemoval = false,
  }) {
    return AppsLoaded(
      apps: apps ?? this.apps,
      disk: disk ?? this.disk,
      junk: junk ?? this.junk,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isScanningJunk: isScanningJunk ?? this.isScanningJunk,
      removal: clearRemoval ? null : (removal ?? this.removal),
      lastOutcome: clearOutcome ? null : (lastOutcome ?? this.lastOutcome),
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}

class AppsError extends AppsState {
  AppsError(this.message);

  final String message;
}
