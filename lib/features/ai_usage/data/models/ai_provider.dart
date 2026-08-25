/// One AI coding tool whose session logs Tidy can read.
///
/// Deliberately short. The upstream project this feature borrows its idea from
/// supports six, but four of them write nothing on a Mac that does not have
/// them installed, and a parser that has never been run against a real file is
/// not a feature — it is a claim.
enum AiProvider {
  claudeCode(label: 'Claude Code', defaultRoot: '.claude'),
  codex(label: 'Codex', defaultRoot: '.codex');

  const AiProvider({required this.label, required this.defaultRoot});

  final String label;

  /// The CLI's config folder, relative to `$HOME` — `.claude`, `.codex`.
  ///
  /// Kept relative so the parsing layer stays free of `Platform.environment`
  /// and can run inside an isolate against whatever roots the caller resolved.
  /// Settings can override it per provider.
  final String defaultRoot;

  static AiProvider? tryParse(String raw) {
    for (final provider in values) {
      if (provider.name == raw) return provider;
    }
    return null;
  }
}
