import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/data/github_release.dart';
import 'package:tidy/landing/state/landing_controller.dart';
import 'package:tidy/landing/widgets/app_preview.dart';
import 'package:tidy/landing/widgets/landing_button.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/pointer_tilt.dart';

/// The top of the page: what it is, what it costs, and the thing itself.
///
/// Laid out as a split rather than a centred stack, and painted on the app's
/// own `AmbientBackground` rather than a gradient of the page's invention. The
/// backdrop is Tidy's single most recognisable surface — the light pools, the
/// oversized rings, the dot grid — so the first screenful of the site is
/// literally made of the product, and the window on the right lands *in* it
/// rather than on top of it.
class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.controller,
    required this.onSeeDownloads,
    required this.onTryIt,
  });

  final LandingController controller;
  final VoidCallback onSeeDownloads;
  final VoidCallback onTryIt;

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final split = size.atLeast(WindowSizeClass.large);

    // The backdrop is painted behind rather than wrapped around. Inside a
    // scroll view the incoming height is unbounded, and `AmbientBackground`
    // ends in a `Stack(fit: StackFit.expand)` — which needs a height to expand
    // into and renders nothing without one. As a `Positioned.fill` under the
    // content it gets tight constraints from the Stack, and the content is
    // still what decides how tall the band is.
    return Stack(
      children: [
        Positioned.fill(
          child: AmbientBackground(
            tone: ModuleTone.brand,
            child: const SizedBox.expand(),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: kLandingNavHeight + (split ? 64 : 40),
            bottom: split ? 96 : 64,
          ),
          child: LandingContainer(
            child:
                split
                    ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 46,
                          child: _Copy(
                            controller: controller,
                            onSeeDownloads: onSeeDownloads,
                            onTryIt: onTryIt,
                            split: true,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxxl),
                        Expanded(flex: 54, child: const _Window(bleed: true)),
                      ],
                    )
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Copy(
                          controller: controller,
                          onSeeDownloads: onSeeDownloads,
                          onTryIt: onTryIt,
                          split: false,
                        ),
                        const SizedBox(height: 56),
                        const _Window(bleed: false),
                      ],
                    ),
          ),
        ),
      ],
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({required this.bleed});

  /// Lets the window run past the page's right gutter.
  ///
  /// A hero image that stops politely inside the same column as the text reads
  /// as an illustration of the product. One that carries on off the edge reads
  /// as a window that happens to be open behind the page, which is the whole
  /// idea here.
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    const preview = PointerTilt(child: LandingAppPreview(interactive: false));
    if (!bleed) return preview;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 1.34;
        return SizedBox(
          height: width / (kPreviewWidth / kPreviewHeight),
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: width,
            child: SizedBox(width: width, child: preview),
          ),
        );
      },
    );
  }
}

class _Copy extends StatelessWidget {
  const _Copy({
    required this.controller,
    required this.onSeeDownloads,
    required this.onTryIt,
    required this.split,
  });

  final LandingController controller;
  final VoidCallback onSeeDownloads;
  final VoidCallback onTryIt;
  final bool split;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = context.windowSize;

    final headline = size.resolve<double>(
      compact: 38,
      medium: 46,
      expanded: 56,
      large: 58,
      extraLarge: 64,
    );

    return Column(
      crossAxisAlignment:
          split ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        const _StatusLine(),
        const SizedBox(height: AppSpacing.xl),
        _Headline(size: headline, split: split),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'One app for the small jobs macOS makes awkward — clipboard '
            'history, disk cleanup, uninstalling apps properly, startup and '
            'process control, and getting things back out of the Trash.',
            textAlign: split ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              fontSize: split ? 17 : 16,
              height: 1.6,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _Actions(
          controller: controller,
          onSeeDownloads: onSeeDownloads,
          onTryIt: onTryIt,
          split: split,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ReleaseCaption(controller: controller, split: split),
        const SizedBox(height: AppSpacing.xxl),
        _ProofStrip(split: split),
      ],
    );
  }
}

