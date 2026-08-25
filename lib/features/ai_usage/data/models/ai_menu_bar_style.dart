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
  );

  const AiMenuBarStyle(this.label, this.blurb);

  final String label;
  final String blurb;

  static AiMenuBarStyle fromName(String? name) =>
      values.firstWhere((style) => style.name == name, orElse: () => cost);
}
