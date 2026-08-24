import 'package:equatable/equatable.dart';
import 'package:tidy/core/updates/update_release.dart';

enum UpdateStatus {
  /// Nothing has happened yet, or the last thing that did is no longer worth
  /// showing.
  idle,

  checking,

  /// Checked, and this is the newest there is.
  upToDate,

  /// A newer release exists and has not been downloaded.
  available,

  downloading,

  /// Downloaded; the native side is unpacking and checking it.
  verifying,

  /// Checked and staged. One button away from being installed.
  readyToInstall,

  /// The swap is under way. The app is about to quit.
  installing,

  failed,
}

class UpdateState extends Equatable {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.currentVersion = '',
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.lastCheckedAt,
    this.error,
    this.canRetryManually = false,
  });

  final UpdateStatus status;

  /// The release under consideration. Present in every state from [available]
  /// onwards, and also in [upToDate] — a check that finds the newest release is
  /// already installed still knows which release that was.
  final UpdateRelease? release;

  final String currentVersion;

  final int receivedBytes;
  final int totalBytes;

  final DateTime? lastCheckedAt;

  final String? error;

  /// Whether [error] is the kind a user can work around by installing the DMG
  /// by hand, which decides whether the failure comes with a way out.
  final bool canRetryManually;

  bool get isBusy => switch (status) {
    UpdateStatus.checking ||
    UpdateStatus.downloading ||
    UpdateStatus.verifying ||
    UpdateStatus.installing => true,
    _ => false,
  };

  /// True once there is something the user could act on.
  bool get hasUpdate => switch (status) {
    UpdateStatus.available ||
    UpdateStatus.downloading ||
    UpdateStatus.verifying ||
    UpdateStatus.readyToInstall ||
    UpdateStatus.installing => release != null,
    _ => false,
  };

  /// Null while the total is unknown, so the bar can stay indeterminate rather
  /// than sitting at zero.
  double? get progress {
    if (status != UpdateStatus.downloading) return null;
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateRelease? release,
    String? currentVersion,
    int? receivedBytes,
    int? totalBytes,
    DateTime? lastCheckedAt,
    String? error,
    bool? canRetryManually,
    bool clearError = false,
    bool clearRelease = false,
  }) => UpdateState(
    status: status ?? this.status,
    release: clearRelease ? null : (release ?? this.release),
    currentVersion: currentVersion ?? this.currentVersion,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    error: clearError ? null : (error ?? this.error),
    canRetryManually: canRetryManually ?? this.canRetryManually,
  );

  @override
  List<Object?> get props => [
    status,
    release,
    currentVersion,
    receivedBytes,
    totalBytes,
    lastCheckedAt,
    error,
    canRetryManually,
  ];
}
