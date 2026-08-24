import 'package:equatable/equatable.dart';

/// How far through a removal we are.
///
/// Removal used to be a single awaited call, which meant the confirm dialog
/// closed the instant the user pressed the button and the app appeared to do
/// nothing for however long trashing a 12 GB bundle takes. Reporting the steps
/// is what lets the dialog stay open and show its work.
class RemovalProgress extends Equatable {
  const RemovalProgress({
    required this.completed,
    required this.total,
    required this.movedToTrash,
    this.currentLabel,
  });

  /// Paths finished so far.
  final int completed;

  final int total;

  /// Whether this is a trash or a permanent delete — the wording differs and
  /// the progress line should not have to guess.
  final bool movedToTrash;

  /// What is being removed right now, named the way the user would name it.
  final String? currentLabel;

  double get fraction => total == 0 ? 0 : (completed / total).clamp(0.0, 1.0);

  /// A single path gives one step, so a determinate bar would sit at zero for
  /// the whole removal and then jump. Sweep instead — it is the honest shape
  /// for "this is happening and we cannot say how far in".
  bool get isIndeterminate => total <= 1;

  @override
  List<Object?> get props => [completed, total, movedToTrash, currentLabel];
}
