import 'package:flutter/services.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/platform/action_outcome.dart';

/// The launchd half of `macos/Runner/PerformanceChannel.swift`.
///
/// Split out of `PerformanceBridge` when Protection needed to read the same
/// items: `docs/feature.md` §2 forbids one feature importing another's
/// services, and the alternative — a second plist reader and a second elevated
/// remove — would put the one routine in this app that deletes root-owned files
/// in two places.
///
/// **The channel name is deliberately still the performance one.** Nothing
/// native moved, and a renamed key fails silently across the boundary rather
/// than at compile time (`docs/feature.md` §4a).
class LaunchItemsBridge {
  LaunchItemsBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/performance',
  );

  /// Every launchd job in the user's and the machine's agent/daemon folders.
  /// Apple's own under `/System` are deliberately not included.
  static Future<List<Map<String, dynamic>>> launchItems() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('launchItems');
      if (result == null) return const [];
      return result.map((raw) => (raw as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      AppLog.performance.failed('read the launch items', e);
      return const [];
    }
  }

  static Future<ActionOutcome> setLaunchItemEnabled({
    required String label,
    required String scope,
    required String path,
    required bool enabled,
  }) => _act('setLaunchItemEnabled', {
    'label': label,
    'scope': scope,
    'path': path,
    'enabled': enabled,
  });

  /// Stops a job before its plist is removed, so launchd is not left holding a
  /// definition that has gone.
  static Future<ActionOutcome> unloadLaunchItem({
    required String label,
    required String scope,
  }) => _act('unloadLaunchItem', {'label': label, 'scope': scope});

  /// Removes a machine-wide item behind macOS's own authorization prompt.
  ///
  /// The prompt is shown by the system, not by us, and cancelling it is a
  /// normal outcome that leaves everything where it was.
  static Future<ActionOutcome> removeLaunchItemElevated({
    required String path,
    required String label,
    required String kind,
  }) => _act('removeLaunchItemElevated', {
    'path': path,
    'label': label,
    'kind': kind,
  });

  static Future<ActionOutcome> _act(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      return ActionOutcome.fromMap(result);
    } catch (e) {
      final message =
          e is PlatformException ? (e.message ?? e.code) : e.toString();
      return ActionOutcome(ok: false, message: message);
    }
  }
}
