import 'package:equatable/equatable.dart';

sealed class UpdateEvent extends Equatable {
  const UpdateEvent();

  @override
  List<Object?> get props => const [];
}

/// Ask GitHub whether there is a newer release.
///
/// [manual] means a person pressed a button: it ignores the "checked recently"
/// gate and the automatic-checks preference, and it makes the result visible
/// even when there is nothing to install. A background check that finds nothing
/// says nothing.
class CheckForUpdates extends UpdateEvent {
  const CheckForUpdates({this.manual = false});

  final bool manual;

  @override
  List<Object?> get props => [manual];
}

class DownloadUpdate extends UpdateEvent {
  const DownloadUpdate();
}

class CancelDownload extends UpdateEvent {
  const CancelDownload();
}

/// Swap the staged bundle in and relaunch. The app does not come back.
class InstallUpdate extends UpdateEvent {
  const InstallUpdate();
}

/// Stop offering this particular release.
class SkipThisVersion extends UpdateEvent {
  const SkipThisVersion();
}

/// The running bundle's version, read back from the native side at startup.
/// Emitted once by the bloc itself.
class UpdateBootstrapped extends UpdateEvent {
  const UpdateBootstrapped(this.currentVersion, this.lastCheckedAt);

  final String currentVersion;
  final DateTime? lastCheckedAt;

  @override
  List<Object?> get props => [currentVersion, lastCheckedAt];
}

/// Bytes have landed. Private to the bloc.
class UpdateProgressed extends UpdateEvent {
  const UpdateProgressed(this.received, this.total);

  final int received;
  final int total;

  @override
  List<Object?> get props => [received, total];
}
