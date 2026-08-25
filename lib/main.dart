import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tidy/core/config/flavor.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/router/app_router.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/features/performance/data/services/performance_bridge.dart';
import 'package:tidy/features/menubar/platform/popover_bridge.dart';
import 'package:tidy/features/menubar/presentation/menu_bar_panel.dart';
import 'package:tidy/features/splash/presentation/splash_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so that a failure while wiring up the engine below is logged rather
  // than lost: `TidyStore.open` and `AppSettings.load` both survive their own
  // failures quietly, and the warning they log is the only sign it happened.
  setUpLogging();
  // A `--flavor` nobody recognises falls back to prod, which would point a
  // debug build at the real Application Support folder. Caught here, in the
  // only build where it is still cheap to fix.
  assert(isKnownFlavor, 'Unknown --flavor "$rawFlavor"; expected dev or prod.');
  AppLog.app.info(
    'starting',
    fields: {
      'engine': 'main',
      'flavor': currentFlavor.name,
      'level': Logger.level.name,
    },
  );

  await setUpLocator(includeUi: true);
  runApp(TidyApp(settings: locator<AppSettings>()));
}

/// Entrypoint for the menu bar popover, run in a second Flutter engine by
/// `macos/Runner/MenuBarController.swift`.
///
/// That engine is its own Dart isolate: it cannot see the main window's
/// providers or its router, so it registers its own services and keeps in step
/// through the on-disk scan cache.
@pragma('vm:entry-point')
Future<void> menuBarMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Its own call, not the window's: this is a separate isolate with its own
  // statics, so nothing `main` set up above exists here. The engine name is
  // what keeps the two apps' lines apart in one console.
  setUpLogging(engine: 'popover');
  AppLog.menuBar.info(
    'starting',
    fields: {
      'engine': 'popover',
      'flavor': currentFlavor.name,
      'level': Logger.level.name,
    },
  );

  await setUpLocator(includeUi: false);
  runApp(const MenuBarPanelApp());
}

class TidyApp extends StatefulWidget {
  const TidyApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<TidyApp> createState() => _TidyAppState();
}

class _TidyAppState extends State<TidyApp> {
  // Built once and held: rebuilding the router on every settings change would
  // throw away the shell's branch state along with it.
  late final _router = buildRouter(settings: widget.settings);

  @override
  void initState() {
    super.initState();
    // The menu bar popover cannot reach this router across the isolate
    // boundary, so "Open Clipboard" arrives as a route over the channel.
    PopoverRoutes.listen(_router.go);

    // Vitals are read through a closure rather than imported by the sampler:
    // `PerformanceBridge` belongs to a feature, and `docs/feature.md` §2 does
    // not let `core/` reach into one. This is the composition root, so it is
    // the one place allowed to know about both halves.
    locator<MetricSampler>().start(readVitals: PerformanceBridge.systemVitals);
  }

  @override
  void dispose() {
    AppLog.app.debug('shutting down');
    locator<MetricSampler>().stop();
    // Closing the boxes is the flush, and `dispose` cannot await. Nothing is
    // lost worth waiting for: Hive has already written every sample, and the
    // OS tears the process down either way.
    unawaited(locator<TidyStore>().close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        return MaterialApp.router(
          title: Brand.displayName,
          debugShowCheckedModeBanner: false,
          themeMode: widget.settings.themeMode,
          theme: TidyTheme.light(reduceMotion: widget.settings.reduceMotion),
          darkTheme: TidyTheme.dark(reduceMotion: widget.settings.reduceMotion),
          routerConfig: _router,
          // Over the router rather than inside it: the splash is not a route,
          // and making it one would put it in the back stack.
          builder:
              (context, child) =>
                  SplashGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
