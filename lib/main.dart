import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
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
    locator<MetricSampler>().stop();
    locator<TidyStore>().close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        return MaterialApp.router(
          title: Brand.name,
          debugShowCheckedModeBanner: false,
          themeMode: widget.settings.themeMode,
          theme: TidyTheme.light(reduceMotion: widget.settings.reduceMotion),
          darkTheme: TidyTheme.dark(reduceMotion: widget.settings.reduceMotion),
          routerConfig: _router,
          // Over the router rather than inside it: the splash is not a route,
          // and making it one would put it in the back stack.
          builder:
              (context, child) => SplashGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
