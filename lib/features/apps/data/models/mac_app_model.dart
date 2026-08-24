import 'dart:typed_data';

/// A macOS application bundle discovered by [AppManagerService].
///
/// Sizes are kept as raw bytes so nothing has to re-parse human readable
/// strings; format at the edge with `formatBytes` from `utils/size_utils.dart`.
class MacApp {
  const MacApp({
    required this.name,
    required this.path,
    required this.version,
    required this.bundleId,
    required this.sizeBytes,
    this.iconBytes,
    this.developer,
    this.lastUsed,
    this.isSystem = false,
  });

  final String name;
  final String path;
  final String version;
  final String bundleId;

  /// Size of the bundle on disk, in bytes.
  final int sizeBytes;

  /// PNG bytes extracted from the bundle's .icns, when available.
  final Uint8List? iconBytes;

  /// Vendor name, derived from the bundle id or the bundle's copyright string.
  final String? developer;

  /// Spotlight's `kMDItemLastUsedDate`, when the volume is indexed.
  final DateTime? lastUsed;

  /// Apps under /System/Applications: listed for context, never removable.
  final bool isSystem;

  /// Days since the app was last launched, or `null` when Spotlight has no record.
  int? get daysSinceLastUsed {
    final used = lastUsed;
    if (used == null) return null;
    return DateTime.now().difference(used).inDays;
  }

  /// Short human readable "last opened" label for the table.
  String get lastUsedLabel {
    final days = daysSinceLastUsed;
    if (days == null) return 'Never';
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 30) return '$days days ago';
    if (days < 365) {
      final months = days ~/ 30;
      return months == 1 ? '1 month ago' : '$months months ago';
    }
    final years = days ~/ 365;
    return years == 1 ? '1 year ago' : '$years years ago';
  }

  MacApp copyWith({
    String? name,
    String? path,
    String? version,
    String? bundleId,
    int? sizeBytes,
    Uint8List? iconBytes,
    String? developer,
    DateTime? lastUsed,
    bool? isSystem,
  }) {
    return MacApp(
      name: name ?? this.name,
      path: path ?? this.path,
      version: version ?? this.version,
      bundleId: bundleId ?? this.bundleId,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      iconBytes: iconBytes ?? this.iconBytes,
      developer: developer ?? this.developer,
      lastUsed: lastUsed ?? this.lastUsed,
      isSystem: isSystem ?? this.isSystem,
    );
  }

  /// Serialized for the on-disk scan cache. Icons live next to the cache as
  /// PNG files rather than inline base64, so they are excluded here.
  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'version': version,
    'bundleId': bundleId,
    'sizeBytes': sizeBytes,
    'developer': developer,
    'lastUsed': lastUsed?.toIso8601String(),
    'isSystem': isSystem,
  };

  factory MacApp.fromJson(Map<String, dynamic> json, {Uint8List? iconBytes}) {
    final lastUsedRaw = json['lastUsed'] as String?;
    return MacApp(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      version: json['version'] as String? ?? '',
      bundleId: json['bundleId'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      iconBytes: iconBytes,
      developer: json['developer'] as String?,
      lastUsed: lastUsedRaw == null ? null : DateTime.tryParse(lastUsedRaw),
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  /// Identity is the install location — two bundles can share a bundle id
  /// (e.g. the same app in /Applications and ~/Applications).
  @override
  bool operator ==(Object other) => other is MacApp && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
