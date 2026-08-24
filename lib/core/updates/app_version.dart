import 'package:flutter/foundation.dart';

/// A version number, comparable.
///
/// Everything this parses comes from somewhere the app does not control: a git
/// tag someone typed, a `CFBundleShortVersionString` read back from a bundle,
/// the `tag_name` on a GitHub release. So [parse] returns null rather than
/// throwing — a release tagged `nightly` should make the update check decide
/// there is nothing to install, not take down a background timer.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;

  /// The `+45` half of `1.2.3+45`, and the tiebreak when two versions carry the
  /// same three numbers. Absent means zero, so `1.2.3` and `1.2.3+0` are equal.
  final int build;

  /// Accepts `1.2.3`, `v1.2.3`, `1.2.3+45` and `1.2` (missing parts are zero).
  ///
  /// Anything with a non-numeric component — `1.2.3-beta.1`, `nightly` — is
  /// rejected outright. Pre-release ordering is a genuinely subtle corner of
  /// semver, and the app publishes plain three-number releases; guessing at it
  /// would be a way to install a beta over a stable build by accident.
  static AppVersion? parse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

    var build = 0;
    final plus = text.indexOf('+');
    if (plus >= 0) {
      final parsed = int.tryParse(text.substring(plus + 1));
      if (parsed == null) return null;
      build = parsed;
      text = text.substring(0, plus);
    }

    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }

    return AppVersion(numbers[0], numbers[1], numbers[2], build);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  /// Without the build number: what a user should see. The build is an
  /// implementation detail of the store listing, not a thing to read out.
  String get display => '$major.$minor.$patch';

  @override
  String toString() => build == 0 ? display : '$display+$build';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}
