import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// What kind of thing was copied.
///
/// Raw names cross the channel to `ClipboardKind` in `ClipboardStore.swift` and
/// must stay in step with it.
enum ClipboardKind {
  text('Text', AppIcons.plainText),
  link('Links', AppIcons.link),
  richText('Formatted', AppIcons.richText),
  image('Images', AppIcons.image),
  files('Files', AppIcons.folder);

  const ClipboardKind(this.label, this.icon);

  final String label;
  final IconData icon;

  static ClipboardKind fromName(String? name) => values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => ClipboardKind.text,
  );
}

/// One thing the user copied.
///
/// The heavy part — image bytes, RTF, long text — stays native and is fetched
/// by id only when something is about to show it. A history of a thousand rows
/// is a thousand of these and no pixels.
class ClipboardEntry extends Equatable {
  const ClipboardEntry({
    required this.id,
    required this.kind,
    required this.preview,
    required this.text,
    required this.byteCount,
    required this.characterCount,
    required this.paths,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.sourceAppName,
    required this.sourceBundleId,
    required this.firstCopiedAt,
    required this.lastCopiedAt,
    required this.copyCount,
    required this.pinned,
    required this.sensitive,
    required this.hasBlob,
  });

  factory ClipboardEntry.fromMap(Map<String, dynamic> map) {
    return ClipboardEntry(
      id: map['id'] as String? ?? '',
      kind: ClipboardKind.fromName(map['kind'] as String?),
      preview: map['preview'] as String? ?? '',
      text: map['text'] as String?,
      byteCount: (map['byteCount'] as num?)?.toInt() ?? 0,
      characterCount: (map['characterCount'] as num?)?.toInt() ?? 0,
      paths: (map['paths'] as List?)?.cast<String>() ?? const [],
      pixelWidth: (map['pixelWidth'] as num?)?.toInt() ?? 0,
      pixelHeight: (map['pixelHeight'] as num?)?.toInt() ?? 0,
      sourceAppName: map['sourceAppName'] as String?,
      sourceBundleId: map['sourceBundleId'] as String?,
      firstCopiedAt: _time(map['firstCopiedAt']),
      lastCopiedAt: _time(map['lastCopiedAt']),
      copyCount: (map['copyCount'] as num?)?.toInt() ?? 1,
      pinned: map['pinned'] as bool? ?? false,
      sensitive: map['sensitive'] as bool? ?? false,
      hasBlob: map['hasBlob'] as bool? ?? false,
    );
  }

  static DateTime _time(Object? raw) =>
      DateTime.fromMillisecondsSinceEpoch((raw as num?)?.toInt() ?? 0);

  /// SHA-256 of the copied bytes. Also the dedupe key, which is why copying the
  /// same thing twice bumps [copyCount] instead of adding a row.
  final String id;
  final ClipboardKind kind;

  /// A single collapsed line for the list — never the whole payload.
  final String preview;

  /// The full text, when it was short enough to keep inline. Null for images,
  /// and for text long enough to have been written to a blob.
  final String? text;

  final int byteCount;
  final int characterCount;
  final List<String> paths;
  final int pixelWidth;
  final int pixelHeight;

  final String? sourceAppName;
  final String? sourceBundleId;

  final DateTime firstCopiedAt;
  final DateTime lastCopiedAt;
  final int copyCount;

  final bool pinned;

  /// Matched a secret-shaped pattern, or came from somewhere that deals in
  /// them. Blurred in the list until the user asks to see it.
  final bool sensitive;

  /// Whether the payload is still on disk. False for an image that was over the
  /// size ceiling — the row remembers that you copied it, not what it was.
  final bool hasBlob;

  bool get isEmptied => !hasBlob && text == null && paths.isEmpty;

  /// Path- and code-shaped text reads better in the monospace face.
  bool get prefersMono =>
      kind == ClipboardKind.files ||
      preview.startsWith('/') ||
      preview.startsWith('~/');

  /// The line under the preview: where it came from and how often it has been
  /// used. Assembled here so the row and the popover cannot word it differently.
  String get detail {
    final parts = <String>[
      if (sourceAppName != null) sourceAppName!,
      if (copyCount > 1) 'copied $copyCount times',
      if (kind == ClipboardKind.files && paths.length > 1) '${paths.length} items',
    ];
    return parts.join(' · ');
  }

  @override
  List<Object?> get props => [id, pinned, sensitive, copyCount, lastCopiedAt, hasBlob];
}
