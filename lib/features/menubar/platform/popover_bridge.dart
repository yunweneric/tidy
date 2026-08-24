import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to `macos/Runner/MenuBarController.swift`, which owns the status item
/// and the popover this engine is rendered into.
class PopoverBridge {
  PopoverBridge({VoidCallback? onPopoverOpened}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'popoverDidOpen') {
        onPopoverOpened?.call();
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.macuninstaller/popover',
  );

  double? _lastReportedHeight;

  /// Resizes the popover to fit its content. Ignores sub-pixel churn so the
  /// panel does not jitter while the list streams in.
  Future<void> setHeight(double height) async {
    if (_lastReportedHeight != null && (_lastReportedHeight! - height).abs() < 2) {
      return;
    }
    _lastReportedHeight = height;
    try {
      await _channel.invokeMethod<void>('setPopoverHeight', {'height': height});
    } catch (e) {
      debugPrint('setPopoverHeight failed: $e');
    }
  }

  Future<void> close() => _invoke('closePopover');

  Future<void> openMainWindow() => _invoke('openMainWindow');

  Future<void> quitApp() => _invoke('quitApp');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (e) {
      debugPrint('$method failed: $e');
    }
  }
}
