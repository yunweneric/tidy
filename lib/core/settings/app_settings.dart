import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:tidy/core/design/brand.dart';
import 'package:tidy/features/clipboard/data/models/clipboard_prefs.dart';
import 'package:tidy/features/network/data/models/network_prefs.dart';
import 'package:tidy/features/network/data/models/network_units.dart';
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
  static const String _coverageNoteKey = 'smartCareCoverageSeen';

  // Clipboard. These four are also read directly by `ClipboardStore.swift` at
  // launch, so the native store honours the user's limits before any Flutter
  // engine has spoken. Renaming one here means renaming it there.
  static const String _clipboardEnabledKey = 'clipboardEnabled';
  static const String _clipboardMaxItemsKey = 'clipboardMaxItems';
  static const String _clipboardRetentionKey = 'clipboardRetentionDays';
  static const String _clipboardImagesKey = 'clipboardCaptureImages';
  static const String _clipboardSensitiveKey = 'clipboardStoreSensitive';
  static const String _clipboardClearOnQuitKey = 'clipboardClearOnQuit';
  static const String _clipboardExcludedKey = 'clipboardExcludedApps';

  // Network. Read directly by `NetworkStore.swift` at launch, so the menu bar
  // readout is already in the right style — or already absent — before any
  // Flutter engine has run. Renaming one here means renaming it there.
  static const String _networkMenuBarKey = 'networkMenuBarEnabled';
  static const String _networkStyleKey = 'networkMenuBarStyle';
  static const String _networkBitsKey = 'networkUseBits';

  /// Bumping this shows onboarding again — for when a release adds a
  /// permission or a capability the existing copy does not cover.
  ///
  /// 2: the clipboard recorder. It keeps a record of what the user does, and
  /// existing users have never been asked about it — an opt-in buried in
  /// Settings would be an opt-in nobody made.
  static const int onboardingVersion = 2;

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
      p.join(
        home,
        'Library',
        'Application Support',
        Brand.supportDirectoryName,
      ),
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

  /// Whether Smart Care has already shown its coverage note.
  ///
  /// The note says which checks are built and which are not, which matters
  /// enormously the first time and is clutter every time after. It appears on
  /// the first visit and never again — the checkbox on it is there so someone
  /// who wants it gone before they have finished reading can say so outright.
  bool get hasSeenSmartCareCoverage =>
      _values[_coverageNoteKey] as bool? ?? false;

  void markSmartCareCoverageSeen() {
    if (hasSeenSmartCareCoverage) return;
    _values[_coverageNoteKey] = true;
    _persist();
  }

  // ─── Clipboard ─────────────────────────────────────────────────────────

  /// Off until the user turns it on, and deliberately so.
  ///
  /// Recording the clipboard means writing everything copied — including the
  /// passwords the redaction heuristics miss — to an unencrypted file. That is
  /// a reasonable thing to ask for and an unreasonable thing to assume, so the
  /// Clipboard page opens on a plain statement of what it stores and a button
  /// to start.
  bool get clipboardEnabled => _values[_clipboardEnabledKey] as bool? ?? false;

  set clipboardEnabled(bool value) {
    _values[_clipboardEnabledKey] = value;
    _persist();
  }

  /// How many unpinned entries to keep. Pinned ones do not count against it.
  int get clipboardMaxItems => _values[_clipboardMaxItemsKey] as int? ?? 200;

  set clipboardMaxItems(int value) {
    _values[_clipboardMaxItemsKey] = value;
    _persist();
  }

  ClipboardRetention get clipboardRetention =>
      ClipboardRetention.fromDays(_values[_clipboardRetentionKey] as int? ?? 7);

  set clipboardRetention(ClipboardRetention value) {
    _values[_clipboardRetentionKey] = value.days;
    _persist();
  }

  bool get clipboardCaptureImages =>
      _values[_clipboardImagesKey] as bool? ?? true;

  set clipboardCaptureImages(bool value) {
    _values[_clipboardImagesKey] = value;
    _persist();
  }

  /// Whether anything that looks like a secret is kept at all. Off means such
  /// items are dropped at capture and never reach the disk; on means they are
  /// stored but blurred in the list.
  bool get clipboardStoreSensitive =>
      _values[_clipboardSensitiveKey] as bool? ?? false;

  set clipboardStoreSensitive(bool value) {
    _values[_clipboardSensitiveKey] = value;
    _persist();
  }

  bool get clipboardClearOnQuit =>
      _values[_clipboardClearOnQuitKey] as bool? ?? false;

  set clipboardClearOnQuit(bool value) {
    _values[_clipboardClearOnQuitKey] = value;
    _persist();
  }

  /// Apps whose copies are never recorded. The native side adds its own list of
  /// known password managers to whatever is here.
  List<String> get clipboardExcludedApps =>
      (_values[_clipboardExcludedKey] as List?)?.cast<String>() ?? const [];

  set clipboardExcludedApps(List<String> value) {
    _values[_clipboardExcludedKey] = value;
    _persist();
  }

  // ─── Network ───────────────────────────────────────────────────────────

  /// Whether the live readout appears in the menu bar.
  ///
  /// On by default, unlike the clipboard recorder: reading interface counters
  /// needs no permission, records nothing about *what* was sent, and a network
  /// monitor nobody can see is not a network monitor. The switch exists because
  /// the readout permanently occupies menu bar width, which is the scarcest
  /// space on the machine — not because the recording is sensitive.
  bool get networkMenuBarEnabled =>
      _values[_networkMenuBarKey] as bool? ?? true;

  set networkMenuBarEnabled(bool value) {
    _values[_networkMenuBarKey] = value;
    _persist();
  }

  NetworkMenuBarStyle get networkMenuBarStyle =>
      NetworkMenuBarStyle.fromName(_values[_networkStyleKey] as String?);

  set networkMenuBarStyle(NetworkMenuBarStyle value) {
    _values[_networkStyleKey] = value.name;
    _persist();
  }

  /// Rates only. Cumulative totals stay in bytes whichever way this is set —
  /// nobody measures a month's usage in gigabits, and an ISP's cap is quoted in
  /// gigabytes.
  NetworkUnits get networkUnits =>
      (_values[_networkBitsKey] as bool? ?? false)
          ? NetworkUnits.bits
          : NetworkUnits.bytes;

  set networkUnits(NetworkUnits value) {
    _values[_networkBitsKey] = value.isBits;
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
