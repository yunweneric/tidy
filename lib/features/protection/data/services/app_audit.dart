import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/features/apps/data/services/apps_service.dart';
import 'package:tidy/features/protection/data/models/protection_finding.dart';
import 'package:tidy/features/protection/data/models/signing_info.dart';
import 'package:tidy/features/protection/data/services/protection_bridge.dart';

/// Who signed the apps on this Mac, and where they came from.
///
/// Reads the inventory `features/apps` already keeps — the one cross-feature
/// import `docs/feature.md` §2 sanctions, because that inventory is the shared
/// answer to "what is installed" and a second sweep of `/Applications` would be
/// a second, slower answer to the same question.
class AppAudit {
  AppAudit(this._apps);

  final AppManagerService _apps;

  /// Emits as each chunk of signatures lands, so seventy apps do not hold the
  /// page on an empty section for a second and a half.
  Stream<List<ProtectionFinding>> run() async* {
    final apps = await _apps.scanApps();
    final installed = [
      for (final app in apps)
        if (!app.isSystem) app,
    ];
    if (installed.isEmpty) return;

    final paths = [for (final app in installed) app.path];

    // One call for every path — the attribute read is microseconds and the
    // round trip is the expensive half.
    final stamps = await ProtectionBridge.quarantine(paths);
    final history = await ProtectionBridge.downloadEvents(limit: 500);
    final urlByEvent = <String, String>{
      for (final event in history?.events ?? const [])
        if (event.eventId != null && event.url != null)
          event.eventId!: event.url!,
    };

    final signatures = <String, SigningInfo>{};
    final findings = <ProtectionFinding>[];

    for (var i = 0; i < paths.length; i += ProtectionBridge.batch) {
      final chunk = paths.skip(i).take(ProtectionBridge.batch).toList();
      signatures.addAll(await ProtectionBridge.signingInfo(chunk));

      findings.clear();
      for (final app in installed) {
        final signature = signatures[app.path];
        if (signature == null) continue;
        final stamp = stamps[app.path]?.withUrl(
          urlByEvent[stamps[app.path]?.eventId ?? ''],
        );
        findings.add(_findingFor(app.name, app.path, signature, stamp));
      }
      yield List.of(findings);
    }
  }

  ProtectionFinding _findingFor(
    String name,
    String path,
    SigningInfo signature,
    QuarantineStamp? stamp,
  ) {
    final facts = <ProtectionFact>[];

    if (signature.isUnreadable) {
      facts.add(
        ProtectionFact.unreadable(
          'macOS could not read the signature: ${signature.error}.',
        ),
      );
    } else if (!signature.signed) {
      facts.add(
        const ProtectionFact(
          'Not signed',
          'macOS has no developer to attribute this to, and cannot tell you '
              'whether it has been changed since it was made.',
          notable: true,
        ),
      );
    } else if (signature.adhoc) {
      facts.add(
        const ProtectionFact(
          'Signed by itself',
          'The signature proves it has not changed since it was made, and '
              'nothing about who made it.',
          notable: true,
        ),
      );
    } else if (signature.developer case final developer?) {
      facts.add(
        ProtectionFact(
          'Signed by $developer',
          'macOS recognises the signature.',
        ),
      );
    } else {
      facts.add(
        const ProtectionFact(
          'No developer identified',
          'It is signed, but not in a way that names anybody.',
          notable: true,
        ),
      );
    }

    // Provenance is a fact and never a verdict. Plenty of good software is
    // downloaded with a browser, and plenty of bad software arrives by other
    // means — this line says where it came from and stops there.
    if (stamp != null && !stamp.isEmpty) {
      final host =
          stamp.url == null
              ? null
              : Uri.tryParse(stamp.url!)?.host.replaceFirst('www.', '');
      final when = stamp.at == null ? null : _monthYear(stamp.at!);
      facts.add(
        ProtectionFact(
          'Downloaded with ${stamp.agent ?? 'a browser'}',
          [
            if (host != null) 'From $host.',
            if (when != null) 'Arrived $when.',
          ].join(' ').trim(),
        ),
      );
    }

    return ProtectionFinding(
      id: path,
      area: ProtectionArea.apps,
      title: name,
      subtitle: collapseHome(path, kHomeDir),
      facts: facts,
      path: path,
      appPath: path,
      actions: const {
        ProtectionAction.reveal,
        ProtectionAction.validate,
        ProtectionAction.assess,
        ProtectionAction.openApps,
      },
    );
  }

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _monthYear(DateTime at) =>
      '${_months[at.month - 1]} ${at.year}';
}
