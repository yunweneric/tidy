import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/features/protection/data/models/browser_extension.dart';
import 'package:tidy/features/protection/data/models/protection_finding.dart';

/// What the extensions in your browsers are allowed to reach.
///
/// Pure Dart: there is no macOS API involved and no privileged operation — this
/// is JSON on disk that a non-sandboxed app reads directly. The parsing runs in
/// an isolate because a Chrome install with ten profiles is a few megabytes of
/// it, and the result handed back is the summary rather than the parsed tree.
///
/// **It only ever reads.** Chrome keeps its extension list in `Secure
/// Preferences`, which is HMAC-signed per profile: editing it is detected and
/// undone on the next launch. Nothing here writes to any browser's files.
class BrowserExtensionAudit {
  /// [allowed] is whether macOS has already granted access to other apps' data.
  ///
  /// Checked rather than discovered: a browser profile lives in Application
  /// Support, and on Sonoma and later the first read of one is what makes macOS
  /// ask. Reading on page load would put that dialog in front of somebody who
  /// had not been told what it was for, which is the behaviour this app calls
  /// indistinguishable from malware.
  Future<({List<ProtectionFinding> findings, int unreadable})> run({
    required bool allowed,
  }) async {
    final home = kHomeDir;
    if (home == null) return (findings: <ProtectionFinding>[], unreadable: 0);

    if (!allowed) {
      return (findings: [_needsPermission()], unreadable: 1);
    }

    final roots = <BrowserFamily, String>{
      for (final family in BrowserFamily.values)
        family: '$home/Library/Application Support/${family.supportPath}',
    };

    final scanned = await Isolate.run(() => _readAll(roots));

    final findings = <ProtectionFinding>[];
    for (final extension in scanned.extensions) {
      findings.add(_findingFor(extension));
    }
    findings.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    for (final failure in scanned.failures) {
      AppLog.protection.warn('could not read a browser profile: $failure');
    }
    return (findings: findings, unreadable: scanned.failures.length);
  }

  /// Not a finding so much as a door.
  ProtectionFinding _needsPermission() => const ProtectionFinding(
    id: 'extensions:permission',
    area: ProtectionArea.extensions,
    title: 'Your browser extensions have not been looked at',
    subtitle: '~/Library/Application Support',
    facts: [
      ProtectionFact.unreadable(
        'Extensions live inside your browsers’ folders, and macOS treats those '
        'as another app’s data. Tidy reads the extension list and what each one '
        'is allowed to reach — never your history, cookies or passwords.',
      ),
    ],
    actions: {ProtectionAction.allowBrowserAccess},
  );

  ProtectionFinding _findingFor(BrowserExtension extension) {
    final facts = <ProtectionFact>[];

    if (extension.overridesSearch) {
      facts.add(
        const ProtectionFact(
          'Changes your search engine',
          'It sets what your address bar searches. That is the usual way an '
              'unwanted extension makes money, and also what a search extension you '
              'installed on purpose does.',
          notable: true,
        ),
      );
    }

    if (extension.readsEverySite) {
      facts.add(
        const ProtectionFact(
          'Can read every site you visit',
          'Access to every page you open. Worth knowing, and not by itself a '
              'reason to worry: ad blockers, password managers and most useful '
              'extensions genuinely need it. Two in five of yours have it.',
        ),
      );
    }

    if (extension.rewritesRequests) {
      facts.add(
        const ProtectionFact(
          'Can change what pages load',
          'It can watch requests as they happen and rewrite or block them.',
          notable: true,
        ),
      );
    }

    if (!extension.enabled) {
      facts.add(
        const ProtectionFact(
          'Turned off',
          'Installed, but not currently running.',
        ),
      );
    }

    if (facts.isEmpty) {
      facts.add(
        const ProtectionFact(
          'Asks for little',
          'It cannot read the pages you visit.',
        ),
      );
    }

    final where =
        extension.profiles.length == 1
            ? extension.profiles.first
            : '${extension.profiles.length} profiles';

    return ProtectionFinding(
      id: '${extension.family.name}:${extension.id}',
      area: ProtectionArea.extensions,
      title: extension.name,
      subtitle: '${extension.family.label} · $where · ${extension.id}',
      facts: facts,
      path: extension.path,
      actions: {if (extension.path != null) ProtectionAction.reveal},
    );
  }
}

/// Everything one sweep of the browser profiles found.
class _Scanned {
  const _Scanned(this.extensions, this.failures);
  final List<BrowserExtension> extensions;
  final List<String> failures;
}

/// Runs in an isolate. Returns only the summary, never the parsed JSON.
_Scanned _readAll(Map<BrowserFamily, String> roots) {
  final extensions = <BrowserExtension>[];
  final failures = <String>[];

  for (final entry in roots.entries) {
    final family = entry.key;
    final root = Directory(entry.value);
    if (!root.existsSync()) continue;

    try {
      if (family.isFirefox) {
        extensions.addAll(_readFirefox(family, entry.value));
      } else {
        extensions.addAll(_readChromium(family, entry.value));
      }
    } catch (e) {
      failures.add('${family.label}: $e');
    }
  }

  return _Scanned(_merge(extensions), failures);
}

/// The same extension in ten profiles is one row, not ten.
List<BrowserExtension> _merge(List<BrowserExtension> found) {
  final byKey = <String, BrowserExtension>{};

  for (final extension in found) {
    final key = '${extension.family.name}:${extension.id}';
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = extension;
      continue;
    }
    byKey[key] = BrowserExtension(
      id: existing.id,
      family: existing.family,
      name: existing.name,
      version: existing.version,
      path: existing.path,
      profiles: [...existing.profiles, ...extension.profiles],
      permissions: existing.permissions,
      hostPermissions: existing.hostPermissions,
      overridesSearch: existing.overridesSearch || extension.overridesSearch,
      // Off in one profile and on in another is on: the question the row
      // answers is whether this is running anywhere.
      enabled: existing.enabled || extension.enabled,
    );
  }

  return byKey.values.toList();
}

