import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/pane_applications.dart';
import 'package:tidy/landing/preview/pane_cleanup.dart';
import 'package:tidy/landing/preview/pane_clipboard.dart';
import 'package:tidy/landing/preview/pane_dashboard.dart';
import 'package:tidy/landing/preview/pane_network.dart';
import 'package:tidy/landing/preview/pane_performance.dart';
import 'package:tidy/landing/preview/pane_recycle_bin.dart';
import 'package:tidy/landing/preview/preview_chrome.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

export 'package:tidy/landing/preview/preview_mac.dart'
    show PreviewMac, PreviewScreen;

/// The size the window is composed at, before it is scaled to whatever room
/// the page has.
///
/// Composing at a fixed desktop size and scaling is what keeps this reading as
/// a desktop app. Laying it out at the container's real width would hand the
/// panes a phone's worth of room inside a wide frame, and a table designed for
/// 1280 does not degrade gracefully into 380 — it just ellipses everything away.
const double kPreviewWidth = 1280;
const double kPreviewHeight = 840;

/// A live, usable Tidy window, built from the same tokens, cards, tables,
/// gauges and charts as the real app.
///
/// This is not a screenshot with hotspots. A screenshot is frozen in whichever
/// appearance it was captured in and cannot be poked at; this repaints with the
/// site's theme toggle and answers the pointer. Depending on the pane, a
/// visitor can run a scan, untick a category and watch the reclaim figure move,
/// uninstall an app and put it back out of the Trash.
///
/// Pass [interactive] false where the window is decoration rather than a demo —
/// the hero tilts it in 3D, and a skewed hit area that swallows clicks is worse
/// than no interaction at all.
class LandingAppPreview extends StatefulWidget {
  const LandingAppPreview({
    super.key,
    this.screen = PreviewScreen.dashboard,
    this.mac,
    this.onNavigate,
    this.interactive = true,
    this.glow = true,
  });

  final PreviewScreen screen;

  /// Supply one to share state across several previews, or leave it null and
  /// this widget owns its own.
  final PreviewMac? mac;

  /// Called when something inside the window navigates — a sidebar row, or one
  /// of the dashboard's counters. Null leaves the window on [screen].
  final ValueChanged<PreviewScreen>? onNavigate;

  final bool interactive;
  final bool glow;

  @override
  State<LandingAppPreview> createState() => _LandingAppPreviewState();
}

class _LandingAppPreviewState extends State<LandingAppPreview> {
  PreviewMac? _owned;

  PreviewMac get _mac => widget.mac ?? (_owned ??= PreviewMac());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget window = AnimatedBuilder(
      animation: _mac,
      builder:
          (context, _) => _PreviewWindow(
            mac: _mac,
            screen: widget.screen,
            onNavigate: widget.interactive ? widget.onNavigate : null,
          ),
    );

    if (!widget.interactive) {
      window = Semantics(
        label:
            'A preview of the Tidy window, showing the '
            '${widget.screen.label} screen.',
        image: true,
        excludeSemantics: true,
        child: IgnorePointer(child: window),
      );
    }

    return AspectRatio(
      aspectRatio: kPreviewWidth / kPreviewHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow:
              widget.glow
                  ? [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: 0.28),
                      blurRadius: 90,
                      spreadRadius: -20,
                      offset: const Offset(0, 30),
                    ),
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 40,
                      spreadRadius: -12,
                      offset: const Offset(0, 18),
                    ),
                  ]
                  : null,
        ),
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: kPreviewWidth,
            height: kPreviewHeight,
            child: window,
          ),
        ),
      ),
    );
  }
}

class _PreviewWindow extends StatelessWidget {
  const _PreviewWindow({
    required this.mac,
    required this.screen,
    this.onNavigate,
  });

  final PreviewMac mac;
  final PreviewScreen screen;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        // The module's colour is the window — not a tint over a neutral
        // canvas. It reaches the sidebar too, and cross-fades when the
        // destination changes, which is the one thing a static capture of this
        // app can never show.
        child: AmbientBackground(
          tone: screen.destination.tone,
          child: Column(
            children: [
              PreviewTitleBar(title: screen.label),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PreviewSidebar(
                      mac: mac,
                      screen: screen,
                      onNavigate: onNavigate,
                    ),
                    Expanded(child: _pane()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pane() => switch (screen) {
    PreviewScreen.dashboard => PreviewDashboardPane(
      mac: mac,
      onNavigate: onNavigate,
    ),
    PreviewScreen.cleanup => PreviewCleanupPane(
      mac: mac,
      onNavigate: onNavigate,
    ),
    PreviewScreen.applications => PreviewApplicationsPane(
      mac: mac,
      onNavigate: onNavigate,
    ),
    PreviewScreen.clipboard => PreviewClipboardPane(mac: mac),
    PreviewScreen.performance => PreviewPerformancePane(mac: mac),
    PreviewScreen.network => PreviewNetworkPane(mac: mac),
    PreviewScreen.recycleBin => PreviewRecycleBinPane(mac: mac),
  };
}
