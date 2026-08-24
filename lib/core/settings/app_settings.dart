import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:mac_uninstaller/core/design/brand.dart';
import 'package:path/path.dart' as p;

/// User preferences, persisted as JSON next to the scan cache.
///
/// A plain file rather than `shared_preferences`: the project already reads and
/// writes its own Application Support directory, the payload is three fields,
/// and it keeps the dependency list honest.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._file, this._values);

  final File? _file;
  final Map<String, dynamic> _values;

  static const String _themeKey = 'themeMode';
  static const String _reduceMotionKey = 'reduceMotion';
  static const String _onboardingKey = 'onboardingCompletedVersion';

  /// Bumping this shows onboarding again — for when a release adds a
  /// permission or a capability the existing copy does not cover.
  static const int onboardingVersion = 1;

  /// Loads from disk, falling back to defaults if anything is missing or
  /// unreadable. Never throws — a corrupt settings file should not stop the app
  /// from opening.
  static Future<AppSettings> load() async {
    final file = await _settingsFile();
    Map<String, dynamic> values = {};

    if (file != null && file.existsSync()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) values = decoded;
      } catch (e) {
        debugPrint('Could not read settings: $e');
      }
    }

    return AppSettings._(file, values);
  }

  static Future<File?> _settingsFile() async {
    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final dir = Directory(
      p.join(home, 'Library', 'Application Support', Brand.supportDirectoryName),
    );
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('Cannot create settings directory: ${e.message}');
      return null;
    }
    return File(p.join(dir.path, 'settings.json'));
  }

  /// Follows the system appearance unless the user has chosen otherwise.
  ThemeMode get themeMode => switch (_values[_themeKey] as String?) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  set themeMode(ThemeMode mode) {
    _values[_themeKey] = mode.name;
    _persist();
  }

  /// Strips the scan animations. Shipped from day one rather than retrofitted:
  /// motion is spread across every module, and adding the switch later means
  /// touching all of them.
  bool get reduceMotion => _values[_reduceMotionKey] as bool? ?? false;

  set reduceMotion(bool value) {
    _values[_reduceMotionKey] = value;
    _persist();
  }

  /// False on first run, and again after [onboardingVersion] is bumped.
  bool get hasCompletedOnboarding =>
      (_values[_onboardingKey] as int? ?? 0) >= onboardingVersion;

  void completeOnboarding() {
    _values[_onboardingKey] = onboardingVersion;
    _persist();
  }

  /// Used by the "show me the intro again" affordance in Settings.
  void resetOnboarding() {
    _values.remove(_onboardingKey);
    _persist();
  }

  void _persist() {
    notifyListeners();
    final file = _file;
    if (file == null) return;
    file.writeAsString(jsonEncode(_values)).catchError((Object e) {
      debugPrint('Could not write settings: $e');
      return file;
    });
  }
}
