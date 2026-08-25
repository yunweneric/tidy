import 'package:flutter/services.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/menubar/data/models/menu_bar_prefs.dart';

/// Mirrors the menu bar preferences into the native side, now and on every
/// change.
///
/// One funnel, for the reason `ClipboardService.bindTo` and
/// `NetworkService.bindTo` give: a setter that forgot to push would leave the
/// bar showing icons the user had already switched off, with nothing on screen
/// to suggest the app had heard them.
///
/// Main engine only. The popover has no settings UI, and the native side reads
/// the same file itself at launch.
class MenuBarService {
  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/menu_bar',
  );

  AppSettings? _settings;
  MenuBarPrefs? _pushed;

  void bindTo(AppSettings settings) {
    if (identical(_settings, settings)) return;
    _settings?.removeListener(_syncPrefs);
    _settings = settings;
    settings.addListener(_syncPrefs);
    _syncPrefs();
  }

  void _syncPrefs() {
    final settings = _settings;
    if (settings == null) return;

    // `AppSettings` notifies for every preference, theme included, so only a
    // real change to the menu bar ones is worth a channel round trip — and a
    // round trip here tears the bar down and rebuilds it.
    final prefs = MenuBarPrefs.from(settings);
    if (prefs == _pushed) return;
    _pushed = prefs;
    _configure(prefs);
  }

  Future<void> _configure(MenuBarPrefs prefs) async {
    try {
      await _channel.invokeMethod<void>('configure', prefs.toMap());
    } on PlatformException catch (e) {
      AppLog.menuBar.failed('push the menu bar preferences', e);
    } on MissingPluginException catch (e) {
      AppLog.menuBar.failed('reach the menu bar channel', e);
    }
  }

  void dispose() {
    _settings?.removeListener(_syncPrefs);
    _settings = null;
  }
}
