import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';

/// Whose usage the menu bar's AI readout is about.
///
/// The bar is the one surface with no room to label what it is showing, so it
/// shows one thing and this is where that is chosen. The panel behind it is
/// unaffected: it has room for a section per provider and draws every one it
/// found, whatever this says.
///
/// Raw names cross the channel and land in the Swift `AiReadoutScope`, so they
/// must stay in step with it.
enum AiReadoutScope {
  both('Both', 'Claude Code and Codex, side by side. The widest readout.'),
  claudeCode('Claude Code', 'Claude Code alone.'),
  codex('Codex', 'Codex alone.');

  const AiReadoutScope(this.label, this.blurb);

  final String label;
  final String blurb;

  /// The providers this covers, in bar order.
  List<AiProvider> get providers => switch (this) {
    both => AiProvider.values,
    claudeCode => const [AiProvider.claudeCode],
    codex => const [AiProvider.codex],
  };

  bool covers(AiProvider provider) => providers.contains(provider);

  static AiReadoutScope fromName(String? name) =>
      values.firstWhere((scope) => scope.name == name, orElse: () => both);
}
