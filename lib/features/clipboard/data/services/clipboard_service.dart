import 'dart:typed_data';

import 'package:mac_uninstaller/core/platform/action_outcome.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/features/clipboard/data/models/clipboard_entry.dart';
import 'package:mac_uninstaller/features/clipboard/data/models/clipboard_prefs.dart';
import 'package:mac_uninstaller/features/clipboard/data/services/clipboard_bridge.dart';

/// Reads the native clipboard history and keeps the native side's settings in
/// step with the user's.
///
/// A singleton rather than a per-page instance, for the same reason the
/// Performance services are: it holds an image cache, and rebuilding that every
/// time the user switches pages is visible.
class ClipboardService {
  /// Decoded image bytes, keyed by entry id.
  ///
  /// Bounded, because a history full of screenshots would otherwise be held
  /// twice — once on disk, once here. Oldest-fetched goes first; it is a cache
  /// for what is on screen, and what is on screen was fetched recently.
  static const int _maxCachedBlobs = 40;

  final Map<String, Uint8List> _blobs = {};

  AppSettings? _settings;
  ClipboardPrefs? _pushed;

  /// Fires whenever the native store changes.
  Stream<void> get onChanged => ClipboardBridge.onChanged;

  Future<List<ClipboardEntry>> history() async {
    final raw = await ClipboardBridge.history();
    return raw.map(ClipboardEntry.fromMap).toList();
  }

  /// The image bytes for an entry, or null if its content has been cleared.
  Future<Uint8List?> imageBytes(ClipboardEntry entry) async {
    if (!entry.hasBlob) return null;
    final cached = _blobs[entry.id];
    if (cached != null) return cached;

    final bytes = await ClipboardBridge.blob(entry.id);
    if (bytes == null) return null;

    if (_blobs.length >= _maxCachedBlobs) {
      _blobs.remove(_blobs.keys.first);
    }
    return _blobs[entry.id] = bytes;
  }

  /// The whole text, including the part that was too long to keep inline.
  Future<String?> fullText(ClipboardEntry entry) async {
    if (entry.text != null) return entry.text;
    return ClipboardBridge.fullText(entry.id);
  }

  Future<ActionOutcome> copyToClipboard(ClipboardEntry entry) =>
      ClipboardBridge.copyToPasteboard(entry.id);

  Future<ActionOutcome> setPinned(ClipboardEntry entry, {required bool pinned}) =>
      ClipboardBridge.setPinned(entry.id, pinned: pinned);

  Future<ActionOutcome> delete(List<String> ids) {
    ids.forEach(_blobs.remove);
    return ClipboardBridge.delete(ids);
  }

  Future<ActionOutcome> clear({required bool keepPinned}) {
    _blobs.clear();
    return ClipboardBridge.clear(keepPinned: keepPinned);
  }

  Future<ActionOutcome> revealSource(ClipboardEntry entry) =>
      ClipboardBridge.revealSource(entry.id);

  /// Mirrors the user's settings into the native store, now and on every
  /// change.
  ///
  /// One funnel on purpose. Every clipboard preference has to reach Swift, and
  /// a setter that forgot to push would leave the recorder running to limits
  /// the user had already changed — the kind of bug that shows up as "it kept
  /// something I told it not to".
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
    // change to the clipboard ones is worth a channel round trip.
    final prefs = ClipboardPrefs.from(settings);
    if (prefs == _pushed) return;
    _pushed = prefs;
    ClipboardBridge.configure(prefs);
  }
}
