import 'package:tidy/core/logging/logging.dart';
import 'package:flutter/services.dart';

/// What arrives with `popoverDidOpen`.
///
/// A record rather than three loose positional strings: every field in it is a
/// nullable `String?`, so the day two of them get swapped at a call site
/// nothing would fail — the panel would open on the wrong tab in the wrong
/// style, and go on doing it.
typedef PopoverOpening =
    ({String? section, String? layout, String? aiWindowStyle});

/// Talks to `macos/Runner/MenuBarController.swift`, which owns the status item
/// and the popover this engine is rendered into.
///
/// One instance per engine: a method channel has room for exactly one handler,
/// so a second bridge would silently take the callbacks off the first.
class PopoverBridge {
  PopoverBridge({
    this.onAppearanceChanged,
    this.onPopoverOpened,
    this.onPopoverClosed,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'popoverDidOpen':
          final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
          // The section rides along with the open rather than following it.
          // Which panel to show is part of *what opened*, and announcing it
          // separately makes the panel change shape twice while the popover is
          // still animating — which the resize handshake does not survive.
          // The layout rides along for the same reason: whether there is a
          // tab strip is part of what opened, and this engine has no
          // `AppSettings` of its own to look it up in.
          // The AI window style travels the same road for the same reason:
          // it is a preference this engine has no `AppSettings` to read.
          onPopoverOpened?.call((
            section: arguments?['section'] as String?,
            layout: arguments?['layout'] as String?,
            aiWindowStyle: arguments?['aiWindowStyle'] as String?,
          ));
        case 'popoverDidClose':
          onPopoverClosed?.call();
        case 'appearanceChanged':
          final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
          onAppearanceChanged?.call(arguments?['dark'] as bool? ?? false);
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/popover',
  );

  /// Set by whoever owns the panel's data — the popover is only worth sampling
  /// while it is on screen.
  ///
  /// The argument carries the section the popover was opened for — null from
  /// the vitals icon, "clipboard" from the clipboard icon and from ⌘⇧V — the
  /// layout the bar is currently in, and how the AI usage windows draw.
  ValueChanged<PopoverOpening>? onPopoverOpened;
  VoidCallback? onPopoverClosed;

  /// The system switched between light and dark.
  final ValueChanged<bool>? onAppearanceChanged;

  double? _lastReportedHeight;

  /// Tells the native side the user picked a different tab.
  ///
  /// Only used by the consolidated layout, and only while the popover is
  /// already open. Swift owns the popover's width and the height it remembers
  /// for each section, so without this a tab switch would leave the panel at
  /// the previous section's height until it was next opened from the bar.
  ///
  /// Deliberately *not* how the section arrives on open — see the note on
  /// `popoverDidOpen` above. Announcing a section separately from the open is
  /// what the resize handshake does not survive.
  Future<void> setSection(String section) async {
    try {
      await _channel.invokeMethod<void>('setSection', {'section': section});
    } on PlatformException catch (e) {
      AppLog.menuBar.failed('switch the popover section', e);
    }
  }

  /// Whether the menu bar is currently dark.
  ///
  /// Asked for rather than read from `MediaQuery`: this engine is started
  /// headless before any window exists and does not reliably learn the system
  /// appearance, which is how the panel ends up painting light-theme text onto
  /// a dark popover.
  Future<bool> isDarkAppearance() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'appearance',
      );
      return result?['dark'] as bool? ?? false;
    } catch (e) {
      AppLog.menuBar.failed('read the popover appearance', e);
      return false;
    }
  }

  /// Resizes the popover to fit its content. Ignores sub-pixel churn so the
  /// panel does not jitter while the list streams in.
  Future<void> setHeight(double height) async {
    if (_lastReportedHeight != null &&
        (_lastReportedHeight! - height).abs() < 2) {
      return;
    }
    _lastReportedHeight = height;
    try {
      await _channel.invokeMethod<void>('setPopoverHeight', {'height': height});
    } catch (e) {
      AppLog.menuBar.failed(
        'set the popover height',
        e,
        fields: {'height': height},
      );
    }
  }

  Future<void> close() => _invoke('closePopover');

  /// Shows the hover preview for a clip beside the panel.
  ///
  /// [top] is the row's distance from the top of the panel, so AppKit can line
  /// the preview up with the row the pointer is actually on. Drawn natively
  /// because it has to appear outside the popover, which clips its content.
  Future<void> showClipPreview({required String id, required double top}) =>
      _send('showClipPreview', {'id': id, 'top': top});

  Future<void> hideClipPreview() => _invoke('hideClipPreview');

  /// Brings the main window forward, optionally at a particular route.
  ///
  /// The route is handed over natively: this engine is a separate isolate and
  /// cannot reach the main window's router.
  Future<void> openMainWindow({String? route}) async {
    try {
      await _channel.invokeMethod<void>('openMainWindow', {
        if (route != null) 'route': route,
      });
    } catch (e) {
      AppLog.menuBar.failed(
        'open the main window',
        e,
        fields: {'route': route},
      );
    }
  }

  Future<void> quitApp() => _invoke('quitApp');

  Future<void> _invoke(String method) async => _send(method, null);

  Future<void> _send(String method, Map<String, dynamic>? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e) {
      AppLog.menuBar.failed('call the menu bar', e, fields: {'method': method});
    }
  }
}

/// The main window's end of the popover channel.
///
/// The popover runs in its own Flutter engine, a separate Dart isolate that
/// cannot reach the main window's router. "Open Clipboard" therefore goes out
/// to `MenuBarController`, which hands the route to the main engine, which
/// arrives here.
///
/// Static, and set up once: a method channel holds exactly one handler, and
/// the main engine has no [PopoverBridge] of its own to compete with.
class PopoverRoutes {
  const PopoverRoutes._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/popover',
  );

  static void listen(ValueChanged<String> onRoute) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'navigateTo') return null;
      final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
      final route = arguments?['route'] as String?;
      if (route != null) onRoute(route);
      return null;
    });
  }
}
