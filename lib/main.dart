import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/presentation/screens/list_apps_screen.dart';
import 'package:mac_uninstaller/features/menubar/presentation/menu_bar_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MacUninstallerApp());
}

/// Entrypoint for the menu bar popover, run in a second Flutter engine by
/// `macos/Runner/MenuBarController.swift`.
///
/// It is a separate Dart isolate with its own state; the two views stay in
/// sync through the on-disk scan cache.
@pragma('vm:entry-point')
void menuBarMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MenuBarPanelApp());
}

class MacUninstallerApp extends StatelessWidget {
  const MacUninstallerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppsBloc(AppManagerService())..add(LoadApps()),
      child: MaterialApp(
        title: 'MacUninstaller',
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const ListAppsScreen(),
      ),
    );
  }
}
