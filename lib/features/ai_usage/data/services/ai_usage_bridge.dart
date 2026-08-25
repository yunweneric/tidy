import 'package:flutter/services.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';

/// Thin wrapper over `macos/Runner/AiUsageChannel.swift`.
///
/// Carries the menu bar's slice of the usage report in one direction and hands
/// it back in the other. Two callers, one store:
///
/// - The **main engine** publishes, because it is the only one with an
///   `AiUsageService` — the popover runs `includeUi: false` and has neither the
///   service nor the `AppSettings` its constructor needs, and must never run
///   the sweep, which is 16 seconds over 1.5 GB cold.
/// - The **popover engine** reads, so its AI panel draws the same figures the
///   bar is drawing rather than a second opinion.
///
/// The native side keeps the last summary on disk as well as in memory, so the
/// readout is right for the first second of a launch instead of blank — the
/// same reason `NetworkStore` reads `settings.json` itself.
///
/// Every call degrades to null or a no-op rather than throwing. A menu bar
/// without a number is a smaller problem than a panel that will not open.
class AiUsageBridge {
  AiUsageBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/ai_usage',
  );

  /// Hands the native side a fresh summary.
  static Future<void> publish(AiUsageSummary summary) async {
    try {
      await _channel.invokeMethod<void>('publish', summary.toJson());
    } on PlatformException catch (e) {
      AppLog.aiUsage.failed('publish the usage summary', e);
    } on MissingPluginException catch (e) {
      AppLog.aiUsage.failed('reach the usage channel', e);
    }
  }

  /// The last published summary, or null when nothing has been published and
  /// nothing was left on disk by a previous run.
  ///
  /// Null is a real answer and the panel renders it as such. A zeroed summary
  /// would claim a day with no usage, which is a different thing from a day we
  /// have not measured yet.
  static Future<AiUsageSummary?> read() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('summary');
      return raw == null ? null : AiUsageSummary.fromJson(raw);
    } on PlatformException catch (e) {
      AppLog.aiUsage.failed('read the usage summary', e);
      return null;
    } on MissingPluginException catch (e) {
      AppLog.aiUsage.failed('reach the usage channel', e);
      return null;
    }
  }
}
