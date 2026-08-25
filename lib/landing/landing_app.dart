import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/landing_page.dart';
import 'package:tidy/landing/state/landing_controller.dart';

/// The marketing site's root.
///
/// It builds the *product's* themes, not a set of its own, which is what lets
/// the toggle in the navigation bar repaint the page and the app window
/// embedded in it together — and what stops the site and the app drifting into
/// two different-looking things.
class LandingApp extends StatefulWidget {
  const LandingApp({super.key, this.initialAnchor = ''});

  /// The section named in the URL fragment at load, e.g. `download`.
  final String initialAnchor;

  @override
  State<LandingApp> createState() => _LandingAppState();
}

class _LandingAppState extends State<LandingApp> {
  final LandingController _controller = LandingController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app inherits Reduce Motion from the OS through the same query the
    // product uses, so the page's reveals and tilts stop with everything else.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, _) => MaterialApp(
            title: '${Brand.name} — ${Brand.tagline}',
            debugShowCheckedModeBanner: false,
            theme: _webFont(TidyTheme.light(reduceMotion: reduceMotion)),
            darkTheme: _webFont(TidyTheme.dark(reduceMotion: reduceMotion)),
            themeMode: _controller.isDark ? ThemeMode.dark : ThemeMode.light,
            scrollBehavior: const _LandingScrollBehavior(),
            home: LandingPage(
              controller: _controller,
              initialAnchor: widget.initialAnchor,
            ),
          ),
    );
  }

  /// Puts Inter under the whole page.
  ///
  /// The app leaves `fontFamily` unset and gets San Francisco from macOS. On
  /// the web that falls through to Flutter's bundled Roboto, which is the one
  /// thing that would make a page built entirely from the app's own tokens
  /// stop looking like the app. Inter is close enough to SF at text sizes and
  /// is loaded from `web/index.html`.
  ///
  /// `AppTypography`'s styles leave `fontFamily` null, so they inherit this
  /// through the ambient text style rather than needing to be rebuilt.
  ThemeData _webFont(ThemeData base) => base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Inter',
      fontFamilyFallback: const [
        '-apple-system',
        'BlinkMacSystemFont',
        'Segoe UI',
        'sans-serif',
      ],
    ),
  );
}

/// Mouse drag included, so the page can be thrown around with a trackpad the
/// way a native scroll view can. Flutter's web default omits it.
class _LandingScrollBehavior extends MaterialScrollBehavior {
  const _LandingScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
