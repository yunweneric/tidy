import 'package:flutter/widgets.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// What a toast or an alert is telling you, named by meaning rather than hue.
///
/// The status colours mean the same thing on every module — amber has to keep
/// reading as “look at this” and not as “you are in Performance” — so a piece
/// of feedback picks a tone and the tokens resolve it. Nothing outside this
/// file pairs a message with a colour.
enum FeedbackTone {
  /// It worked. Green.
  success,

  /// It worked, mostly, or it is about to do something worth reading first.
  warning,

  /// It failed, or the next tap destroys something.
  danger,

  /// Neutral advisory — an explanation, a permission, a heads-up.
  info,

  /// No status at all. For a plain confirmation with nothing to warn about.
  neutral,
}

extension FeedbackToneTokens on FeedbackTone {
  /// The semantic colour this tone wears.
  ///
  /// [FeedbackTone.neutral] deliberately resolves to text rather than a status
  /// colour: a message with no status should not borrow one.
  Color color(AppColorTokens colors) => switch (this) {
    FeedbackTone.success => colors.safe,
    FeedbackTone.warning => colors.review,
    FeedbackTone.danger => colors.risky,
    FeedbackTone.info => colors.info,
    FeedbackTone.neutral => colors.textSecondary,
  };

  /// The default glyph, overridable at every call site that has a better one.
  IconData get icon => switch (this) {
    FeedbackTone.success => AppIcons.safe,
    FeedbackTone.warning => AppIcons.risky,
    FeedbackTone.danger => AppIcons.error,
    FeedbackTone.info => AppIcons.info,
    FeedbackTone.neutral => AppIcons.info,
  };

  /// How long a toast of this tone stays up by default.
  ///
  /// Bad news gets longer than good news: “it worked” is confirmable at a
  /// glance, “four items stayed put” needs reading and usually a tap.
  Duration get defaultDuration => switch (this) {
    FeedbackTone.success => const Duration(seconds: 4),
    FeedbackTone.neutral => const Duration(seconds: 4),
    FeedbackTone.info => const Duration(seconds: 5),
    FeedbackTone.warning => const Duration(seconds: 8),
    FeedbackTone.danger => const Duration(seconds: 8),
  };
}
