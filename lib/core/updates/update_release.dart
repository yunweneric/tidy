import 'package:equatable/equatable.dart';
import 'package:tidy/core/updates/app_version.dart';

/// One published release, reduced to the parts the updater acts on.
///
/// A release carries two artifacts: a `.dmg` for someone installing by hand,
/// and a `.zip` of the app bundle for this updater. The zip is what gets
/// downloaded — a disk image would have to be mounted, copied out of and
/// unmounted, which is three more things to fail for no gain.
class UpdateRelease extends Equatable {
  const UpdateRelease({
    required this.version,
    required this.tag,
    required this.name,
    required this.notes,
    required this.zipUrl,
    required this.zipBytes,
    this.publishedAt,
    this.sha256,
    this.dmgUrl,
    this.isPrerelease = false,
  });

  final AppVersion version;

  /// The git tag, as published — `v1.2.3`. Kept verbatim for the "skipped
  /// version" record, so the comparison there is a string equality on the same
  /// value the API returned rather than a re-derivation.
  final String tag;

  /// The release title. Falls back to the tag when GitHub has none.
  final String name;

  /// The release body, as written. Markdown, rendered as plain text — a
  /// markdown dependency to show three bullet points would not pay for itself.
  final String notes;

  final Uri zipUrl;

  /// Content length as GitHub reports it, so the progress bar is determinate
  /// from the first byte rather than after the first response header.
  final int zipBytes;

  final DateTime? publishedAt;

  /// The asset digest GitHub publishes, without its `sha256:` prefix.
  ///
  /// Null on older releases and on any asset uploaded before GitHub started
  /// recording it. Integrity only — it arrives over the same connection as the
  /// download, so it catches a truncated or corrupted transfer, not an attacker.
  /// The signature check in `Updater.swift` is what actually establishes trust.
  final String? sha256;

  /// Offered as the manual fallback when the in-place swap cannot proceed.
  final Uri? dmgUrl;

  final bool isPrerelease;

  @override
  List<Object?> get props => [
    version,
    tag,
    name,
    notes,
    zipUrl,
    zipBytes,
    publishedAt,
    sha256,
    dmgUrl,
    isPrerelease,
  ];
}
