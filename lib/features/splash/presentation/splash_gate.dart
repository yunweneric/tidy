import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/splash/presentation/splash_screen.dart';

/// Holds [SplashScreen] over the app until the first real frame has settled.
///
/// Only on the desktop platforms. Android, iOS and web get a *native* splash
/// from `flutter_native_splash`, which hands straight over to the first Flutter
/// frame — running this on top of that would show two splashes in a row. The
/// desktop embedders have no such thing: without this, launching Tidy shows an
/// empty window while the engine warms up.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  /// How long the mark stays up once the app has painted.
  ///
  /// The gate is not waiting on work — services are resolved before `runApp`.
  /// It is covering the gap between the window appearing and the shell being
  /// laid out, plus just enough beyond it that the mark is legible rather than
  /// a flicker.
  static const Duration hold = Duration(milliseconds: 900);

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  /// Splash still in the tree.
  bool _mounted = SplashGate._isDesktop;

  /// Splash still opaque. Separate from [_mounted] so it can fade out before
  /// being removed.
  bool _opaque = SplashGate._isDesktop;

  static const Duration _fade = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    if (!_mounted) return;

    // Post-frame, so the hold starts when the app has actually painted rather
    // than when the widget was created — on a slow cold start those are
    // seconds apart and the splash should cover the whole gap.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(SplashGate.hold);
      if (!mounted) return;
      setState(() => _opaque = false);

      await Future<void>.delayed(_fade);
      if (!mounted) return;
      setState(() => _mounted = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return widget.child;

    return Stack(
      children: [
        widget.child,
        // Once it starts fading the app underneath is live, so the splash must
        // stop swallowing clicks even though it is still painted.
        IgnorePointer(
          ignoring: !_opaque,
          child: AnimatedOpacity(
            opacity: _opaque ? 1 : 0,
            duration: context.motion.reduced ? Duration.zero : _fade,
            child: const SplashScreen(),
          ),
        ),
      ],
    );
  }
}
