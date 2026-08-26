/// How the AI usage readout draws itself in the menu bar.
///
/// Raw names cross the channel and land in the Swift `AiMenuBarStyle`, so they
/// must stay in step with it — the same contract `NetworkMenuBarStyle` carries.
enum AiMenuBarStyle {
  cost('Cost only', 'Today at published API rates. The least menu bar space.'),
  costAndTokens(
    'Cost and tokens',
    'The cost above, the token count below, the way the network readout '
        'stacks its two rates.',
  ),

  /// Deliberately a *time* bar and not a usage one.
  ///
  /// Claude Code writes no limit into its logs, so there is no denominator to
  /// draw a percentage against; the bar shows how far into the five-hour block
  /// you are, which is a fact. Inventing the other one would be the same class
  /// of lie as a scanner reporting "0 threats found".
  block(
    'Cost and block',
    'The cost, with a bar showing how far into the current five-hour block '
        'you are. Not how much of an allowance is left — nothing on this Mac '
        'knows that.',
  ),

  /// The share, and a bar filled to it. No cost.
  ///
  /// What each provider's share *is* differs, and the difference is the same
  /// one the panel draws: Codex publishes its own reading of its allowance, and
  /// Claude Code publishes nothing at all — so its share is how far through the
  /// five-hour block the clock is. Both are facts; only one of them is about an
  /// allowance, and the bar cannot say which, which is what the tooltip is for.
  percentAndBlock(
    'Percentage and block',
    'A bar filled to the share used, and the share beside it. Codex shows its '
        'own published reading; Claude Code shows how far through the '
        'five-hour block you are, because it publishes no limit.',
  );

  const AiMenuBarStyle(this.label, this.blurb);

  final String label;
  final String blurb;

  static AiMenuBarStyle fromName(String? name) =>
      values.firstWhere((style) => style.name == name, orElse: () => cost);
}
