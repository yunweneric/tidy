import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Fades its child back in whenever [trigger] changes.
///
/// Used for switching between shell branches. An [AnimatedSwitcher] is the
/// obvious choice and the wrong one here: it holds the outgoing and incoming
/// children on screen together, and the shell's branch navigators carry global
/// keys — two live copies means a duplicate-GlobalKey crash.
///
/// Since the branch swap itself is instantaneous, fading the new content up
/// from zero gives the same read as a cross-fade with none of that risk.
class FadeThrough extends StatefulWidget {
  const FadeThrough({super.key, required this.trigger, required this.child});

  /// Change this to replay the fade. Usually the active branch index.
  final Object trigger;

  final Widget child;

  @override
  State<FadeThrough> createState() => _FadeThroughState();
}

class _FadeThroughState extends State<FadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void didUpdateWidget(FadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger == widget.trigger) return;

    if (context.motion.reduced) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// A [Page] that fades in rather than sliding, for top-level route changes.
///
/// macOS windows do not slide their content sideways; a cross-fade is what the
/// platform does and what the rest of this app does.
class FadePage<T> extends CustomTransitionPage<T> {
  FadePage({required super.child, super.key, super.name, super.arguments})
    : super(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (context.motion.reduced) return child;
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      );
}
