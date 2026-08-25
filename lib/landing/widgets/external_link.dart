import 'dart:js_interop';

/// Opens [url] in a new tab.
///
/// `dart:js_interop` rather than `url_launcher`, because this page is only ever
/// compiled for the web. `url_launcher` would add a plugin to the macOS, iOS,
/// Android, Linux and Windows builds — a pod, a Gradle dependency and a
/// registrant entry on every platform — so that one anchor on a marketing page
/// can do what the browser already does.
///
/// Only ever reached from `lib/landing/`, which `lib/main.dart` never imports,
/// so nothing in the product build resolves this library.
@JS('window.open')
external void _windowOpen(String url, String target, String features);

void openExternalUrl(String url) {
  // `noopener` is not optional: without it the opened page gets a live
  // `window.opener` handle back into this one.
  _windowOpen(url, '_blank', 'noopener,noreferrer');
}
