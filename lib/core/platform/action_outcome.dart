import 'package:flutter/foundation.dart';

/// The result of a native action that either worked or has something to say.
///
/// Lives in `core/` rather than beside any one bridge because Performance and
/// Clipboard both speak it, and `docs/feature.md` §2 puts a type used by two
/// features here rather than letting one import the other.
@immutable
class ActionOutcome {
  const ActionOutcome({required this.ok, this.message});

  static const ActionOutcome success = ActionOutcome(ok: true);

  factory ActionOutcome.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const ActionOutcome(ok: false, message: 'No answer from macOS.');
    }
    return ActionOutcome(
      ok: map['ok'] as bool? ?? false,
      message: map['message'] as String?,
    );
  }

  final bool ok;

  /// A sentence to show the user. Null when it simply worked.
  final String? message;
}
