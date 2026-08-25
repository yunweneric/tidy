/// Where the app lives on GitHub, in one place.
///
/// `core/updates/github_release_client.dart` holds the same slug for the in-app
/// updater, but it is not importable here — it is built on `dart:io`, which
/// does not compile for web. This is the landing page's copy; the slug is the
/// only thing duplicated, and it is the one part that will never change.
class TidyRepo {
  const TidyRepo._();

  static const String owner = 'yunweneric';
  static const String name = 'tidy';
  static const String slug = '$owner/$name';

  static const String url = 'https://github.com/$slug';
  static const String releases = '$url/releases';
  static const String latestRelease = '$releases/latest';
  static const String issues = '$url/issues';
  static const String license = '$url/blob/main/LICENSE';
  static const String readme = '$url#readme';

  /// Public, unauthenticated and CORS-enabled, which is exactly why the
  /// download button resolves *releases* rather than Actions artifacts —
  /// artifact downloads need a token a public page cannot carry.
  static const String api = 'https://api.github.com/repos/$slug';

  /// Where the site itself is served from. Absolute because Open Graph tags
  /// and the clone snippet both need a real URL.
  static const String site = 'https://tidy.yunweneric.com';
}