/// The mark, then the three things worth knowing before the headline.
class _StatusLine extends StatelessWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: 22),
        const SizedBox(width: AppSpacing.md),
        Text(
          'Tidy for macOS',
          style: context.text.label.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(width: 1, height: 13, color: colors.border),
        const SizedBox(width: AppSpacing.md),
        Text(
          'Free · GPL-3.0',
          style: context.text.label.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// The tagline, with the verb the product is named for carrying the brand ramp.
class _Headline extends StatelessWidget {
  const _Headline({required this.size, required this.split});

  final double size;
  final bool split;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final style = TextStyle(
      fontSize: size,
      height: 1.02,
      fontWeight: FontWeight.w700,
      letterSpacing: -size * 0.032,
      color: colors.textPrimary,
    );

    Widget gradient(String word) => ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback:
          (bounds) => LinearGradient(
            colors: colors.accentGradient,
          ).createShader(bounds),
      child: Text(word, style: style),
    );

    if (!split) {
      // One block that wraps where it likes. Forcing a break at a narrow width
      // is how a headline ends up with one orphaned word on its own line.
      return Text(Brand.tagline, textAlign: TextAlign.center, style: style);
    }

    // Broken by hand, because the break is the point: "reclaim" starts the
    // second line, where it is the first thing read.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clean, tune and', style: style),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [gradient('reclaim'), Text(' your Mac', style: style)],
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.controller,
    required this.onSeeDownloads,
    required this.onTryIt,
    required this.split,
  });

  final LandingController controller;
  final VoidCallback onSeeDownloads;
  final VoidCallback onTryIt;
  final bool split;

  @override
  Widget build(BuildContext context) {
    final asset = controller.suggestedAsset;

    final (label, url, busy) = switch (controller.release) {
      ReleaseLoading() => ('Checking builds…', null, true),
      ReleaseReady() when asset != null => (
        'Download ${Brand.name} ${controller.version}',
        asset.downloadUrl,
        false,
      ),
      _ => ('See downloads', null, false),
    };

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      alignment: split ? WrapAlignment.start : WrapAlignment.center,
      children: [
        LandingButton(
          label: label,
          icon: AppIcons.downloads,
          large: true,
          busy: busy,
          url: url,
          onPressed: url == null && !busy ? onSeeDownloads : null,
        ),
        LandingButton(
          label: 'Try it right here',
          icon: AppIcons.run,
          kind: LandingButtonKind.secondary,
          large: true,
          onPressed: onTryIt,
        ),
      ],
    );
  }
}

/// The line under the buttons. Says what pressing them gets you, and admits it
/// when it does not know.
class _ReleaseCaption extends StatelessWidget {
  const _ReleaseCaption({required this.controller, required this.split});

  final LandingController controller;
  final bool split;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final text = switch (controller.release) {
      ReleaseLoading() => 'Looking up the latest build…',
      ReleaseReady(:final release) => [
        'v${release.version}',
        if (release.assetFor(DownloadTarget.dmg)?.readableSize
            case final String size when size.isNotEmpty)
          size,
        'macOS 11 or later',
        release.publishedLabel,
      ].where((part) => part.isNotEmpty).join(' · '),
      ReleasePending() =>
        'The next build is still going through CI. Everything is on GitHub in '
            'the meantime.',
      ReleaseUnavailable(:final reason) =>
        '$reason You can still download from the releases page.',
    };

    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        textAlign: split ? TextAlign.start : TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: colors.textMuted),
      ),
    );
  }
}

/// Three claims on one rule, under the fold-line of the copy column.
class _ProofStrip extends StatelessWidget {
  const _ProofStrip({required this.split});

  final bool split;

  static const List<({IconData icon, String label})> _items = [
    (icon: AppIcons.unlocked, label: 'Open source'),
    (icon: AppIcons.privacy, label: 'No account, no telemetry'),
    (icon: AppIcons.cpu, label: 'Apple silicon & Intel'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        spacing: AppSpacing.xxl,
        runSpacing: AppSpacing.md,
        alignment: split ? WrapAlignment.start : WrapAlignment.center,
        children: [
          for (final item in _items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 15, color: colors.accent),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  item.label,
                  style: context.text.bodyM.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
