import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_service.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_event.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_state.dart';

export 'package:tidy/features/ai_usage/logic/ai_usage_event.dart';
export 'package:tidy/features/ai_usage/logic/ai_usage_state.dart';

/// Drives the AI Usage page.
///
/// No timer. Unlike the Network page there is nothing live to tap — the logs
/// are files somebody else appends to, and re-reading them on a schedule would
/// spend an isolate every few seconds to learn nothing. The page re-reads when
/// it comes back on screen, and on Refresh.
class AiUsageBloc extends Bloc<AiUsageEvent, AiUsageState> {
  AiUsageBloc(this._service) : super(const AiUsageState()) {
    on<LoadAiUsage>(_onLoad);
    on<RebuildAiUsage>(_onRebuild);
    on<AiUsageTabChanged>(_onTab);
    on<AiUsageRangeChanged>(_onRange);
    on<AiUsageProgressed>(_onProgress);
  }

  final AiUsageService _service;

  Future<void> _onLoad(LoadAiUsage event, Emitter<AiUsageState> emit) async {
    // A held report paints immediately; the sweep behind it only ever adds to
    // it. Blanking the page while the same numbers are re-read makes a refresh
    // look like a reset.
    emit(state.copyWith(status: AiUsageStatus.loading, filesDone: 0));

    final report = await _service.load(
      refresh: event.refresh,
      onProgress: (progress) => add(AiUsageProgressed(progress)),
    );

    emit(state.copyWith(status: AiUsageStatus.ready, report: report));
  }

  Future<void> _onRebuild(
    RebuildAiUsage event,
    Emitter<AiUsageState> emit,
  ) async {
    emit(state.copyWith(status: AiUsageStatus.loading, filesDone: 0));
    final report = await _service.rebuild(
      onProgress: (progress) => add(AiUsageProgressed(progress)),
    );
    emit(state.copyWith(status: AiUsageStatus.ready, report: report));
  }

  void _onTab(AiUsageTabChanged event, Emitter<AiUsageState> emit) {
    emit(
      state.copyWith(
        tab: event.index == 1 ? AiUsageTab.analytics : AiUsageTab.overview,
      ),
    );
  }

  void _onRange(AiUsageRangeChanged event, Emitter<AiUsageState> emit) {
    emit(state.copyWith(range: event.range));
  }

  void _onProgress(AiUsageProgressed event, Emitter<AiUsageState> emit) {
    emit(
      state.copyWith(
        filesDone: event.progress.filesDone,
        filesTotal: event.progress.filesTotal,
      ),
    );
  }
}
