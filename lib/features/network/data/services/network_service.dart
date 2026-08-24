import 'package:tidy/core/platform/action_outcome.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/network/data/models/network_prefs.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/core/models/network_series.dart';
import 'package:tidy/features/network/data/services/network_bridge.dart';

/// Reads the native monitor, and keeps the native side's settings in step with
/// the user's.
///
/// A singleton rather than a per-page instance, matching `ClipboardService`: it
/// caches the ranges the user has already looked at, and both the page and the
/// menu bar popover reach it.
class NetworkService {
  /// The ranges already fetched this session. A year's chart does not change
  /// between two clicks on the tab bar, and re-reading the whole daily tier for
  /// every switch makes the segmented control feel slow.
  ///
  /// Invalidated on refresh and whenever a new bucket could have closed — see
  /// [invalidate].
  final Map<NetworkRange, NetworkSeries> _cache = {};

  AppSettings? _settings;
  NetworkPrefs? _pushed;

  /// One reading a second while a subscriber has the tap open.
  Stream<NetworkSample> get onSample => NetworkBridge.onSample;

  Future<NetworkSample> startLive() => NetworkBridge.startLive();

  Future<void> stopLive() => NetworkBridge.stopLive();

  Future<NetworkSample> live() => NetworkBridge.live();

  Future<NetworkHeadline> headline() => NetworkBridge.headline();

  Future<NetworkSeries> series(NetworkRange range, {bool refresh = false}) async {
    if (!refresh) {
      final cached = _cache[range];
      if (cached != null) return cached;
    }
    final series = await NetworkBridge.history(range);
    return _cache[range] = series;
  }

  void invalidate() => _cache.clear();

  Future<ActionOutcome> reset() async {
    final outcome = await NetworkBridge.reset();
    if (outcome.ok) invalidate();
    return outcome;
  }

  /// Mirrors the user's settings into the native store, now and on every
  /// change.
  ///
  /// One funnel, for the reason `ClipboardService.bindTo` gives: a setter that
  /// forgot to push would leave the menu bar in a style the user had already
  /// changed away from.
  void bindTo(AppSettings settings) {
    if (identical(_settings, settings)) return;
    _settings?.removeListener(_syncPrefs);
    _settings = settings;
    settings.addListener(_syncPrefs);
    _syncPrefs();
  }

  void _syncPrefs() {
    final settings = _settings;
    if (settings == null) return;

    // AppSettings notifies for every preference, theme included, so only a real
    // change to the network ones is worth a channel round trip.
    final prefs = NetworkPrefs.from(settings);
    if (prefs == _pushed) return;
    _pushed = prefs;
    NetworkBridge.configure(prefs);
  }
}
