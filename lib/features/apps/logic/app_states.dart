import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

abstract class AppsState {}

class AppsInitial extends AppsState {}

class AppsLoading extends AppsState {}

class AppsLoaded extends AppsState {
  final List<MacApp> apps;

  AppsLoaded(this.apps);
}

class AppsError extends AppsState {
  final String message;

  AppsError(this.message);
}