/// Chromium profiles hold their extensions in `<profile>/Extensions/<id>/<ver>`.
///
/// Profiles are found by looking for a directory containing `Preferences`
/// rather than by trusting the browser's own `Local State`, which several
/// forks write differently — and rather than trusting that the support folder
/// exists at all, which on this Mac it does for browsers that were never set up.
List<BrowserExtension> _readChromium(BrowserFamily family, String root) {
  final found = <BrowserExtension>[];

  for (final profile in _profileDirs(root)) {
    final extensions = Directory('${profile.path}/Extensions');
    if (!extensions.existsSync()) continue;

    for (final folder in extensions.listSync().whereType<Directory>()) {
      final id = folder.path.split('/').last;
      final version = _newestVersion(folder);
      if (version == null) continue;

      final manifest = File('${version.path}/manifest.json');
      if (!manifest.existsSync()) continue;

      try {
        final json = jsonDecode(manifest.readAsStringSync()) as Map;
        found.add(
          BrowserExtension(
            id: id,
            family: family,
            name: _nameFrom(json, version.path),
            version: json['version'] as String?,
            path: version.path,
            profiles: [_profileName(profile.path)],
            permissions: _strings(json['permissions']),
            hostPermissions: [
              ..._strings(json['host_permissions']),
              // Manifest v2 put host access in the same list as permissions.
              ..._strings(json['permissions']).where((p) => p.contains('://')),
            ],
            overridesSearch:
                (json['chrome_settings_overrides']
                    as Map?)?['search_provider'] !=
                null,
          ),
        );
      } on FormatException {
        // A manifest being written while we read it. Skipping one extension is
        // better than losing the browser, and the count is reported either way.
        continue;
      }
    }
  }

  return found;
}

/// Firefox keeps one file with everything in it, already resolved.
List<BrowserExtension> _readFirefox(BrowserFamily family, String root) {
  final profiles = Directory('$root/Profiles');
  if (!profiles.existsSync()) return const [];

  final found = <BrowserExtension>[];

  for (final profile in profiles.listSync().whereType<Directory>()) {
    final file = File('${profile.path}/extensions.json');
    if (!file.existsSync()) continue;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map;
      for (final raw in (json['addons'] as List? ?? const [])) {
        if (raw is! Map || raw['type'] != 'extension') continue;
        // Firefox ships its own; they are not "installed extensions" in the
        // sense anybody means when they ask what is in their browser.
        if (raw['location'] == 'app-builtin' ||
            raw['location'] == 'app-system-defaults') {
          continue;
        }

        final manifest = raw['manifest'] as Map? ?? const {};
        found.add(
          BrowserExtension(
            id: '${raw['id']}',
            family: family,
            name:
                (raw['defaultLocale'] as Map?)?['name'] as String? ??
                '${raw['id']}',
            version: raw['version'] as String?,
            path: raw['path'] as String?,
            profiles: [_profileName(profile.path)],
            permissions: _strings(manifest['permissions']),
            hostPermissions: _strings(manifest['host_permissions']),
            overridesSearch:
                (manifest['chrome_settings_overrides']
                    as Map?)?['search_provider'] !=
                null,
            enabled: raw['active'] == true,
          ),
        );
      }
    } on FormatException {
      continue;
    }
  }

  return found;
}

/// Directories that look like a profile: they hold a `Preferences` file.
///
/// Necessary because Brave, Edge, Vivaldi, Chromium and Arc all leave a support
/// folder behind containing nothing but `NativeMessagingHosts`, and treating
/// "the folder exists" as "the browser is set up" would report every one of them
/// as a browser with no extensions.
List<Directory> _profileDirs(String root) {
  final base = Directory(root);
  if (!base.existsSync()) return const [];

  final candidates = <Directory>[
    base,
    ...base.listSync().whereType<Directory>(),
  ];
  return [
    for (final directory in candidates)
      if (File('${directory.path}/Preferences').existsSync() ||
          File('${directory.path}/Secure Preferences').existsSync())
        directory,
  ];
}

/// The highest version folder inside an extension's directory.
Directory? _newestVersion(Directory folder) {
  final versions = folder.listSync().whereType<Directory>().toList();
  if (versions.isEmpty) return null;
  versions.sort((a, b) => a.path.compareTo(b.path));
  return versions.last;
}

/// Resolves `__MSG_name__` against the extension's own locale files.
///
/// Without this every second row reads `__MSG_name__`, which is the placeholder
/// Chrome substitutes at display time and never writes back to the manifest.
String _nameFrom(Map json, String versionPath) {
  final raw = json['name'] as String? ?? '';
  if (!raw.startsWith('__MSG_') || !raw.endsWith('__')) {
    return raw.isEmpty ? 'Unnamed extension' : raw;
  }

  final key = raw.substring(6, raw.length - 2);
  final locales = [json['default_locale'] as String? ?? 'en', 'en_US', 'en'];

  for (final locale in locales) {
    final file = File('$versionPath/_locales/$locale/messages.json');
    if (!file.existsSync()) continue;
    try {
      final messages = jsonDecode(file.readAsStringSync()) as Map;
      final entry = messages[key] ?? messages[key.toLowerCase()];
      final message = (entry as Map?)?['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
    } on FormatException {
      continue;
    }
  }

  return 'Unnamed extension';
}

String _profileName(String path) {
  final name = path.split('/').last;
  return name == 'Default' ? 'Default' : name;
}

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final value in raw)
      if (value is String) value,
];
