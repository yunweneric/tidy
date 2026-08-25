import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/data/github_release.dart';
import 'package:tidy/landing/data/tidy_repo.dart';
import 'package:tidy/landing/state/landing_controller.dart';
import 'package:tidy/landing/widgets/copy_block.dart';
import 'package:tidy/landing/widgets/landing_button.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/landing_pill.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// What there is to download, read live from the releases API.
///
/// Nothing here is hard-coded to a version. Publishing a tag updates this page
/// without a deploy, and a tag whose build failed says the build is not ready
/// rather than offering a link to nothing.
class DownloadSection extends StatelessWidget {
  const DownloadSection({super.key, required this.controller, this.anchor});

  final LandingController controller;
  final GlobalKey? anchor;

  @override
  Widget build(BuildContext context) {
    return LandingSection(
      anchor: anchor,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            eyebrow: 'Download',
            title:
                controller.onMac ? 'Ready when you are' : 'Tidy is a macOS app',
            lead:
                controller.onMac
                    ? 'Free, and there is no account to make. macOS 11 or later, '
                        'Apple silicon or Intel.'
                    : 'It talks to macOS directly — the Trash, launch agents, the '
                        'pasteboard — so there is no Windows or Linux build, and '
                        'there will not be one. macOS 11 or later.',
          ),
          const SizedBox(height: AppSpacing.xxl),
          Reveal(child: _Body(controller: controller)),
          const SizedBox(height: AppSpacing.xl),
          Reveal(child: _SourceCard()),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final LandingController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.release) {
      ReleaseLoading() => const _LoadingCard(),
      ReleaseReady(:final release) => _ReleaseCard(release: release),
      ReleasePending() => _FallbackCard(
        controller: controller,
        title: 'The next build is still going through CI',
        body:
            'A tag has been pushed but its artefacts are not published yet. '
            'The releases page will have them shortly.',
      ),
      ReleaseUnavailable(:final reason) => _FallbackCard(
        controller: controller,
        title: 'Could not reach GitHub',
        body: '$reason The releases page has every build.',
        retry: true,
      ),
    };
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LandingCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: AppRadii.mdAll,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});

  final GithubRelease release;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LandingCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${Brand.name} ${release.version}',
                style: context.text.titleL,
              ),
              const SizedBox(width: AppSpacing.md),
              const LandingPill(label: 'Latest', emphasis: true),
              const Spacer(),
              if (release.publishedLabel.isNotEmpty)
                Text(
                  'Published ${release.publishedLabel}',
                  style: context.text.caption,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final asset in release.assets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _AssetRow(asset: asset),
            ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.info, size: 15, color: colors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'The first launch is blocked, and that is expected',
                      style: context.text.titleS,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'CI builds are ad-hoc signed rather than notarised, so '
                  'Gatekeeper quarantines them. Open System Settings → Privacy '
                  '& Security and press Open Anyway, or clear the flag '
                  'yourself:',
                  style: context.text.bodyM,
                ),
                const SizedBox(height: AppSpacing.md),
                const CopyBlock(
                  command:
                      'xattr -dr com.apple.quarantine /Applications/Tidy.app',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              LandingLink(
                label: 'All releases and changelogs',
                url: TidyRepo.releases,
              ),
              const Spacer(),
              Text(
                'Verify with SHA256SUMS.txt before you open it.',
                style: context.text.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssetRow extends StatefulWidget {
  const _AssetRow({required this.asset});

  final ReleaseAsset asset;

  @override
  State<_AssetRow> createState() => _AssetRowState();
}

class _AssetRowState extends State<_AssetRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asset = widget.asset;
    final compact = context.windowSize.isBelow(WindowSizeClass.medium);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => openExternalUrl(asset.downloadUrl),
        child: AnimatedContainer(
          duration: context.motion.fast,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surfaceRaised,
            borderRadius: AppRadii.mdAll,
            border: Border.all(
              color: _hovered ? colors.borderStrong : colors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(asset.target.icon, size: 20, color: colors.accent),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset.target.label, style: context.text.titleS),
                    Text(asset.target.detail, style: context.text.caption),
                  ],
                ),
              ),
              if (!compact) ...[
                Text(asset.name, style: context.text.mono),
                const SizedBox(width: AppSpacing.lg),
              ],
              SizedBox(
                width: 76,
                child: Text(
                  asset.readableSize,
                  textAlign: TextAlign.right,
                  style: context.text.bodyM,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(
                AppIcons.downloads,
                size: 18,
                color: _hovered ? colors.accent : colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FallbackCard extends StatelessWidget {
  const _FallbackCard({
    required this.controller,
    required this.title,
    required this.body,
    this.retry = false,
  });

  final LandingController controller;
  final String title;
  final String body;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    return LandingCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleM),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: context.text.bodyL),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              LandingButton(
                label: 'Open releases on GitHub',
                icon: AppIcons.openExternal,
                url: TidyRepo.releases,
              ),
              if (retry)
                LandingButton(
                  label: 'Try again',
                  icon: AppIcons.refresh,
                  kind: LandingButtonKind.secondary,
                  onPressed: () => controller.load(refresh: true),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Build it yourself. The alternative to trusting a binary is being able to
/// make your own, and the instructions are two lines.
class _SourceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LandingCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.developerJunk,
                size: 18,
                color: context.colors.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Or build it from source', style: context.text.titleM),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Flutter 3.38 and Xcode. The script produces the same disk image '
            'CI does, ad-hoc signed, in dist/.',
            style: context.text.bodyM,
          ),
          const SizedBox(height: AppSpacing.lg),
          const CopyBlock(
            command:
                'git clone ${TidyRepo.url}.git && cd tidy && '
                'flutter pub get && ./scripts/build_dmg.sh',
          ),
        ],
      ),
    );
  }
}
