import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/updates/app_version.dart';
import 'package:tidy/core/updates/github_release_client.dart';
import 'package:tidy/core/updates/update_bridge.dart';
import 'package:tidy/core/updates/update_release.dart';

/// Why a check produced nothing to install.
enum UpdateCheckOutcome {
  /// A newer release exists. [UpdateCheckResult.release] is set.
  available,

  /// Asked, and this is the newest there is.
  upToDate,

  /// Did not ask: the user turned automatic checks off, or the last check was
  /// recent enough that asking again would be noise.
  skipped,

  /// Asked and could not tell — offline, rate-limited, GitHub down.
  unreachable,
}

class UpdateCheckResult {
  const UpdateCheckResult(this.outcome, {this.release});

  final UpdateCheckOutcome outcome;
  final UpdateRelease? release;
}

/// Finding, fetching and handing off an update.
///
/// The split between this and `Updater.swift` is deliberate: everything up to
/// and including "there is a file on disk" happens here, because that is where
/// progress can be streamed into a bloc; everything from "is this file real"
/// onwards happens natively, because verifying a signature and exchanging a
/// running bundle are not things Dart can do truthfully.
class UpdateService {
  UpdateService({required AppSettings settings, GitHubReleaseClient? client})
    : _settings = settings,
      _client = client ?? GitHubReleaseClient();

  final AppSettings _settings;
  final GitHubReleaseClient _client;

  /// How stale a check has to be before a background trigger repeats it.
  ///
  /// Half an hour, not a day. A day meant that a release published at 10am was
  /// invisible until the following morning if the app had happened to check at
  /// 9am — so in practice the only thing that ever surfaced an update was
  /// pressing the button in Settings, which bypasses this gate.
  ///
  /// The cost of the shorter window is one conditional GET against the GitHub
  /// releases API at most twice an hour. The unauthenticated limit is sixty an
  /// hour per address, so this spends about three per cent of it.
  static const Duration checkInterval = Duration(minutes: 30);

  AppBundleInfo? _bundle;
  StreamSubscription<List<int>>? _download;

  /// Completed by whichever of `onDone`, `onError` or [cancelDownload] gets
  /// there first. Held as a field precisely so cancelling can settle it:
  /// `StreamSubscription.cancel` fires neither callback, so without this a
  /// cancelled download would leave the awaiting caller hanging forever.
  Completer<File?>? _pending;

  /// The scratch directory the download is written into, tracked separately
  /// from [_downloaded] because a cancelled or failed download leaves a partial
  /// file behind and never sets that.
  Directory? _workDir;
  File? _downloaded;
  String? _staged;

  /// Version, build and install location of the running app, read once.
  Future<AppBundleInfo> bundle() async =>
      _bundle ??= await SystemBridge.appVersion();

  Future<AppVersion> currentVersion() async =>
      AppVersion.parse((await bundle()).version) ?? const AppVersion(0, 0, 0);

  /// Asks GitHub whether there is anything newer.
  ///
  /// [manual] bypasses both gates — the user pressing a button has said what
  /// they want more clearly than a preference can.
  Future<UpdateCheckResult> check({bool manual = false}) async {
    if (!manual) {
      if (!_settings.updateChecksEnabled) {
        return const UpdateCheckResult(UpdateCheckOutcome.skipped);
      }
      final last = _settings.lastUpdateCheckAt;
      if (last != null && DateTime.now().difference(last) < checkInterval) {
        return const UpdateCheckResult(UpdateCheckOutcome.skipped);
      }
    }

    final current = await currentVersion();
    final release = await _client.latest(currentVersion: current.display);

    // Recorded only when the request actually came back with something.
    //
    // This is what the comment here always claimed and what the condition did
    // not do: `|| !manual` made *every* background check stamp the clock,
    // including one that could not reach GitHub at all. So a single failure —
    // launching on a train, DNS not up yet at login, a flaky minute — recorded
    // "checked just now" and shut every later background check out for the
    // whole interval, however long that interval was. Nothing recovered it but
    // the button in Settings.
    //
    // A failed check has not checked. Leaving the clock alone lets the next
    // trigger try again.
    if (release != null) {
      _settings.lastUpdateCheckAt = DateTime.now();
    }

    if (release == null) {
      return const UpdateCheckResult(UpdateCheckOutcome.unreachable);
    }
    if (release.version <= current) {
      AppLog.updates.debug(
        'no newer release',
        fields: {'current': current.display, 'latest': release.version.display},
      );
      return UpdateCheckResult(UpdateCheckOutcome.upToDate, release: release);
    }

    AppLog.updates.info(
      'update available',
      fields: {'current': current.display, 'latest': release.version.display},
    );
    return UpdateCheckResult(UpdateCheckOutcome.available, release: release);
  }

