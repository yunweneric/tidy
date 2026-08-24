import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/features/menubar/presentation/menu_bar_panel.dart';
import 'package:mac_uninstaller/features/shell/presentation/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpLocator(includeUi: true);
  runApp(TidyApp(settings: locator<AppSettings>()));
}

/// Entrypoint for the menu bar popover, run in a second Flutter engine by
/// `macos/Runner/MenuBarController.swift`.
///
/// That engine is its own Dart isolate: it cannot see the main window's
/// providers, so it registers its own services and keeps in step through the
/// on-disk scan cache.
@pragma('vm:entry-point')
Future<void> menuBarMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpLocator(includeUi: false);
  runApp(const MenuBarPanelApp());
}

class TidyApp extends StatelessWidget {
  const TidyApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: Brand.name,
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: TidyTheme.light(reduceMotion: settings.reduceMotion),
          darkTheme: TidyTheme.dark(reduceMotion: settings.reduceMotion),
          home: const ShellScreen(),
        );
      },
    );
  }
}
