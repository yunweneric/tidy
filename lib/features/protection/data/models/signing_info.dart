/// What macOS says about one bundle's signature, and where it came from.
///
/// Every field is optional because every one is genuinely absent for something:
/// an unsigned binary has no team, Apple's own software has no Team ID, an
/// ad-hoc build has neither. Absent is reported as absent rather than as an
/// empty string, so "no developer" can be told apart from "a developer whose
/// name we failed to read".
class SigningInfo {
  const SigningInfo({
    required this.path,
    this.signed = false,
    this.adhoc = false,
    this.appleSigned = false,
    this.teamIdentifier,
    this.authority,
    this.identifier,
    this.error,
  });

  factory SigningInfo.fromMap(String path, Map<Object?, Object?> raw) =>
      SigningInfo(
        path: path,
        signed: raw['signed'] == true,
        adhoc: raw['adhoc'] == true,
        appleSigned: raw['appleSigned'] == true,
        teamIdentifier: raw['teamIdentifier'] as String?,
        authority: raw['authority'] as String?,
        identifier: raw['identifier'] as String?,
        error: raw['error'] as String?,
      );

  /// Nothing was read — the path was not checked at all, as opposed to checked
  /// and found unsigned.
  const SigningInfo.unchecked(this.path)
    : signed = false,
      adhoc = false,
      appleSigned = false,
      teamIdentifier = null,
      authority = null,
      identifier = null,
      error = 'Not checked';

  final String path;

  final bool signed;

  /// Signed by itself: the signature proves the file has not changed since it
  /// was made, and nothing at all about who made it.
  final bool adhoc;

  final bool appleSigned;

  /// The developer's Apple team, e.g. `ZJP8787K3Q`. Absent for Apple's own
  /// software and for anything ad-hoc.
  final String? teamIdentifier;

  /// The leaf certificate's common name — the only human-readable "who" macOS
  /// holds, e.g. `Developer ID Application: Some Company (ABCDE12345)`.
  final String? authority;

  final String? identifier;

  /// Set when the check itself failed, which is not the same as "unsigned".
  final String? error;

  bool get isUnreadable => error != null;

  /// Signed by somebody macOS can name.
  bool get hasKnownDeveloper => signed && !adhoc && teamIdentifier != null;

  /// The developer as a person would say it: the company name out of the
  /// authority string, or Apple, or nothing.
  String? get developer {
    if (appleSigned) return 'Apple';
    final name = authority;
    if (name == null) return null;
    // "Developer ID Application: Some Company (ABCDE12345)" → "Some Company".
    final colon = name.indexOf(': ');
    final trimmed = colon == -1 ? name : name.substring(colon + 2);
    final bracket = trimmed.lastIndexOf(' (');
    return bracket == -1 ? trimmed : trimmed.substring(0, bracket);
  }
}

/// Where a file came from, as macOS recorded it when it arrived.
class QuarantineStamp {
  const QuarantineStamp({this.agent, this.at, this.eventId, this.url});

  factory QuarantineStamp.fromMap(Map<Object?, Object?> raw) => QuarantineStamp(
    agent: raw['agent'] as String?,
    at:
        raw['at'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
              ((raw['at'] as num) * 1000).round(),
            )
            : null,
    eventId: raw['eventId'] as String?,
  );

  /// The app that downloaded it — "Chrome", "Safari", "Free Download Manager".
  final String? agent;

  final DateTime? at;

  /// Joins to the download history, when it is present. Often it is not.
  final String? eventId;

  /// Filled in from the download history where the event id matched.
  final String? url;

  QuarantineStamp withUrl(String? found) => QuarantineStamp(
    agent: agent,
    at: at,
    eventId: eventId,
    url: found ?? url,
  );

  bool get isEmpty => agent == null && at == null;
}

/// One row of the download history macOS keeps.
class DownloadEvent {
  const DownloadEvent({this.at, this.agent, this.url, this.eventId});

  factory DownloadEvent.fromMap(Map<Object?, Object?> raw) => DownloadEvent(
    at:
        raw['at'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
              ((raw['at'] as num) * 1000).round(),
            )
            : null,
    agent: raw['agent'] as String?,
    url: raw['url'] as String?,
    eventId: raw['eventId'] as String?,
  );

  final DateTime? at;
  final String? agent;
  final String? url;
  final String? eventId;

  /// The site it came from, not the whole URL — a download link is often a
  /// hundred characters of signed query string, and the host is the part that
  /// answers "where did this come from".
  String? get host {
    final raw = url;
    if (raw == null) return null;
    return Uri.tryParse(raw)?.host.replaceFirst('www.', '');
  }
}
