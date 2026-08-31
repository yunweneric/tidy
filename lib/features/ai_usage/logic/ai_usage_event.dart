import 'package:equatable/equatable.dart';
import 'package:tidy/features/ai_usage/data/models/usage_window.dart';
import 'package:tidy/features/ai_usage/data/parsing/usage_scan.dart';

sealed class AiUsageEvent extends Equatable {
  const AiUsageEvent();

  @override
  List<Object?> get props => const [];
}

/// First load, and the Refresh action.
///
/// [refresh] re-reads the logs. It does not throw the cache away — files that
/// have not changed since the last sweep are still taken from it, which is the
/// difference between a refresh that takes a moment and one that takes half a
/// minute.
class LoadAiUsage extends AiUsageEvent {
  const LoadAiUsage({this.refresh = false});

  final bool refresh;

  @override
  List<Object?> get props => [refresh];
}

/// Throws the cache away and reads every log from scratch.
class RebuildAiUsage extends AiUsageEvent {
  const RebuildAiUsage();
}

/// Overview or Analytics.
class AiUsageTabChanged extends AiUsageEvent {
  const AiUsageTabChanged(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}

class AiUsageRangeChanged extends AiUsageEvent {
  const AiUsageRangeChanged(this.range);

  final UsageRange range;

  @override
  List<Object?> get props => [range];
}

/// A minute has passed. Re-derives the page's views against a fresh clock.
///
/// Reads nothing: the windows count down to a reset and the plan reading ages
/// out, and both of those move on their own. Without this the countdown froze
/// at whatever it said when the last sweep finished.
class AiUsageTicked extends AiUsageEvent {
  const AiUsageTicked();
}

/// Fetch Claude's plan limits alone, leaving the logs alone.
///
/// [force] skips the client's own cache, for the case where the user has just
/// switched the setting on and is waiting to see a bar appear.
class ClaudePlanRefreshed extends AiUsageEvent {
  const ClaudePlanRefreshed({this.force = false});

  final bool force;

  @override
  List<Object?> get props => [force];
}

/// The sweep moved on. Drives the determinate progress line, which is the
/// difference between a cold read looking like work and looking like a hang.
class AiUsageProgressed extends AiUsageEvent {
  const AiUsageProgressed(this.progress);

  final UsageScanProgress progress;

  @override
  List<Object?> get props => [progress.filesDone, progress.filesTotal];
}
