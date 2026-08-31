import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_service.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_event.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_state.dart';

export 'package:tidy/features/ai_usage/logic/ai_usage_event.dart';
export 'package:tidy/features/ai_usage/logic/ai_usage_state.dart';

/// Drives the AI Usage page.
///
/// No sweep timer. Unlike the Network page there is nothing live to tap — the
/// logs are files somebody else appends to, and re-reading them on a schedule
/// would spend an isolate every few seconds to learn nothing. The page re-reads
/// when it comes back on screen, and on Refresh.
///
/// There *is* a clock tick, which is a different thing: the windows count down
/// to a reset and the plan reading ages out, so once a minute the page
/// re-derives its views against a fresh `now` without touching a single file.
class AiUsageBloc extends Bloc<AiUsageEvent, AiUsageState> {
  AiUsageBloc(this._service) : super(const AiUsageState()) {
    on<LoadAiUsage>(_onLoad);
    on<RebuildAiUsage>(_onRebuild);
    on<AiUsageTabChanged>(_onTab);
    on<AiUsageRangeChanged>(_onRange);
    on<AiUsageProgressed>(_onProgress);
    on<AiUsageTicked>(_onTick);
    on<ClaudePlanRefreshed>(_onClaudePlan);

    _ticker = Timer.periodic(tick, (_) => add(const AiUsageTicked()));
  }

  /// How often the countdowns move.
  ///
  /// A minute, because that is the resolution they are drawn at — "3h 53m
  /// left" does not need a second hand, and a per-second rebuild of a page
  /// with a chart on it is a lot of frames to spend on one changed digit.
  static const Duration tick = Duration(minutes: 1);

  final AiUsageService _service;
  late final Timer _ticker;

  Future<void> _onLoad(LoadAiUsage event, Emitter<AiUsageState> emit) async {
    // A held report paints immediately; the sweep behind it only ever adds to
    // it. Blanking the page while the same numbers are re-read makes a refresh
    // look like a reset.
    emit(state.copyWith(status: AiUsageStatus.loading, filesDone: 0));

    final report = await _service.load(
      refresh: event.refresh,
      onProgress: (progress) => add(AiUsageProgressed(progress)),
    );

    emit(state.derive(report: report, status: AiUsageStatus.ready));
  }

  Future<void> _onRebuild(
    RebuildAiUsage event,
    Emitter<AiUsageState> emit,
  ) async {
    emit(state.copyWith(status: AiUsageStatus.loading, filesDone: 0));
    final report = await _service.rebuild(
      onProgress: (progress) => add(AiUsageProgressed(progress)),
    );
    emit(state.derive(report: report, status: AiUsageStatus.ready));
  }

  /// Re-reads the plan limits alone, leaving the logs untouched.
  ///
  /// What switching the setting on should cost: one request. Sweeping every
  /// session log again to collect a number that arrives over the network was
  /// gigabytes of work for two percentages.
  Future<void> _onClaudePlan(
    ClaudePlanRefreshed event,
    Emitter<AiUsageState> emit,
  ) async {
    final report = await _service.refreshClaudePlan(force: event.force);
    if (report == null) return;
    emit(state.derive(report: report));
  }

  void _onTick(AiUsageTicked event, Emitter<AiUsageState> emit) {
    // Nothing to count down to before the first sweep lands.
    if (state.tickedAt == null) return;
    emit(state.derive());

    // And pull the plan reading through while the page is open, so the
    // percentages move rather than only the countdown beside them. Cheap by
    // construction: the client serves its own cache for two minutes and backs
    // off on a 429, so a minute's tick is at most one request every other one.
    add(const ClaudePlanRefreshed());
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

  @override
  Future<void> close() {
    _ticker.cancel();
    return super.close();
  }
}
