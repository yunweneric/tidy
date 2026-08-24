import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mac_uninstaller/core/platform/action_outcome.dart';
import 'package:mac_uninstaller/features/clipboard/data/models/clipboard_prefs.dart';

/// Thin wrapper over `macos/Runner/ClipboardChannel.swift`.
///
/// The history lives natively rather than here. Capture has to keep working
/// with no window open, and the app runs two Flutter engines in separate
/// isolates — a Dart-side store would be two writers racing on every copy.
/// Each engine gets its own channel onto the one native store instead.
///
/// Every call degrades to an empty result rather than throwing: a Clipboard
/// page missing a row is better than one that crashes.
class ClipboardBridge {
  ClipboardBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.macuninstaller/clipboard',
  );

  static StreamController<void>? _changes;

  /// Fires when the native store changes — a copy, a pin, a clear.
  ///
  /// A push rather than a poll: a copy is an event macOS hands us, so asking
  /// every second for something that mostly has not happened would be the wrong
  /// shape. It is also why there is no timer to gate on visibility.
  static Stream<void> get onChanged {
    final existing = _changes;
    if (existing != null) return existing.stream;

    final controller = StreamController<void>.broadcast();
    _changes = controller;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'clipboardDidChange' && !controller.isClosed) {
        controller.add(null);
      }
      return null;
    });
    return controller.stream;
  }

  /// Every entry, newest first. Metadata only — short text rides along, but
  /// images and long text are fetched by id when something shows them.
  static Future<List<Map<String, dynamic>>> history() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('history');
      if (result == null) return const [];
      return result.map((raw) => (raw as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      debugPrint('clipboard history failed: $e');
      return const [];
    }
  }

  /// The stored bytes for an image or a piece of rich text.
  static Future<Uint8List?> blob(String id) async {
    try {
      return await _channel.invokeMethod<Uint8List>('blob', {'id': id});
    } catch (e) {
      debugPrint('clipboard blob failed: $e');
      return null;
    }
  }

  /// The whole text of an entry, including the part too long to have been kept
  /// inline.
  static Future<String?> fullText(String id) async {
    try {
      return await _channel.invokeMethod<String>('fullText', {'id': id});
    } catch (e) {
      debugPrint('clipboard fullText failed: $e');
      return null;
    }
  }

  /// Puts an entry back on the system clipboard. The native side suppresses the
  /// change this causes, so it does not come straight back in as a new copy.
  static Future<ActionOutcome> copyToPasteboard(String id) =>
      _act('copyToPasteboard', {'id': id});

  static Future<ActionOutcome> setPinned(String id, {required bool pinned}) =>
      _act('setPinned', {'id': id, 'pinned': pinned});

  static Future<ActionOutcome> delete(List<String> ids) =>
      _act('delete', {'ids': ids});

  static Future<ActionOutcome> clear({required bool keepPinned}) =>
      _act('clear', {'keepPinned': keepPinned});

  static Future<ActionOutcome> configure(ClipboardPrefs prefs) =>
      _act('configure', prefs.toMap());

  /// Shows a copied file in Finder.
  static Future<ActionOutcome> revealSource(String id) =>
      _act('revealSource', {'id': id});

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
      debugPrint('clipboard $method failed: $message');
      return ActionOutcome(ok: false, message: message);
    }
  }
}
