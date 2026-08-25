import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/sections/built_with_section.dart';
import 'package:tidy/landing/sections/download_section.dart';
import 'package:tidy/landing/sections/features_section.dart';
import 'package:tidy/landing/sections/footer_section.dart';
import 'package:tidy/landing/sections/hero_section.dart';
import 'package:tidy/landing/sections/landing_nav.dart';
import 'package:tidy/landing/sections/menu_bar_section.dart';
import 'package:tidy/landing/sections/open_source_section.dart';
import 'package:tidy/landing/sections/privacy_section.dart';
import 'package:tidy/landing/sections/problem_section.dart';
import 'package:tidy/landing/sections/safety_section.dart';
import 'package:tidy/landing/sections/steps_section.dart';
import 'package:tidy/landing/sections/tour_section.dart';
import 'package:tidy/landing/state/landing_controller.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// The whole page: one scroll view, a floating bar over it, and a scroll spy
/// keeping the two in agreement.
class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.controller,
    this.initialAnchor = '',
  });

  final LandingController controller;

  /// The section named in the URL fragment at load, e.g. `download`.
  final String initialAnchor;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scroll = ScrollController();

  final GlobalKey _why = GlobalKey();
  final GlobalKey _tour = GlobalKey();
  final GlobalKey _menuBar = GlobalKey();
  final GlobalKey _features = GlobalKey();
  final GlobalKey _safety = GlobalKey();
  final GlobalKey _built = GlobalKey();
  final GlobalKey _steps = GlobalKey();
  final GlobalKey _download = GlobalKey();

  /// Scroll-derived state, kept out of `setState` and out of
  /// [LandingController] on purpose.
  ///
  /// Both of these change while the page is moving. Routing them through
  /// `setState` here rebuilt every section on the page — including three live
  /// preview windows — and routing them through the controller rebuilt the
  /// whole `MaterialApp`. Only the navigation bar cares, so only the
  /// navigation bar listens.
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _active = ValueNotifier<String?>(null);

  /// Declaration order matters: the spy takes the last section above the
  /// reading line, which is only the right answer if this reads down the page.
  late final Map<String, GlobalKey> _anchors = {
    'why': _why,
    'app': _tour,
    'menu-bar': _menuBar,
    'features': _features,
    'safety': _safety,
    'built': _built,
    'install': _steps,
    'download': _download,
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFragment());
    // Again once the web fonts have landed. They reflow the page and move every
    // section, so an anchor resolved against the fallback metrics ends up
    // several hundred pixels off.
    Future<void>.delayed(const Duration(milliseconds: 600), _openFragment);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrolled.dispose();
    _active.dispose();
    super.dispose();
  }

  void _openFragment() {
    if (!mounted) return;
    final key = _anchors[widget.initialAnchor];
    if (key == null) return;
    _jumpTo(key, animate: false);
  }

  void _onScroll() {
    _scrolled.value = _scroll.offset > 12;
    _active.value = _sectionInView();
  }

  /// The section under the reading line, measured live from the render tree.
  ///
  /// Live rather than from cached offsets: the sections resize as images and
  /// fonts arrive and as the window changes width, and a table of offsets built
  /// once is wrong within a second of the page loading.
  String? _sectionInView() {
    if (!_scroll.hasClients) return null;
    final line = MediaQuery.sizeOf(context).height * 0.34;

    String? found;
    for (final entry in _anchors.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy <= line) found = entry.key;
    }

    // The last band is usually shorter than the distance between the reading
    // line and the bottom of the page, so it would never win on its own.
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 4) {
      return _anchors.keys.last;
    }
    return found;
  }

  void _jumpTo(GlobalKey key, {bool animate = true}) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;

    final offset = (_scroll.offset +
            box.localToGlobal(Offset.zero).dy -
            kLandingNavHeight)
        .clamp(0.0, _scroll.position.maxScrollExtent);

    if (!animate || context.motion.reduced) {
      _scroll.jumpTo(offset);
      return;
    }
    _scroll.animateTo(
      offset,
      duration: context.motion.slow,
      curve: context.motion.smooth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    // Three in the bar, all of them in the sheet. The bar has to leave room for
    // the theme toggle, the star chip and the download button, and seven links
    // does not fit next to those at any width worth designing for.
    final barTargets = [
      NavTarget(id: 'app', label: 'The app', onTap: () => _jumpTo(_tour)),
      NavTarget(
        id: 'menu-bar',
        label: 'Menu bar',
        onTap: () => _jumpTo(_menuBar),
      ),
      NavTarget(
        id: 'features',
        label: 'Modules',
        onTap: () => _jumpTo(_features),
      ),
    ];
    final sheetTargets = [
      NavTarget(id: 'why', label: 'Why', onTap: () => _jumpTo(_why)),
      ...barTargets,
      NavTarget(id: 'safety', label: 'Safety', onTap: () => _jumpTo(_safety)),
      NavTarget(
        id: 'built',
        label: 'How it works',
        onTap: () => _jumpTo(_built),
      ),
      NavTarget(id: 'install', label: 'Install', onTap: () => _jumpTo(_steps)),
      NavTarget(
        id: 'download',
        label: 'Download',
        onTap: () => _jumpTo(_download),
      ),
    ];

    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: LandingScroll(
        controller: _scroll,
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  children: [
                    HeroSection(
                      controller: controller,
                      onSeeDownloads: () => _jumpTo(_download),
                      onTryIt: () => _jumpTo(_tour),
                    ),
                    ProblemSection(anchor: _why),
                    TourSection(anchor: _tour),
                    MenuBarSection(anchor: _menuBar),
                    FeaturesSection(anchor: _features),
                    SafetySection(anchor: _safety),
                    const PrivacySection(),
                    BuiltWithSection(anchor: _built),
                    StepsSection(anchor: _steps),
                    DownloadSection(controller: controller, anchor: _download),
                    OpenSourceSection(controller: controller),
                    FooterSection(controller: controller),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _scrolled,
                builder:
                    (context, scrolled, _) => ValueListenableBuilder<String?>(
                      valueListenable: _active,
                      builder:
                          (context, activeId, _) => LandingNav(
                            controller: controller,
                            targets: barTargets,
                            menuTargets: sheetTargets,
                            scrolled: scrolled,
                            activeId: activeId,
                            onDownload: () => _jumpTo(_download),
                          ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
