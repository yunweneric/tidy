import 'package:equatable/equatable.dart';

/// One Trash folder.
///
/// There is never only one. `~/.Trash` holds what was deleted from the boot
/// volume, and every writable volume keeps its own `.Trashes/<uid>` — which is
/// why a drive can stay full after someone has "emptied the Trash". Each is
/// listed separately so the space can be attributed to the disk it is on.
class TrashLocation extends Equatable {
  const TrashLocation({
    required this.id,
    required this.path,
    required this.label,
    required this.isHome,
    required this.readable,
  });

  factory TrashLocation.fromMap(Map<String, dynamic> map) {
    final path = map['path'] as String? ?? '';
    return TrashLocation(
      id: map['id'] as String? ?? path,
      path: path,
      label: map['label'] as String? ?? 'Trash',
      isHome: map['isHome'] as bool? ?? false,
      readable: map['readable'] as bool? ?? true,
    );
  }

  /// The folder's path, which is unique and stable.
  final String id;

  final String path;

  /// "This Mac", or the volume's name.
  final String label;

  final bool isHome;

  /// False when macOS refused to list it. Reading `~/.Trash` needs Full Disk
  /// Access, and a denial has to be reported as a denial — an unreadable bin
  /// shown as an empty one is the app telling the user there is nothing to
  /// reclaim when there may be gigabytes.
  final bool readable;

  @override
  List<Object?> get props => [id, path, label, isHome, readable];
}
