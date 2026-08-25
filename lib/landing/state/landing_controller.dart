import 'package:flutter/foundation.dart';
import 'package:tidy/landing/data/github_release.dart';
import 'package:tidy/landing/data/github_service.dart';

/// The page's slow-moving state: the appearance, and what GitHub has to say.
///
/// A plain [ChangeNotifier], deliberately: the app is built on bloc and
/// `get_it`, and reaching for either here would drag the service locator — and
/// with it every `dart:io` service it registers — into a web bundle whose only
/// job is to render a page.
///
/// Nothing that changes while scrolling lives here. `LandingApp` rebuilds the
/// whole `MaterialApp` when this notifies, which is the right cost for a theme
/// toggle and much too high for a scroll-spy — that state is a pair of
/// `ValueNotifier`s in `LandingPage`, read only by the navigation bar.
class LandingController extends ChangeNotifier {
  LandingController({GithubService? github})
    : _github = github ?? GithubService();

  final GithubService _github;

  /// Dark by default. Tidy is a utility you keep open beside your work, and
  /// dark is the appearance most of its screenshots and most of its users are
  /// in — the toggle is there for the rest.
  bool _isDark = true;
  bool get isDark => _isDark;

  ReleaseState _release = const ReleaseLoading();
  ReleaseState get release => _release;

  int? _stars;
  int? get stars => _stars;

  /// True when the visitor is already on the platform the app runs on. Flutter
  /// web derives this from the user agent, so it costs no JS interop of ours.
  bool get onMac => defaultTargetPlatform == TargetPlatform.macOS;

  /// The file a visitor most likely wants: the disk image, which is the first
  /// install. The archive is what the in-app updater fetches, and offering it
  /// first would hand people the harder path.
  ReleaseAsset? get suggestedAsset => switch (_release) {
    ReleaseReady(:final release) => release.assetFor(DownloadTarget.dmg),
    _ => null,
  };

  String? get version => switch (_release) {
    ReleaseReady(:final release) => release.version,
    _ => null,
  };

  Future<void> load({bool refresh = false}) async {
    if (refresh) _release = const ReleaseLoading();
    notifyListeners();

    _release = await _github.latestRelease(refresh: refresh);
    if (_disposed) return;
    // Notified before the star count is asked for: the download buttons are
    // the point of the page and should not wait on a decoration.
    notifyListeners();

    final stars = await _github.stars();
    if (_disposed || stars == null) return;
    _stars = stars;
    notifyListeners();
  }

  void toggleBrightness() {
    _isDark = !_isDark;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _github.dispose();
    super.dispose();
  }
}
