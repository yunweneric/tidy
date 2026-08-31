/// The predicates that decide what Protection is allowed to touch.
///
/// Pure functions in a file of their own because they are the only code in this
/// module that can lose somebody a file, and `docs/feature.md` §6 asks for
/// exactly that to be testable — see `test/protection/path_safety_test.dart`.
///
/// They are a second line, not the only one: every removal still goes through
/// `SystemBridge.trashItems`, whose native `isRemovable` guard refuses the
/// dangerous roots regardless of what is asked here. These exist so a bug in
/// this module is caught before it reaches that guard, rather than relying on
/// it.
library;

import 'dart:io';

/// The three folders whose launchd jobs this app reads.
///
/// `/System/Library/Launch*` is deliberately not among them — those are macOS
/// itself, they are protected by SIP, and an app that offers to remove them is
/// offering something it cannot do to something nobody should.
List<String> launchAgentRoots(String home) => [
  '$home/Library/LaunchAgents',
  '/Library/LaunchAgents',
  '/Library/LaunchDaemons',
];

/// Whether [path] is a launchd plist this module may act on.
///
/// Everything is required: inside one of the three roots, an immediate child of
/// it rather than something nested deeper, and named `*.plist`. A path that
/// climbs out with `..`, or arrives already normalised somewhere else, fails on
/// the first test because the comparison is done against the resolved form.
bool isActionableLaunchAgent(String path, {required String home}) {
  final resolved = _normalise(path);
  if (!resolved.endsWith('.plist')) return false;

  final parent = resolved.substring(0, resolved.lastIndexOf('/'));
  return launchAgentRoots(home).any((root) => parent == _normalise(root));
}

/// Whether [path] is an extension folder inside a browser profile we read.
///
/// The shape is `<support>/<browser>/…/Extensions/<id>/<version>`, and the test
/// is that the path sits under the given browser support root *and* has an
/// `Extensions` component. Without the second test, a bug that handed this a
/// profile root would happily offer to remove the entire profile.
bool isActionableExtension(String path, {required String supportRoot}) {
  final resolved = _normalise(path);
  final root = _normalise(supportRoot);
  if (!resolved.startsWith('$root/')) return false;

  final parts = resolved.substring(root.length + 1).split('/');
  final index = parts.indexOf('Extensions');
  // At least an id after `Extensions`, and never `Extensions` itself.
  return index != -1 && parts.length > index + 1;
}

/// True when any component of [path] is a symlink.
///
/// A symlinked root is skipped rather than followed: trashing a link removes the
/// link and frees nothing, and following one leaves the roots above meaning
/// nothing at all.
bool crossesSymlink(String path) {
  var walked = '';
  for (final part in _normalise(path).split('/')) {
    if (part.isEmpty) continue;
    walked = '$walked/$part';
    final type = FileSystemEntity.typeSync(walked, followLinks: false);
    if (type == FileSystemEntityType.link) return true;
    if (type == FileSystemEntityType.notFound) return false;
  }
  return false;
}

/// Collapses `.` and `..`, strips trailing and doubled slashes.
///
/// Done by hand rather than with `File(path).absolute` so it is pure — these
/// predicates have to be answerable without touching the disk, or they cannot
/// be tested for the cases that matter, which are the ones where the path does
/// not exist.
String _normalise(String path) {
  final rooted = path.startsWith('/');
  final parts = <String>[];

  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (!rooted) {
        parts.add('..');
      }
      continue;
    }
    parts.add(part);
  }

  return '${rooted ? '/' : ''}${parts.join('/')}';
}
