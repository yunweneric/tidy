import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/logic/app_states.dart';

class AppsBloc extends Bloc<AppsEvent, AppsState> {
  final AppManagerService service;

  AppsBloc(this.service) : super(AppsInitial()) {
    on<LoadApps>(_onLoadApps);
    on<UninstallAppEvent>(_onUninstall);
  }

  Future<void> _onLoadApps(LoadApps event, Emitter<AppsState> emit) async {
    emit(AppsLoading());

    try {
      final apps = await service.getInstalledApps();
      emit(AppsLoaded(apps));
    } catch (e) {
      emit(AppsError(e.toString()));
    }
  }

  Future<void> _onUninstall(UninstallAppEvent event, Emitter<AppsState> emit) async {
    if (state is! AppsLoaded) return;

    final currentApps = List<MacApp>.from((state as AppsLoaded).apps);

    try {
      await service.uninstallApp(event.app);

      currentApps.remove(event.app);

      emit(AppsLoaded(currentApps));
    } catch (e) {
      emit(AppsError('Failed to uninstall app'));
    }
  }
}
