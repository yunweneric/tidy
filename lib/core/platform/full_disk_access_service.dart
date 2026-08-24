import 'package:flutter/foundation.dart';
import 'package:tidy/core/platform/system_bridge.dart';

/// Tracks whether the app holds Full Disk Access.
///
/// macOS offers no way to *ask* for FDA — the user has to add the app by hand in
/// System Settings — and the decision is cached per process, so a grant made
/// while we are running will not take effect until relaunch. Both facts have to
/// be surfaced in the UI or the permission flow looks broken.
class FullDiskAccessService extends ChangeNotifier {
  bool? _granted;
  bool _checking = false;

  /// Null until the first probe completes.
  bool? get granted => _granted;

  bool get isChecking => _checking;

  /// True once we know access is missing, so callers can avoid flashing a
  /// warning during the initial probe.
  bool get isDenied => _granted == false;

  Future<bool> refresh() async {
    if (_checking) return _granted ?? false;
    _checking = true;
    notifyListeners();

    _granted = await SystemBridge.hasFullDiskAccess();
    _checking = false;
    notifyListeners();
    return _granted!;
  }

  /// Sends the user to the right System Settings pane.
  Future<void> openSettings() => SystemBridge.openFullDiskAccessSettings();
}
