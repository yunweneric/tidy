import 'package:equatable/equatable.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';

/// How long history is kept before it clears itself.
enum ClipboardRetention {
  never('Never', 0),
  day('24 hours', 1),
  week('7 days', 7),
  month('30 days', 30);

  const ClipboardRetention(this.label, this.days);

  final String label;

  /// Zero means never expire.
  final int days;

  static ClipboardRetention fromDays(int days) => values.firstWhere(
    (retention) => retention.days == days,
    orElse: () => ClipboardRetention.week,
  );
}

/// How much history to keep. The presets exist because the number is a rough
/// preference, not a measurement, and a free-form field invites picking 137.
const List<int> clipboardHistorySizes = [50, 200, 500, 1000];

/// The user's clipboard settings, as the native store needs them.
///
/// [AppSettings] is the single source of truth; this is the shape it takes on
/// the way across the channel. The Swift side also reads the same keys straight
/// out of `settings.json` at launch, so a start with no window open still
/// honours them before Dart has said anything.
class ClipboardPrefs extends Equatable {
  const ClipboardPrefs({
    required this.enabled,
    required this.maxItems,
    required this.retention,
    required this.captureImages,
    required this.storeSensitive,
    required this.clearOnQuit,
    required this.excludedApps,
  });

  factory ClipboardPrefs.from(AppSettings settings) => ClipboardPrefs(
    enabled: settings.clipboardEnabled,
    maxItems: settings.clipboardMaxItems,
    retention: settings.clipboardRetention,
    captureImages: settings.clipboardCaptureImages,
    storeSensitive: settings.clipboardStoreSensitive,
    clearOnQuit: settings.clipboardClearOnQuit,
    excludedApps: settings.clipboardExcludedApps,
  );

  final bool enabled;
  final int maxItems;
  final ClipboardRetention retention;
  final bool captureImages;
  final bool storeSensitive;
  final bool clearOnQuit;
  final List<String> excludedApps;

  /// Keys match `settings.json` exactly — the native side parses that file
  /// directly, so two spellings would mean two behaviours.
  Map<String, dynamic> toMap() => {
    'clipboardEnabled': enabled,
    'clipboardMaxItems': maxItems,
    'clipboardRetentionDays': retention.days,
    'clipboardCaptureImages': captureImages,
    'clipboardStoreSensitive': storeSensitive,
    'clipboardClearOnQuit': clearOnQuit,
    'clipboardExcludedApps': excludedApps,
  };

  @override
  List<Object?> get props => [
    enabled,
    maxItems,
    retention,
    captureImages,
    storeSensitive,
    clearOnQuit,
    excludedApps,
  ];
}
