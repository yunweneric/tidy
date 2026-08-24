import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';

/// What the window shows before the shell is ready.
///
/// The same backdrop the rest of the app wears — [AmbientBackground] on the
/// brand tone — so the launch does not flash a colour the app never uses again.
/// The mark rises and settles rather than appearing; on a cold start the window
/// is visible for long enough that a static image reads as a hang.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final reduced = context.motion.reduced;

    // Reduce Motion gets the finished state, not a faster version of the
    // animation — the point of the setting is that nothing moves.
    final curve = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    final progress = reduced ? const AlwaysStoppedAnimation<double>(1.0) : curve;

    return AmbientBackground(
      tone: ModuleTone.brand,
      intensity: 1.2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, child) {
              final t = progress.value;
              return Opacity(
                opacity: t,
                // A short rise, not a zoom: the mark lands where it started
                // rather than growing into place.
                child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 108),
                const SizedBox(height: AppSpacing.xxl),
                Text(Brand.name, style: text.displayL),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  Brand.tagline,
                  style: text.bodyM.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                SizedBox(
                  width: 168,
                  child: ClipRRect(
                    borderRadius: AppRadii.pillAll,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      // Determinate at zero under Reduce Motion: an
                      // indeterminate bar is a permanent animation.
                      value: reduced ? 0 : null,
                      backgroundColor: colors.surfaceRaised,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
