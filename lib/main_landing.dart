import 'package:flutter/material.dart';
import 'package:tidy/landing/landing_app.dart';

/// Entry point for the marketing site.
///
/// Built with `flutter build web -t lib/main_landing.dart`. It shares the
/// design tokens, the widget library and the navigation model with the product,
/// but none of its bootstrap: no logging, no service locator, no router — so
/// none of that, and none of the `dart:io` beneath it, reaches the web bundle.
void main() {
  // Read before `runApp`: once a Navigator is mounted, Flutter's browser
  // history integration normalises the URL and the fragment is gone.
  final anchor = Uri.base.fragment;

  WidgetsFlutterBinding.ensureInitialized();
  runApp(LandingApp(initialAnchor: anchor));
}
