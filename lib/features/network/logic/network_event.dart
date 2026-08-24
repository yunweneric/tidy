import 'package:equatable/equatable.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/features/network/data/models/network_series.dart';

sealed class NetworkEvent extends Equatable {
  const NetworkEvent();

  @override
  List<Object?> get props => const [];
}

/// First load, and the Refresh action.
///
/// [refresh] bypasses the service's per-range cache. A plain load does not: the
/// year chart does not change between two clicks on the tab bar.
class LoadNetwork extends NetworkEvent {
  const LoadNetwork({this.refresh = false});

  final bool refresh;

  @override
  List<Object?> get props => [refresh];
}

/// The user picked a different span on the segmented control.
class NetworkRangeChanged extends NetworkEvent {
  const NetworkRangeChanged(this.range);

  final NetworkRange range;

  @override
  List<Object?> get props => [range];
}

/// One reading arrived from the native sampler.
class NetworkSampled extends NetworkEvent {
  const NetworkSampled(this.sample);

  final NetworkSample sample;

  @override
  List<Object?> get props => [sample];
}

/// The page came on screen or left it.
///
/// Branches live in an `IndexedStack` and stay mounted, so a page that is not
/// visible is still running — this is what closes the tap. Same gate
/// `PerformancePage` puts on its process monitor.
class NetworkVisibilityChanged extends NetworkEvent {
  const NetworkVisibilityChanged({required this.visible});

  final bool visible;

  @override
  List<Object?> get props => [visible];
}
