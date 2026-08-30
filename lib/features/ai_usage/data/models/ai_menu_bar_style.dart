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
  ),

  /// The same share the bar styles draw, as a ring rather than six segments.
  ///
  /// A different shape for the same fact, for a bar that is already crowded:
  /// a ring reads at a glance at 14pt where a 24pt row of segments needs the
  /// width. It degrades the same way, which is why it is grouped with them by
  /// [needsShare].
  ring(
    'Ring and percentage',
    'A round gauge filled to the same share, with the figure beside it. The '
        'narrowest way to show a share.',
  ),

  /// The one style with no denominator anywhere in it.
  ///
  /// Tokens are counted from logs that are already on this Mac, so unlike
  /// every share style this one can always draw what it promises — which is
  /// the reason it exists.
  tokens(
    'Tokens only',
    'How many tokens went through today, and nothing else. Always available: '
        'it is counted from the logs rather than published by anyone.',
  );

  const AiMenuBarStyle(this.label, this.blurb);

  final String label;
  final String blurb;

  /// Whether this style needs a share to draw, and so can fall back to the
  /// cost when no provider in scope publishes one.
  ///
  /// The settings preview asks this before promising a bar. Claude Code has a
  /// share only while a five-hour block is open or a plan reading is in hand,
  /// and Codex only after a request in the current window — so a style picked
  /// here can be a style that draws nothing different, and the preview has to
  /// say so rather than showing a bar that will not appear.
  bool get needsShare =>
      this == block || this == percentAndBlock || this == ring;

  static AiMenuBarStyle fromName(String? name) =>
      values.firstWhere((style) => style.name == name, orElse: () => cost);
}
