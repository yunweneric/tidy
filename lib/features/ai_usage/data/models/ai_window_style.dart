/// How the popover lays out one AI limit window.
///
/// Raw names cross the channel and land in the Swift `AiWindowStyle`, so they
/// must stay in step with it — the same contract `AiMenuBarStyle` carries. The
/// popover engine runs `includeUi: false` and has no `AppSettings` of its own,
/// so this arrives with `popoverDidOpen` the way the layout does.
enum AiWindowStyle {
  /// The share on its own line beside the window's name, a bar under it, the
  /// reset and the tokens under that.
  ///
  /// The default: three lines a window, and the only one that draws a share as
  /// a figure. At 320pt the bar is the part read first and the figure is what
  /// makes it exact.
  expanded(
    'Expanded',
    'The share beside each window’s name, a bar of its own underneath, and '
        'the reset and tokens below that. Three lines a window.',
  ),

  /// Everything but the bar on one line.
  compact(
    'Compact',
    'The name, the reset and the figure sharing one line above the bar. Two '
        'lines a window, for a panel with several of them.',
  );

  const AiWindowStyle(this.label, this.blurb);

  final String label;
  final String blurb;

  static AiWindowStyle fromName(String? name) =>
      values.firstWhere((style) => style.name == name, orElse: () => expanded);
}
