import 'package:equatable/equatable.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';

sealed class ScanEvent extends Equatable {
  const ScanEvent();

  @override
  List<Object?> get props => const [];
}

/// Run the module. [root] narrows the scan to a folder or volume.
class StartScan extends ScanEvent {
  const StartScan({this.root});

  final String? root;

  @override
  List<Object?> get props => [root];
}

/// Abandon a scan in flight, keeping whatever has already come back.
class CancelScan extends ScanEvent {
  const CancelScan();
}

/// Back to the idle hero, discarding results.
class ResetScan extends ScanEvent {
  const ResetScan();
}

/// Select or clear a node and everything under it.
class ToggleNode extends ScanEvent {
  const ToggleNode(this.node, {this.select});

  final ScanNode node;

  /// Null flips the current state.
  final bool? select;

  @override
  List<Object?> get props => [node.id, select];
}

/// Select or clear every removable finding.
class ToggleAll extends ScanEvent {
  const ToggleAll(this.select);

  final bool select;

  @override
  List<Object?> get props => [select];
}

/// Drill into a result tile, or back out when [nodeId] is null.
///
/// Named `FocusCategory` rather than `FocusNode` because Flutter already
/// exports a `FocusNode` from material.
class FocusCategory extends ScanEvent {
  const FocusCategory(this.nodeId);

  final String? nodeId;

  @override
  List<Object?> get props => [nodeId];
}

/// Remove everything selected.
class CleanSelected extends ScanEvent {
  const CleanSelected({this.toTrash = true});

  /// Trash by default: an uninstall the user regrets should be recoverable.
  final bool toTrash;

  @override
  List<Object?> get props => [toTrash];
}
