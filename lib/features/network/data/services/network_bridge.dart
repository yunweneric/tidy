import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tidy/core/platform/action_outcome.dart';
import 'package:tidy/features/network/data/models/network_prefs.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/core/models/network_series.dart';

/// Thin wrapper over `macos/Runner/NetworkChannel.swift`.
///
/// The sampler and the history live natively for the same reasons the clipboard
/// does: recording has to continue with no window open, and two Flutter engines
/// in separate isolates would be two writers racing on one file. Each engine
/// gets its own channel onto the one native monitor.
///
/// Every call degrades to an empty result rather than throwing — a chart missing
/// a bar is better than a page that crashes.
class NetworkBridge {
  NetworkBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/network',
  );

  static StreamController<NetworkSample>? _samples;

  /// One reading a second, pushed while this engine has asked for them.
  ///
  /// A push rather than a poll because the native side is already sampling on a
  /// timer for the menu bar; a second timer here would be two clocks disagreeing
  /// about the same counters. Listening is not enough on its own — call
  /// [startLive] to open the tap and [stopLive] to close it, so an engine whose
  /// panel is shut is not woken sixty times a minute.
  static Stream<NetworkSample> get onSample {
    final existing = _samples;
    if (existing != null) return existing.stream;

    final controller = StreamController<NetworkSample>.broadcast();
    _samples = controller;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'networkDidSample' && !controller.isClosed) {
        final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
        if (arguments != null) {
          controller.add(NetworkSample.fromMap(arguments));
        }
      }
      return null;
    });
    return controller.stream;
  }

  /// The current reading, with the last five minutes of history attached so a
  /// panel that has just opened draws a populated chart rather than filling one
  /// in a pixel at a time.
  static Future<NetworkSample> live() => _read('live');

  /// Opens the tap and returns the reading that was already there.
  static Future<NetworkSample> startLive() => _read('startLive');

  static Future<void> stopLive() async {
    try {
      await _channel.invokeMethod<void>('stopLive');
    } catch (e) {
      debugPrint('network stopLive failed: $e');
    }
  }

  static Future<NetworkSample> _read(String method) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method);
      if (result == null) return NetworkSample.unknown;
      return NetworkSample.fromMap(result);
    } catch (e) {
      debugPrint('network $method failed: $e');
      return NetworkSample.unknown;
    }
  }

  /// One range's buckets, already at the granularity the chart wants.
  static Future<NetworkSeries> history(NetworkRange range) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('history', {
        'range': range.id,
      });
      if (result == null) return NetworkSeries.empty;
      return NetworkSeries.fromMap(result);
    } catch (e) {
      debugPrint('network history failed: $e');
      return NetworkSeries.empty;
    }
  }

  /// Today, this month, and the busiest day on record.
  static Future<NetworkHeadline> headline() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('headline');
      if (result == null) return NetworkHeadline.empty;
      return NetworkHeadline.fromMap(result);
    } catch (e) {
      debugPrint('network headline failed: $e');
      return NetworkHeadline.empty;
    }
  }

  static Future<void> configure(NetworkPrefs prefs) async {
    try {
      await _channel.invokeMethod<void>('configure', prefs.toMap());
    } catch (e) {
      debugPrint('network configure failed: $e');
    }
  }

  /// Throws away every recorded bucket. Irreversible, and the only destructive
  /// thing this feature can do — which is why it lives in Settings behind a
  /// confirmation rather than on the page.
  static Future<ActionOutcome> reset() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('reset');
      return ActionOutcome.fromMap(result);
    } catch (e) {
      debugPrint('network reset failed: $e');
      return const ActionOutcome(ok: false, message: 'That could not be done.');
    }
  }
}
