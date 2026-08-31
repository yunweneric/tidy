import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy/features/protection/data/services/path_safety.dart';

/// The only tests in this repo, and `docs/feature.md` §6 says why: these
/// predicates decide what Protection is allowed to hand to a delete, and they
/// are the one part of the module that can lose somebody a file.
void main() {
  const home = '/Users/someone';

  group('isActionableLaunchAgent', () {
    test('accepts a plist directly inside each of the three roots', () {
      for (final root in launchAgentRoots(home)) {
        expect(
          isActionableLaunchAgent('$root/com.example.agent.plist', home: home),
          isTrue,
          reason: root,
        );
      }
    });

    test('refuses anything that is not a plist', () {
      expect(
        isActionableLaunchAgent('$home/Library/LaunchAgents/agent', home: home),
        isFalse,
      );
      expect(
        isActionableLaunchAgent(
          '$home/Library/LaunchAgents/agent.plist.bak',
          home: home,
        ),
        isFalse,
      );
    });

    test('refuses a path that climbs out of a root', () {
      expect(
        isActionableLaunchAgent(
          '$home/Library/LaunchAgents/../../../etc/passwd.plist',
          home: home,
        ),
        isFalse,
      );
      // The resolved form lands in /Library/Preferences, not a launchd root.
      expect(
        isActionableLaunchAgent(
          '/Library/LaunchAgents/../Preferences/com.example.plist',
          home: home,
        ),
        isFalse,
      );
    });

    test('refuses macOS’s own launchd folders', () {
      expect(
        isActionableLaunchAgent(
          '/System/Library/LaunchDaemons/com.apple.something.plist',
          home: home,
        ),
        isFalse,
      );
      expect(
        isActionableLaunchAgent(
          '/System/Library/LaunchAgents/com.apple.something.plist',
          home: home,
        ),
        isFalse,
      );
    });

    test('refuses something nested deeper than an immediate child', () {
      expect(
        isActionableLaunchAgent(
          '/Library/LaunchDaemons/vendor/com.example.plist',
          home: home,
        ),
        isFalse,
      );
    });

    test('refuses another user’s folder', () {
      expect(
        isActionableLaunchAgent(
          '/Users/someone-else/Library/LaunchAgents/com.example.plist',
          home: home,
        ),
        isFalse,
      );
    });
  });

  group('isActionableExtension', () {
    const support = '/Users/someone/Library/Application Support/Google/Chrome';

    test('accepts a version folder inside a profile’s Extensions', () {
      expect(
        isActionableExtension(
          '$support/Default/Extensions/abcdefghijklmnop/1.2.3_0',
          supportRoot: support,
        ),
        isTrue,
      );
    });

    test('refuses the profile itself', () {
      expect(
        isActionableExtension('$support/Default', supportRoot: support),
        isFalse,
      );
      expect(isActionableExtension(support, supportRoot: support), isFalse);
    });

    test('refuses the Extensions folder itself', () {
      expect(
        isActionableExtension(
          '$support/Default/Extensions',
          supportRoot: support,
        ),
        isFalse,
      );
    });

    test('refuses a path outside the browser’s support root', () {
      expect(
        isActionableExtension(
          '/Users/someone/Documents/Extensions/abc/1.0',
          supportRoot: support,
        ),
        isFalse,
      );
      expect(
        isActionableExtension(
          '$support/../../../Extensions/abc/1.0',
          supportRoot: support,
        ),
        isFalse,
      );
    });
  });

  group('crossesSymlink', () {
    late Directory scratch;

    // Resolved, because on macOS `Directory.systemTemp` sits under `/var`,
    // which is itself a symlink to `/private/var` — so an unresolved temp path
    // genuinely does cross one, and the test would be asserting the opposite of
    // what it means to.
    setUp(() {
      final temp = Directory.systemTemp.createTempSync('tidy-paths');
      scratch = Directory(temp.resolveSymbolicLinksSync());
    });
    tearDown(() => scratch.deleteSync(recursive: true));

    test('is false for a plain directory', () {
      final real = Directory('${scratch.path}/LaunchAgents')..createSync();
      File('${real.path}/com.example.plist').writeAsStringSync('');
      expect(crossesSymlink('${real.path}/com.example.plist'), isFalse);
    });

    test('is true when a parent is a link', () {
      final real = Directory('${scratch.path}/real')..createSync();
      File('${real.path}/com.example.plist').writeAsStringSync('');
      Link('${scratch.path}/LaunchAgents').createSync(real.path);
      expect(
        crossesSymlink('${scratch.path}/LaunchAgents/com.example.plist'),
        isTrue,
      );
    });

    test('is true when the file itself is a link', () {
      final target = File('${scratch.path}/target.plist')
        ..writeAsStringSync('');
      Link('${scratch.path}/link.plist').createSync(target.path);
      expect(crossesSymlink('${scratch.path}/link.plist'), isTrue);
    });
  });
}
