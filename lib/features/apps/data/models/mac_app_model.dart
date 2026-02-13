import 'dart:typed_data';

class MacApp {
  final String name;
  final String path;
  final String version;
  final String bundleId;
  final Uint8List? iconBytes;
  final String size;
  final String? developer;
  final String? lastOpened;

  MacApp({
    required this.name,
    required this.path,
    required this.version,
    required this.bundleId,
    this.iconBytes,
    required this.size,
    this.developer,
    this.lastOpened,
  });
}
