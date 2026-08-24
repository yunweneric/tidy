import 'package:equatable/equatable.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// First paint. Fires every read, each landing on its own.
class LoadDashboard extends DashboardEvent {
  const LoadDashboard();
}

/// The header's refresh: the same reads again, with the slow ones included.
class RefreshDashboard extends DashboardEvent {
  const RefreshDashboard();
}

/// The 2s pulse that keeps the vitals meters live while the page is on screen.
class DashboardTicked extends DashboardEvent {
  const DashboardTicked();
}

class TrendRangeChanged extends DashboardEvent {
  const TrendRangeChanged(this.range);

  final TrendRange range;

  @override
  List<Object?> get props => [range];
}

/// The Cleanup scan's current total, handed in by the page.
///
/// The Dashboard never starts a scan of its own. `ShellScaffold` already hoists
/// a `ScanBloc` for Cleanup above every branch so the sidebar can show the
/// reclaimable figure, and running a second sweep of `~/Library` just to fill in
/// a tile would double the disk work to show the same number twice.
class JunkObserved extends DashboardEvent {
  const JunkObserved(this.bytes);

  final int bytes;

  @override
  List<Object?> get props => [bytes];
}
