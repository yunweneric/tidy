import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/router/app_router.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/features/menubar/platform/popover_bridge.dart';
import 'package:mac_uninstaller/features/menubar/presentation/menu_bar_panel.dart';

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
        );
      },
    );
  }
}
