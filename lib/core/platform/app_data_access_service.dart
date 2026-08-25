import 'package:flutter/foundation.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/settings/app_settings.dart';

/// Tracks whether Tidy may read other apps' data.
///
/// Sonoma carved `kTCCServiceSystemPolicyAppData` out of Full Disk Access:
/// listing `~/Library/Containers` or reading inside another app's container
/// now needs its own grant, and macOS asks for it with "Tidy would like to
/// access data from other apps."
///
/// The awkward part, and the reason this is a service rather than a call:
/// **there is no way to check without asking.** The first access is the
/// request. So the state machine has three positions rather than two —
/// [granted] is null until the question has actually been put, and
/// [hasBeenAsked] is what separates "we do not know" from "we were refused".
///
/// The consequence for callers: never call [request] from anywhere except a
/// screen that has just explained what the permission is for. [refresh] is
/// safe anywhere, but tells you nothing until the question has been asked.
class AppDataAccessService extends ChangeNotifier {
  AppDataAccessService(this._settings);

  final AppSettings _settings;

  bool? _granted;
  bool _checking = false;

  /// Null until the question has been put and answered.
  bool? get granted => _granted;

  bool get isChecking => _checking;

  /// True once we know access is missing, so callers can avoid flashing a
  /// warning before anyone has been asked anything.
  bool get isDenied => _granted == false;

  /// Whether macOS has already shown its dialog to this user.
  bool get hasBeenAsked => _settings.hasRequestedAppDataAccess;

  /// Silent. Returns null — and probes nothing — until the question has been
  /// put, because the probe *is* the question.
  Future<bool?> refresh() async {
    if (!hasBeenAsked || _checking) return _granted;
    _checking = true;
    notifyListeners();

    _granted = await SystemBridge.hasAppDataAccess();
    _checking = false;
    notifyListeners();
    return _granted;
  }

  /// Puts macOS's dialog on screen, if it has not been shown before.
  ///
  /// Records that the question was asked before waiting for the answer: the
  /// dialog is modal and the user may quit the app while it is up, and a flag
  /// written only on success would ask again next launch.
  Future<bool> request() async {
    if (_checking) return _granted ?? false;
    _checking = true;
    notifyListeners();

    _settings.markAppDataAccessRequested();
    _granted = await SystemBridge.requestAppDataAccess();
    _checking = false;
    notifyListeners();
    return _granted!;
  }

  /// Sends the user to Privacy & Security → Files and Folders, which is where
  /// this one is listed. It is not under Full Disk Access, which is where
  /// everyone looks for it.
  Future<void> openSettings() => SystemBridge.openAppDataSettings();
}
