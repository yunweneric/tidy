import 'dart:io';

import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/features/protection/data/models/protection_finding.dart';
import 'package:tidy/features/protection/data/models/signing_info.dart';
import 'package:tidy/features/protection/data/services/protection_bridge.dart';

/// What this Mac has written down about where things came from.
///
/// Deliberately short, and honest about why. Of the three traces originally
/// planned here, one is readable, one needs a permission the user may not have
/// given, and one is readable only by an administrator — and the answer to that
/// last one is to say so, not to ask for a password so we can show somebody a
/// list.
class PrivacyTracesAudit {
  /// How many download records to fetch. Enough to describe the history and to
  /// join app provenance against; the page shows a count, not four thousand rows.
  static const int _historyLimit = 500;

  /// [allowed] is whether macOS has already granted access to other apps' data.
  ///
  /// The recent-items lists sit in Application Support, so *probing whether we
  /// can read them is itself the request* — `SystemBridge.canReadPaths` opens
  /// the path, and opening it is what makes macOS ask. Checking the grant we
  /// already hold, rather than discovering it by touching the folder, is the
  /// difference between a page that explains before it asks and one that throws
  /// a permission dialog at somebody for opening a tab.
  Future<({List<ProtectionFinding> findings, List<DownloadEvent> recent})> run({
    required bool allowed,
  }) async {
    final findings = <ProtectionFinding>[];
    final history = await ProtectionBridge.downloadEvents(limit: _historyLimit);

    findings.add(_downloadHistory(history));
    findings.add(await _recentItems(allowed: allowed));
    findings.add(_savedNetworks());

    return (findings: findings, recent: history?.events ?? const []);
  }

  ProtectionFinding _downloadHistory(
    ({List<DownloadEvent> events, int total})? history,
  ) {
    if (history == null) {
      return const ProtectionFinding(
        id: 'traces:downloads',
        area: ProtectionArea.traces,
        title: 'Download history',
        subtitle: '~/Library/Preferences',
        facts: [
          ProtectionFact.unreadable(
            'macOS keeps a record of everything you have downloaded, and would '
            'not let Tidy read it.',
          ),
        ],
      );
    }

    final agents = <String>{
      for (final event in history.events)
        if (event.agent != null) event.agent!,
    };
    final oldest = history.events.isEmpty ? null : history.events.last.at;

    return ProtectionFinding(
      id: 'traces:downloads',
      area: ProtectionArea.traces,
      title: 'Download history',
      subtitle: '~/Library/Preferences',
      facts: [
        ProtectionFact(
          '${history.total} downloads recorded',
          [
            'macOS notes where every downloaded file came from.',
            if (oldest != null) 'The oldest here is from ${oldest.year}.',
            if (agents.isNotEmpty) 'Written by ${agents.take(3).join(', ')}.',
          ].join(' '),
        ),
      ],
    );
  }

  /// The recent-items lists, which sit behind Full Disk Access.
  ///
  /// Counted rather than read: the files are `NSKeyedArchiver` archives, and
  /// decoding them for a list nobody asked to see is work with no payoff. What
  /// the row can honestly say is that they exist and how many there are.
  Future<ProtectionFinding> _recentItems({required bool allowed}) async {
    final home = kHomeDir;
    final path = '$home/Library/Application Support/com.apple.sharedfilelist';

    final readable =
        allowed ? await SystemBridge.canReadPaths([path]) : const {};
    if (readable[path] != true) {
      return const ProtectionFinding(
        id: 'traces:recents',
        area: ProtectionArea.traces,
        title: 'Recent items',
        subtitle: '~/Library/Application Support/com.apple.sharedfilelist',
        facts: [
          ProtectionFact.unreadable(
            'macOS keeps lists of the documents, servers and folders you opened '
            'recently. They sit with other apps’ data, which Tidy has not been '
            'given access to.',
          ),
        ],
        actions: {ProtectionAction.allowBrowserAccess},
      );
    }

    var lists = 0;
    try {
      lists =
          Directory(path)
              .listSync()
              .where(
                (entry) =>
                    entry.path.endsWith('.sfl2') ||
                    entry.path.endsWith('.sfl3'),
              )
              .length;
    } on FileSystemException {
      lists = 0;
    }

    return ProtectionFinding(
      id: 'traces:recents',
      area: ProtectionArea.traces,
      title: 'Recent items',
      subtitle: '~/Library/Application Support/com.apple.sharedfilelist',
      facts: [
        ProtectionFact(
          '$lists ${lists == 1 ? 'list' : 'lists'} kept',
          'macOS records the documents, servers and folders you opened recently, '
              'one list per app. Clearing them is in System Settings.',
        ),
      ],
      path: path,
      actions: const {ProtectionAction.reveal},
    );
  }

  /// Saved Wi-Fi networks, which only an administrator can read.
  ///
  /// The row states the fact and stops. Tidy has a way to ask for an
  /// administrator — it is how a root-owned launch agent is removed — and this
  /// module deliberately does not use it, because asking somebody for their
  /// password so an app can *look at a list* is a trade nobody should make.
  ProtectionFinding _savedNetworks() => const ProtectionFinding(
    id: 'traces:wifi',
    area: ProtectionArea.traces,
    title: 'Saved Wi-Fi networks',
    subtitle: '/Library/Preferences',
    facts: [
      ProtectionFact(
        'Only an administrator can read this',
        'macOS keeps every network this Mac has joined, with the date. The file '
            'is readable only as an administrator, and Tidy does not ask for your '
            'password to read a list. System Settings shows them under Wi-Fi.',
      ),
    ],
    actions: {ProtectionAction.openSettings},
  );
}
