import 'package:equatable/equatable.dart';
import 'package:mac_uninstaller/core/platform/trash_ledger.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/models/trash_location.dart';

/// What sort of thing this is, for the row glyph.
///
/// Deliberately coarse. macOS hands back a localized type description
/// ("Portable Network Graphics image") which is right for a details column and
/// far too specific to pick an icon from.
enum TrashItemKind { folder, app, image, video, audio, archive, document, other }

/// One item sitting in a Trash folder.
class TrashItem extends Equatable {
  const TrashItem({
    required this.path,
    required this.name,
    required this.locationId,
    required this.sizeBytes,
    required this.isDirectory,
    required this.isPackage,
    required this.kindLabel,
    required this.extension,
    this.deletedAt,
    this.origin,
  });

  factory TrashItem.fromMap(Map<String, dynamic> map) {
    final deleted = (map['deletedAt'] as num?)?.toDouble() ?? 0;
    return TrashItem(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      locationId: map['locationId'] as String? ?? '',
      sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
      isDirectory: map['isDirectory'] as bool? ?? false,
      isPackage: map['isPackage'] as bool? ?? false,
      kindLabel: map['kind'] as String? ?? '',
      extension: map['extension'] as String? ?? '',
      deletedAt:
          deleted <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch((deleted * 1000).round()),
    );
  }

  /// Where it is now, inside the Trash. Stable while it is in there, so it is
  /// the row's identity and what selection is keyed on.
  final String path;

  final String name;

  /// Which [TrashLocation] it belongs to.
  final String locationId;

  /// Allocated bytes, so the figure matches what emptying actually frees.
  final int sizeBytes;

  final bool isDirectory;

  /// A bundle — an `.app`, a `.photoslibrary`. One item to a person, a folder
  /// to the filesystem, and never to be opened up.
  final bool isPackage;

  /// macOS's own words for it: "Folder", "PNG image", "Application".
  final String kindLabel;

  final String extension;

  /// When it went into the Trash. Null when macOS has no record, which happens
  /// for items moved in by something that did not set the date.
  final DateTime? deletedAt;

  /// Where it came from, when Tidy is the one that trashed it.
  final TrashOrigin? origin;

  TrashItem withOrigin(TrashOrigin? origin) => TrashItem(
    path: path,
    name: name,
    locationId: locationId,
    sizeBytes: sizeBytes,
    isDirectory: isDirectory,
    isPackage: isPackage,
    kindLabel: kindLabel,
    extension: extension,
    deletedAt: deletedAt,
    origin: origin,
  );

  /// True when this can go straight back where it came from, with nothing to
  /// ask the user.
  bool get canPutBack => origin != null;

  /// How long it has been sitting there. Null when the date is unknown.
  int? get daysInBin =>
      deletedAt == null ? null : DateTime.now().difference(deletedAt!).inDays;

  TrashItemKind get kind {
    if (isPackage && extension == 'app') return TrashItemKind.app;
    if (isDirectory && !isPackage) return TrashItemKind.folder;

    return switch (extension) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'heic' || 'webp' || 'tiff' || 'svg' =>
        TrashItemKind.image,
      'mp4' || 'mov' || 'm4v' || 'avi' || 'mkv' || 'webm' => TrashItemKind.video,
      'mp3' || 'm4a' || 'wav' || 'aiff' || 'flac' || 'aac' => TrashItemKind.audio,
      'zip' || 'dmg' || 'gz' || 'tar' || 'rar' || '7z' || 'pkg' =>
        TrashItemKind.archive,
      'pdf' || 'doc' || 'docx' || 'txt' || 'md' || 'pages' || 'key' || 'numbers' =>
        TrashItemKind.document,
      _ => isDirectory ? TrashItemKind.folder : TrashItemKind.other,
    };
  }

  @override
  List<Object?> get props => [path, sizeBytes, deletedAt, origin?.originalPath];
}

/// Everything in every bin, as one read.
class TrashSnapshot extends Equatable {
  const TrashSnapshot({this.locations = const [], this.items = const []});

  static const TrashSnapshot empty = TrashSnapshot();

  final List<TrashLocation> locations;
  final List<TrashItem> items;

  int get totalBytes =>
      items.fold(0, (sum, item) => sum + item.sizeBytes);

  @override
  List<Object?> get props => [locations, items];
}
