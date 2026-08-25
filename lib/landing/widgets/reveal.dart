import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Publishes the page's [ScrollController] to everything below it.
///
/// [Reveal] needs to know where it is as the page moves. Threading the controller
/// down through every section constructor would put a parameter on widgets that
/// have no other reason to know the page scrolls at all.
class LandingScroll extends InheritedWidget {
  const LandingScroll({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LandingScroll>()?.controller;

  @override
  bool updateShouldNotify(LandingScroll oldWidget) =>
      oldWidget.controller != controller;
}

/// Fades and lifts its child in the first time it comes near the fold.
///
/// One-shot on purpose: content that re-animates every time it scrolls back
/// past is a page that will not sit still to be read.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Position within a group, for the staggered variant. Ignored here.
  final int index;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  ScrollController? _controller;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = LandingScroll.maybeOf(context);
    if (controller == _controller) return;
    _controller?.removeListener(_check);
    _controller = controller?..addListener(_check);
    // A section already on screen at first paint never fires a scroll
    // notification, so it needs a check of its own or it stays invisible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    // And again once the web font has landed. Inter arrives over the network
    // and reflows the whole page; anything that was just below the trip line
    // at first paint may be above it afterwards, and no scroll event fires to
    // say so. Without this, a tall window shows an empty band under the hero
    // until the visitor scrolls.
    Future<void>.delayed(const Duration(milliseconds: 700), _check);
  }

  @override
  void dispose() {
    _controller?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_shown || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    // Trips slightly before the fold, so the movement is finishing as the
    // content arrives rather than starting once it is already being read.
    if (top < MediaQuery.sizeOf(context).height * 0.92) {
      _controller?.removeListener(_check);
      setState(() => _shown = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    if (motion.reduced) return widget.child;

    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.045),
      duration: motion.slow,
      curve: motion.standard,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: motion.slow,
        curve: motion.standard,
        child: widget.child,
      ),
    );
  }
}

/// A per-index delayed fade, with no scroll listener of its own.
///
/// Pair it with one [Reveal] around the whole group: the group's listener
/// decides *when* the row arrives, and these decide the order within it. One
/// listener per card measured its own position on every scroll frame, which on
/// a page of grids meant thirty measurements a frame for an effect that has
/// already finished by the time most of them run.
class StaggeredFade extends StatelessWidget {
  const StaggeredFade({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  /// Capped: past the sixth card the delay stops meaning "in order" and starts
  /// meaning "still loading".
  static Duration delayFor(int index) =>
      Duration(milliseconds: 70 * (index.clamp(0, 5)));

  @override
  Widget build(BuildContext context) {
    if (context.motion.reduced) return child;
    return _DelayedFade(delay: delayFor(index), child: child);
  }
}

/// [Reveal] and [StaggeredFade] together, for a lone card outside a grid.
class StaggeredReveal extends StatelessWidget {
  const StaggeredReveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.motion.reduced) return child;
    return Reveal(child: StaggeredFade(index: index, child: child));
  }
}

class _DelayedFade extends StatefulWidget {
  const _DelayedFade({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_DelayedFade> createState() => _DelayedFadeState();
}

class _DelayedFadeState extends State<_DelayedFade> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _ready ? 1 : 0,
      duration: context.motion.normal,
      child: widget.child,
    );
  }
}
