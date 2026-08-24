/// Toasts and modals: how the app tells you what happened, and asks before it
/// does something it cannot take back.
///
/// Two things live here and nothing else should be built by hand:
///
/// * **Toast** — transient, corner of the window, never blocks. A result you
///   would want to see but would not want to acknowledge.
/// * **Alert** — modal, blocks, has to be answered. A question, or a report
///   that is too detailed for a toast.
///
/// The dividing line: if the user has to do something about it, it is an
/// alert. If they only have to know, it is a toast.
library;

export 'alert.dart';
export 'feedback_tone.dart';
export 'toast.dart';
