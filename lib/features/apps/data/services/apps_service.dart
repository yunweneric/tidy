import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

class AppManagerService {
  static const String appsDir = '/Applications';

  /// 🔍 Scan installed apps
  Future<List<MacApp>> getInstalledApps() async {
    final dir = Directory(appsDir);

    if (!dir.existsSync()) return [];

    final apps = <MacApp>[];

    for (final entity in dir.listSync()) {
      if (!entity.path.endsWith('.app')) continue;

      final appName = entity.path.split('/').last;

      final info = await _readPlist(appName);
      final icon = await _findAppIcon(appName);
      final size = await _getSize(entity.path);

      // print('info: $info');

      apps.add(
        MacApp(
          name: info['name'] ?? appName.replaceAll('.app', ''),
          path: entity.path,
          version: info['version'] ?? '',
          bundleId: info['bundleId'] ?? '',
          iconBytes: icon,
          size: size,
        ),
      );
    }

    return apps;
  }

  /// 📄 Read Info.plist safely
  Future<Map<String, String>> _readPlist(String appName) async {
    try {
      final plist = '$appsDir/$appName/Contents/Info.plist';

      final result = await Process.run('plutil', ['-convert', 'json', '-o', '-', plist]);

      final data = jsonDecode(result.stdout);

      print('--------------------------------');
      print('data: $data');
      print('--------------------------------');

      return {
        'name': data['CFBundleName'] ?? data['CFBundleDisplayName'] ?? '',
        'version': data['CFBundleShortVersionString'] ?? '',
        'bundleId': data['CFBundleIdentifier'] ?? '',
      };
    } catch (_) {
      return {};
    }
  }

  /// 💾 Get disk usage
  Future<String> _getSize(String path) async {
    final result = await Process.run('du', ['-sh', path]);

    return result.stdout.toString().split('\t').first;
  }

  /// 🗑 Uninstall app + leftovers
  Future<void> uninstallApp(MacApp app) async {
    await Process.run('rm', ['-rf', app.path]);

    await _cleanupLeftovers(app);
  }

  /// 🧹 Deep clean
  Future<void> _cleanupLeftovers(MacApp app) async {
    final home = Platform.environment['HOME'];

    final patterns = [
      '$home/Library/Application Support/${app.name}',
      '$home/Library/Caches/${app.name}',
      '$home/Library/Logs/${app.name}',
      '$home/Library/Preferences/${app.bundleId}.plist',
    ];

    for (final path in patterns) {
      await Process.run('rm', ['-rf', path]);
    }
  }

  Future<Uint8List?> _findAppIcon(String appName) async {
    final resourcesPath = '/Applications/$appName/Contents/Resources';

    final dir = Directory(resourcesPath);

    if (!dir.existsSync()) return null;

    final icnsFiles =
        dir
            .listSync()
            .where((f) => f.path.toLowerCase().endsWith('.icns'))
            .cast<File>()
            .toList();

    if (icnsFiles.isEmpty) return null;

    icnsFiles.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));

    return _icnsToPngBytes(icnsFiles.first.path);
  }

  Future<Uint8List?> icnsToUint8List(String icnsPath) async {
    final result = await Process.run('sips', [
      '-s',
      'format',
      'png',
      icnsPath,
      '--out',
      '/dev/stdout',
    ], runInShell: true);

    if (result.exitCode != 0) {
      print('Icon conversion failed: ${result.stderr}');
      return null;
    }

    if (result.stdout is Uint8List) {
      return result.stdout as Uint8List;
    }

    return Uint8List.fromList(result.stdout.codeUnits);
  }

  /// Converts .icns to PNG bytes by writing the iconset to a writable temp dir
  /// (app bundle Resources is read-only, so iconutil cannot write there).
  Future<Uint8List?> _icnsToPngBytes(String icnsPath) async {
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('icns_');
      final iconsetPath = p.join(tempDir.path, 'icon.iconset');

      final result = await Process.run('iconutil', [
        '--convert',
        'iconset',
        icnsPath,
        '--output',
        iconsetPath,
      ]);

      if (result.exitCode != 0) return null;

      // Prefer largest PNG; fallback to smaller sizes if missing
      const candidates = [
        'icon_512x512@2x.png',
        'icon_512x512.png',
        'icon_256x256@2x.png',
        'icon_256x256.png',
        'icon_128x128@2x.png',
        'icon_128x128.png',
        'icon_32x32@2x.png',
        'icon_32x32.png',
      ];

      for (final name in candidates) {
        final file = File(p.join(iconsetPath, name));
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
      return null;
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
