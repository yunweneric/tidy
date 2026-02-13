import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/presentation/screens/list_apps_screen.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
