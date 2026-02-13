import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

abstract class AppsEvent {}

class LoadApps extends AppsEvent {}

class UninstallAppEvent extends AppsEvent {
  final MacApp app;

  UninstallAppEvent(this.app);
}
