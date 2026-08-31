import 'package:tidy/core/models/launch_item.dart';
import 'package:tidy/core/services/launch_items_service.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/features/protection/data/models/protection_finding.dart';
import 'package:tidy/features/protection/data/models/signing_info.dart';
import 'package:tidy/features/protection/data/services/protection_bridge.dart';

/// What starts itself, and what macOS can say about the thing it starts.
///
/// The launchd read already exists and is shared with Performance — this adds
/// the one thing that read does not carry, which is who signed the program.
class StartupAudit {
  StartupAudit(this._items);

  final LaunchItemsService _items;

  /// Binaries built on this Mac rather than downloaded, which is why they carry
  /// no signature. Recognised so the row can say *why* it is unsigned instead of
  /// leaving a developer's own database looking like something that crept in.
  static const List<String> _locallyBuilt = [
    '/opt/homebrew/',
    '/usr/local/Cellar/',
    '/usr/local/opt/',
  ];

  /// Somewhere a program has no business living.
  ///
  /// `/tmp` is world-writable and cleared on boot; a login item pointing there
  /// either does nothing or is running something anybody could have replaced.
  static const List<String> _oddRoots = ['/tmp/', '/private/tmp/', '/var/tmp/'];

  Future<List<ProtectionFinding>> run() async {
    final items = await _items.load();
    if (items.isEmpty) return const [];

    // One channel round trip for every program, rather than one per row.
    final programs = <String>{
      for (final item in items)
        if (item.program != null && item.program!.startsWith('/'))
          item.program!,
    };
    final signatures = await ProtectionBridge.signingInfo(programs.toList());

    return [
      for (final item in items) _findingFor(item, signatures[item.program]),
    ];
  }

  ProtectionFinding _findingFor(LaunchItem item, SigningInfo? signature) {
    final facts = <ProtectionFact>[];
    final program = item.program;

    if (item.unreadable) {
      facts.add(
        const ProtectionFact.unreadable(
          'macOS would not let Tidy open this file, so nothing below is known '
          'about it.',
        ),
      );
    } else if (item.emptyStub) {
      facts.add(
        const ProtectionFact(
          'Starts nothing',
          'The file is here but names no program to run.',
          notable: true,
        ),
      );
    } else if (item.programMissing) {
      facts.add(
        ProtectionFact(
          'Binary is missing',
          'It is set to run ${collapseHome(program ?? '', kHomeDir)}, and there '
              'is nothing there.',
          notable: true,
        ),
      );
    } else if (item.programUnknown) {
      facts.add(
        const ProtectionFact.unreadable(
          'It names a bare command rather than a path, so whether it resolves '
          'depends on settings Tidy cannot see.',
        ),
      );
    }

    if (program != null && _oddRoots.any(program.startsWith)) {
      facts.add(
        const ProtectionFact(
          'Runs from a temporary folder',
          'Anything can write there and macOS clears it on restart, so this is '
              'an unusual place to start something from.',
          notable: true,
        ),
      );
    }

    if (signature != null && !item.programMissing) {
      facts.addAll(_signatureFacts(signature, program));
    }

    if (item.startsAtLogin) {
      facts.add(
        const ProtectionFact(
          'Starts when you log in',
          'Runs without being asked.',
        ),
      );
    }

    return ProtectionFinding(
      id: item.path,
      area: ProtectionArea.startup,
      title: item.name,
      subtitle: collapseHome(item.path, kHomeDir),
      facts: facts,
      path: item.path,
      appPath: item.appPath,
      enabled: item.enabled,
      actions: {
        ProtectionAction.reveal,
        if (item.canToggle)
          if (item.enabled)
            ProtectionAction.disable
          else
            ProtectionAction.enable,
        if (item.isRemovable || item.canRemoveWithAdmin)
          ProtectionAction.remove,
      },
    );
  }

  List<ProtectionFact> _signatureFacts(SigningInfo signature, String? program) {
    // Anything Homebrew built. On Apple Silicon those are ad-hoc signed rather
    // than unsigned — arm64 requires a signature of some kind — so every branch
    // below that lands on "nobody is named" has to know about it. Getting this
    // wrong put a developer's own database services among the findings, which
    // is how a checker teaches people to stop reading it.
    final built = program != null && _locallyBuilt.any(program.startsWith);
    const homebrew =
        'Built on this Mac by Homebrew, which does not sign what it builds with '
        'a developer identity. Ordinary for developer tools.';

    if (signature.isUnreadable) {
      return [
        ProtectionFact.unreadable(
          'macOS could not read the signature: ${signature.error}.',
        ),
      ];
    }

    if (!signature.signed) {
      return [
        ProtectionFact(
          'Not signed',
          built
              ? homebrew
              : 'macOS has no developer to attribute this to. Common for tools '
                  'built from source, and worth knowing about anything else.',
          notable: !built,
        ),
      ];
    }

    if (signature.adhoc) {
      return [
        ProtectionFact(
          built ? 'Built locally' : 'Signed by itself',
          built
              ? homebrew
              : 'The signature proves the file has not changed since it was '
                  'made, and nothing at all about who made it.',
          notable: !built,
        ),
      ];
    }

    final developer = signature.developer;
    if (developer == null) {
      return [
        ProtectionFact(
          built ? 'Built locally' : 'No developer identified',
          built
              ? homebrew
              : 'It is signed, but not in a way that names anybody.',
          notable: !built,
        ),
      ];
    }

    return [
      ProtectionFact('Signed by $developer', 'macOS recognises the signature.'),
    ];
  }
}
