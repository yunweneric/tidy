import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The result of a native action that either worked or has something to say.
@immutable
class ActionOutcome {
  const ActionOutcome({required this.ok, this.message});

  static const ActionOutcome success = ActionOutcome(ok: true);

  factory ActionOutcome.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const ActionOutcome(ok: false, message: 'No answer from macOS.');
    }
    return ActionOutcome(
      ok: map['ok'] as bool? ?? false,
      message: map['message'] as String?,
    );
  }

  final bool ok;

  /// A sentence to show the user. Null when it simply worked.
  final String? message;
}

/// Thin wrapper over `macos/Runner/PerformanceChannel.swift`.
///
/// Separate from [SystemBridge] because the two speak about different things:
/// that one is files, this one is launchd, libproc and Apple's own tools. Every
/// call degrades to an empty result rather than throwing — a Performance page
/// that crashes because `launchctl` moved is worse than one missing a section.
class PerformanceBridge {
  PerformanceBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.macuninstaller/performance',
  );

  // ─── Launch items ─────────────────────────────────────────────────────────

  /// Every launchd job in the user's and the machine's agent/daemon folders.
  /// Apple's own under `/System` are deliberately not included.
  static Future<List<Map<String, dynamic>>> launchItems() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('launchItems');
      if (result == null) return const [];
      return result.map((raw) => (raw as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      debugPrint('launchItems failed: $e');
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

  // ─── Processes ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> processSamples() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('processSamples');
      return result ?? const {};
    } catch (e) {
      debugPrint('processSamples failed: $e');
      return const {};
    }
  }

  /// Drops the sampling history so the next tick starts a fresh baseline.
  /// Called when the monitor starts, otherwise the first reading is a delta
  /// against whenever the page was last open.
  static Future<void> resetProcessSamples() async {
    try {
      await _channel.invokeMethod<void>('resetProcessSamples');
    } catch (e) {
      debugPrint('resetProcessSamples failed: $e');
    }
  }

  static Future<ActionOutcome> terminateProcess({
    required int pid,
    bool force = false,
  }) => _act('terminateProcess', {'pid': pid, 'force': force});

  // ─── Maintenance ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> maintenanceTasks() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('maintenanceTasks');
      if (result == null) return const [];
      return result.map((raw) => (raw as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      debugPrint('maintenanceTasks failed: $e');
      return const [];
    }
  }

  static Future<Map<String, dynamic>> runMaintenanceTask(String id) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'runMaintenanceTask',
        {'id': id},
      );
      return result ?? const {'ok': false, 'message': 'No answer from macOS.'};
    } catch (e) {
      debugPrint('runMaintenanceTask failed: $e');
      return {'ok': false, 'message': 'That task could not be run. $e'};
    }
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  /// Opens System Settings → General → Login Items & Extensions.
  ///
  /// There is no public API to enumerate the modern `SMAppService` login items
  /// another app registered, so for those the honest move is to hand the user
  /// straight to the list macOS does show.
  static Future<void> openLoginItemsSettings() async {
    try {
      await _channel.invokeMethod<void>('openLoginItemsSettings');
    } catch (e) {
      debugPrint('openLoginItemsSettings failed: $e');
    }
  }

  static Future<ActionOutcome> _act(String method, Map<String, dynamic> arguments) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method, arguments);
      return ActionOutcome.fromMap(result);
    } catch (e) {
      final message = e is PlatformException ? (e.message ?? e.code) : e.toString();
      return ActionOutcome(ok: false, message: message);
    }
  }
}
