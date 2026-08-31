/// A browser whose extensions can be read from disk.
///
/// Safari is deliberately absent. Its extensions are app bundles installed from
/// the App Store rather than folders in a profile, and its settings live in
/// `~/Library/Safari`, which macOS will not let Tidy read. Half-covering it
/// would be worse than not listing it — the page says so out loud instead.
enum BrowserFamily {
  chrome('Chrome', 'Google/Chrome', 'com.google.Chrome'),
  brave('Brave', 'BraveSoftware/Brave-Browser', 'com.brave.Browser'),
  edge('Edge', 'Microsoft Edge', 'com.microsoft.edgemac'),
  firefox('Firefox', 'Firefox', 'org.mozilla.firefox');

  const BrowserFamily(this.label, this.supportPath, this.bundleId);

  final String label;

  /// Relative to `~/Library/Application Support`.
  final String supportPath;

  /// So the page can tell whether the browser is running before offering to
  /// touch anything inside its profile.
  final String bundleId;

  bool get isFirefox => this == BrowserFamily.firefox;
}

/// One extension, gathered across every profile it appears in.
///
/// Gathered rather than listed per profile because ten Chrome profiles times
/// sixty-five extensions is six hundred and fifty rows, and the same ad
/// blocker appearing ten times is one fact, not ten.
class BrowserExtension {
  const BrowserExtension({
    required this.id,
    required this.family,
    required this.name,
    required this.profiles,
    this.version,
    this.path,
    this.permissions = const [],
    this.hostPermissions = const [],
    this.overridesSearch = false,
    this.enabled = true,
  });

  /// The extension id — `aapbdbdomjkkjkaonfhkkikfgjllcleb` — which is what the
  /// browser's own extensions page shows, so it is what a reader can match on.
  final String id;

  final BrowserFamily family;
  final String name;
  final String? version;

  /// Where it lives, for revealing. The newest version's folder.
  final String? path;

  /// The profile names it is installed in.
  final List<String> profiles;

  final List<String> permissions;
  final List<String> hostPermissions;

  /// It declares a `chrome_settings_overrides.search_provider`, which is how an
  /// extension changes what your address bar searches.
  final bool overridesSearch;

  final bool enabled;

  /// Can read and change everything on every site.
  bool get readsEverySite =>
      hostPermissions.any(
        (host) => host == '<all_urls>' || host == '*://*/*',
      ) ||
      permissions.any((name) => name == '<all_urls>' || name == 'tabs') &&
          hostPermissions.isEmpty &&
          permissions.contains('webRequest');

  /// Can watch, and rewrite, requests as they happen.
  bool get rewritesRequests =>
      permissions.contains('webRequestBlocking') ||
      (permissions.contains('webRequest') &&
          permissions.contains('declarativeNetRequest'));
}
