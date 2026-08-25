import 'package:flutter/widgets.dart';
import 'package:tidy/core/design/design.dart';

/// The kinds of file a Tidy release carries.
///
/// One platform, two shapes plus a manifest. `scripts/build_dmg.sh` names them,
/// `.github/workflows/ci.yml` uploads them, and the in-app updater looks for
/// the zip by exactly that name — so this enum is a reading of an existing
/// contract rather than a new one.
enum DownloadTarget {
  dmg(
    label: 'Disk image',
    detail: 'A first install — drag Tidy to Applications',
    icon: AppIcons.downloads,
  ),
  zip(
    label: 'Archive',
    detail: 'What the in-app updater downloads',
    icon: AppIcons.archive,
  ),
  checksums(
    label: 'Checksums',
    detail: 'Verify what you downloaded before you open it',
    icon: AppIcons.protection,
  );

  const DownloadTarget({
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String detail;
  final IconData icon;

  /// True for the files a visitor actually installs, as opposed to the
  /// manifest they check them against.
  bool get isInstallable => this != DownloadTarget.checksums;

  /// Which target [filename] is, or null for anything not worth listing.
  ///
  /// Returning null rather than a fallback is deliberate: a release picks up
  /// source archives and, if a build leg ever changes, files this page has
  /// never heard of. An unknown asset is dropped, not guessed at.
  static DownloadTarget? classify(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.dmg')) return DownloadTarget.dmg;
    if (name.endsWith('-macos.zip')) return DownloadTarget.zip;
    if (name == 'sha256sums.txt') return DownloadTarget.checksums;
    return null;
  }
}

/// One downloadable file on a release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.target,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final DownloadTarget target;
  final String downloadUrl;
  final int sizeBytes;

  /// Null for anything [DownloadTarget.classify] does not recognise, so the
  /// caller can filter rather than render a row it has no words for.
  static ReleaseAsset? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final url = json['browser_download_url'];
    if (name is! String || url is! String) return null;

    final target = DownloadTarget.classify(name);
    if (target == null) return null;

    return ReleaseAsset(
      name: name,
      target: target,
      downloadUrl: url,
      sizeBytes: switch (json['size']) {
        final int size => size,
        _ => 0,
      },
    );
  }

  /// Megabytes, kilobytes, or bytes.
  ///
  /// `formatBytes` from the app would give MiB against a power-of-two divisor;
  /// a download size is conventionally decimal, and matching what the browser
  /// will say avoids a page that disagrees with the download it started.
  ///
  /// Bytes are spelt out rather than rounded, because SHA256SUMS.txt is a few
  /// hundred of them and "0 KB" beside a real file reads as a broken build.
  String get readableSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1000) return '$sizeBytes B';
    if (sizeBytes < 1000000) return '${(sizeBytes / 1000).round()} KB';
    return '${(sizeBytes / 1000000).toStringAsFixed(1)} MB';
  }
}

/// A published release, reduced to what the page shows.
@immutable
class GithubRelease {
  const GithubRelease({
    required this.tag,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  final String tag;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  /// The tag without its `v`, which is how the app reports its own version.
  String get version => tag.startsWith('v') ? tag.substring(1) : tag;

  bool get hasDownloads => assets.any((a) => a.target.isInstallable);

  ReleaseAsset? assetFor(DownloadTarget target) {
    for (final asset in assets) {
      if (asset.target == target) return asset;
    }
    return null;
  }

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December', //
  ];

  String get publishedLabel {
    final at = publishedAt;
    if (at == null) return '';
    return '${at.day} ${_months[at.month - 1]} ${at.year}';
  }

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final raw = json['assets'];
    final assets = <ReleaseAsset>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        final asset = ReleaseAsset.fromJson(entry);
        if (asset != null) assets.add(asset);
      }
    }
    // Enum order, so the disk image is always the first row and the checksum
    // manifest always the last, whatever order the upload step happened to run
    // its files in.
    assets.sort((a, b) => a.target.index.compareTo(b.target.index));

    return GithubRelease(
      tag: switch (json['tag_name']) {
        final String tag => tag,
        _ => '',
      },
      htmlUrl: switch (json['html_url']) {
        final String url => url,
        _ => '',
      },
      publishedAt: switch (json['published_at']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
      assets: assets,
    );
  }
}

/// What the page knows about the latest release.
///
/// Sealed so the hero and the download band have to answer for every case. The
/// difference between "no release yet" and "could not reach GitHub" matters:
/// one is a page that is early, the other is a page that is broken, and they
/// need different words.
@immutable
sealed class ReleaseState {
  const ReleaseState();
}

class ReleaseLoading extends ReleaseState {
  const ReleaseLoading();
}

class ReleaseReady extends ReleaseState {
  const ReleaseReady(this.release);

  final GithubRelease release;
}

/// A repository with no published release yet, or a tag whose build failed and
/// left the release empty.
class ReleasePending extends ReleaseState {
  const ReleasePending();
}

class ReleaseUnavailable extends ReleaseState {
  const ReleaseUnavailable(this.reason);

  final String reason;
}
