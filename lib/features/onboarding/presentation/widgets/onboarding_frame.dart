import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// The shared two-pane frame: brand panel on the left, step content on the right.
///
/// A single frame for every step means the brand panel and the progress dots
/// never move between them — the content changes, the chrome does not, and the
/// flow reads as one screen rather than three.
class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.title,
    required this.child,
    this.subtitle,
    this.primaryLabel = 'Continue',
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.onBack,
  });

  final int stepIndex;
  final int stepCount;
  final String title;
  final String? subtitle;
  final Widget child;

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: Row(
        children: [
          const _BrandPanel(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.huge,
                vertical: AppSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Dots(index: stepIndex, count: stepCount),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(title, style: context.text.displayL),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(subtitle!, style: context.text.bodyL.copyWith(
                        color: colors.textSecondary,
                      )),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(child: child),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      if (onBack != null)
                        TextButton(onPressed: onBack, child: const Text('Back')),
                      const Spacer(),
                      if (secondaryLabel != null)
                        TextButton(
                          onPressed: onSecondary,
                          child: Text(secondaryLabel!),
                        ),
                      const SizedBox(width: AppSpacing.sm),
                      ElevatedButton(
                        onPressed: onPrimary,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxl,
                            vertical: AppSpacing.lg,
                          ),
                        ),
                        child: Text(primaryLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.accentGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: const Icon(AppIcons.brand, size: 19, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  Brand.name,
                  style: context.text.titleM.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              Brand.tagline,
              style: context.text.titleL.copyWith(color: Colors.white, height: 1.3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Everything happens on this Mac. Nothing is uploaded, and nothing '
              'is removed without you seeing it first.',
              style: context.text.bodyM.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: context.motion.normal,
            curve: context.motion.standard,
            margin: const EdgeInsets.only(right: AppSpacing.xs + 2),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i <= index ? colors.accent : colors.border,
              borderRadius: AppRadii.pillAll,
            ),
          ),
      ],
    );
  }
}