  /// Streams the release zip to a temporary file, reporting bytes as they land.
  ///
  /// Returns the file, or null if it failed or was cancelled. Progress is
  /// reported against the size GitHub published rather than the response's own
  /// `content-length`, so the bar is determinate from the first byte — the
  /// asset URL redirects to object storage and the first response has no body
  /// length at all.
  Future<File?> download(
    UpdateRelease release, {
    required void Function(int received, int total) onProgress,
  }) async {
    await cancelDownload();

    final dir = Directory(
      p.join(Directory.systemTemp.path, 'tidy-update-${release.version}'),
    );
    final file = File(p.join(dir.path, p.basename(release.zipUrl.path)));

    final completer = Completer<File?>();
    _pending = completer;
    IOSink? sink;
    HttpClient? client;

    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      _workDir = dir;

      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(release.zipUrl);
      request.headers.set(HttpHeaders.userAgentHeader, 'Tidy (macOS)');
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        AppLog.updates.warn(
          'the update download was refused',
          fields: {'status': response.statusCode},
        );
        client.close(force: true);
        _pending = null;
        return null;
      }

      final total =
          release.zipBytes > 0
              ? release.zipBytes
              : (response.contentLength > 0 ? response.contentLength : 0);
      var received = 0;
      sink = file.openWrite();

      _download = response.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        },
        onDone: () async {
          await sink?.close();
          client?.close();
          _download = null;
          _pending = null;
          _downloaded = file;
          AppLog.updates.info(
            'update downloaded',
            fields: {'bytes': received, 'version': release.version.display},
          );
          if (!completer.isCompleted) completer.complete(file);
        },
        onError: (Object e) async {
          await sink?.close();
          client?.close(force: true);
          _download = null;
          _pending = null;
          AppLog.updates.failed('download the update', e);
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );
    } catch (e) {
      await sink?.close();
      client?.close(force: true);
      _download = null;
      _pending = null;
      AppLog.updates.failed('download the update', e);
      return null;
    }

    return completer.future;
  }

  /// Stops an in-flight download.
  Future<void> cancelDownload() async {
    final subscription = _download;
    _download = null;
    if (subscription != null) await subscription.cancel();

    // Settle the future `download` handed out. `cancel` fires neither `onDone`
    // nor `onError`, so this is the only thing that unblocks the caller.
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  /// Hands the downloaded zip to the native side to be checked and staged.
  Future<PreparedUpdate> prepare(UpdateRelease release) async {
    final file = _downloaded;
    if (file == null || !file.existsSync()) {
      return const PreparedUpdate(
        ok: false,
        message: 'The downloaded update is no longer on disk.',
      );
    }

    final prepared = await UpdateBridge.prepare(
      zipPath: file.path,
      expectedSha256: release.sha256,
    );
    if (prepared.ok) _staged = prepared.stagedPath;
    return prepared;
  }

  /// Swaps the staged bundle in and relaunches. Returns a message on failure;
  /// on success the app is already on its way out.
  Future<String?> install() async {
    final staged = _staged;
    if (staged == null) {
      return 'There is no prepared update to install.';
    }
    return UpdateBridge.install(staged);
  }

  /// Throws away the download and anything staged from it.
  Future<void> discard() async {
    await cancelDownload();

    final staged = _staged;
    _staged = null;
    if (staged != null) await UpdateBridge.discard(staged);

    _downloaded = null;
    final dir = _workDir;
    _workDir = null;
    if (dir == null) return;
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      AppLog.updates.failed('remove the downloaded update', e);
    }
  }

  void dispose() {
    unawaited(cancelDownload());
    _client.close();
  }
}
