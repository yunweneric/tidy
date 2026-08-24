import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/insights/dashboard_repository.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/features/dashboard/logic/dashboard_event.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';

/// Gathers the Dashboard's numbers.
///
/// Every source is read independently and emitted the moment it lands, rather
/// than awaited together and emitted once. The reads differ by orders of
/// magnitude — `statfs` answers instantly, a Trash sweep crosses every mounted
/// volume — so gathering them into one `await` would make the whole page as
/// slow as the slowest thing on it.
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc(this._repository) : super(const DashboardState()) {
    on<LoadDashboard>(_onLoad);
    on<RefreshDashboard>(_onRefresh);
    on<DashboardTicked>(_onTick);
    on<TrendRangeChanged>(_onRange);
    on<JunkObserved>(_onJunk);
  }

  final DashboardRepository _repository;

  Future<void> _onLoad(LoadDashboard event, Emitter<DashboardState> emit) =>
      _gather(emit);

  Future<void> _onRefresh(
    RefreshDashboard event,
    Emitter<DashboardState> emit,
  ) async {
    emit(state.copyWith(refreshing: true));
    await _gather(emit);
    emit(state.copyWith(refreshing: false));
  }

  Future<void> _onRange(
    TrendRangeChanged event,
    Emitter<DashboardState> emit,
  ) async {
    if (event.range == state.range) return;
    emit(state.copyWith(range: event.range, historyStatus: SectionStatus.loading));
    await _readHistory(emit, event.range);
    await _readNetwork(emit, event.range);
  }

  void _onJunk(JunkObserved event, Emitter<DashboardState> emit) {
    if (state.junkBytes == event.bytes) return;
    emit(state.copyWith(junkBytes: event.bytes));
  }

  /// The 2s pulse. Only the two live readings — re-reading the Trash or the
  /// clipboard every two seconds would be a disk sweep on a timer.
  Future<void> _onTick(
    DashboardTicked event,
    Emitter<DashboardState> emit,
  ) async {
    final vitals = await _repository.vitals();
    final processes = await _repository.processes();
    if (emit.isDone) return;

    // A failed tick keeps the last good reading rather than blanking the
    // meters: one dropped sample is not news, and a gauge that flickers to
    // empty and back reads as a fault in the machine rather than in the read.
    emit(
      state.copyWith(
        vitals: vitals,
        processes: processes,
        vitalsStatus:
            vitals == null ? state.vitalsStatus : SectionStatus.ready,
      ),
    );
  }

  /// Fires every read at once and emits as each returns.
  Future<void> _gather(Emitter<DashboardState> emit) async {
    emit(
      state.copyWith(
        vitalsStatus: _loadingFrom(state.vitalsStatus),
        storageStatus: _loadingFrom(state.storageStatus),
        trashStatus: _loadingFrom(state.trashStatus),
        clipsStatus: _loadingFrom(state.clipsStatus),
        networkStatus: _loadingFrom(state.networkStatus),
        appsStatus: _loadingFrom(state.appsStatus),
        launchStatus: _loadingFrom(state.launchStatus),
        historyStatus: _loadingFrom(state.historyStatus),
        recordingSince: _repository.store.recordingSince,
      ),
    );

    await Future.wait([
      _readStorage(emit),
      _readVitals(emit),
      _readTrash(emit),
      _readClips(emit),
      _readNetwork(emit, state.range),
      _readApps(emit),
      _readLaunchItems(emit),
      _readHistory(emit, state.range),
    ]);
  }

  /// A section that already has data stays "ready" while it refreshes, so the
  /// numbers on screen do not blink out and back on every refresh.
  static SectionStatus _loadingFrom(SectionStatus current) =>
      current == SectionStatus.ready ? current : SectionStatus.loading;

  Future<void> _readStorage(Emitter<DashboardState> emit) async {
    final disk = await _repository.disk();
    final access = await _repository.fullDiskAccess();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        disk: disk,
        fullDiskAccess: access,
        storageStatus:
            disk == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  Future<void> _readVitals(Emitter<DashboardState> emit) async {
    final vitals = await _repository.vitals();
    final processes = await _repository.processes();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        vitals: vitals,
        processes: processes,
        vitalsStatus:
            vitals == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  Future<void> _readTrash(Emitter<DashboardState> emit) async {
    final trash = await _repository.trash();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        trash: trash,
        trashStatus: trash == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  Future<void> _readClips(Emitter<DashboardState> emit) async {
    final clips = await _repository.clips();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        clips: clips,
        clipsStatus: clips == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  Future<void> _readNetwork(
    Emitter<DashboardState> emit,
    TrendRange range,
  ) async {
    final headline = await _repository.networkHeadline();
    final series = await _repository.networkSeries(range.networkRange);
    if (emit.isDone) return;
    emit(
      state.copyWith(
        networkHeadline: headline,
        networkSeries: series,
        networkStatus:
            headline == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  Future<void> _readApps(Emitter<DashboardState> emit) async {
    final apps = await _repository.apps();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        apps: apps,
        appsStatus: apps == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  Future<void> _readLaunchItems(Emitter<DashboardState> emit) async {
    final facts = await _repository.launchItems();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        launchItems: facts,
        launchStatus:
            facts == null ? SectionStatus.failed : SectionStatus.ready,
      ),
    );
  }

  /// The history queries. All indexed and all aggregated in SQL, so each
  /// returns the handful of rows a chart draws rather than every row behind it.
  Future<void> _readHistory(
    Emitter<DashboardState> emit,
    TrendRange range,
  ) async {
    final store = _repository.store;
    if (!store.isOpen) {
      if (!emit.isDone) {
        emit(state.copyWith(historyStatus: SectionStatus.failed));
      }
      return;
    }

    final from = range.from;
    final reclaim = store.reclaimSeries(
      from: from,
      granularity: range.granularity,
    );
    final diskFree = store.series(
      MetricSeries.diskFree,
      from: from,
      granularity: range.granularity,
    );
    final operations = store.recentOperations(limit: 8);
    final categories = store.removedByCategory(from: from);
    final totals = store.reclaimed(from: from);

    if (emit.isDone) return;
    emit(
      state.copyWith(
        reclaimBuckets: reclaim,
        diskFreeBuckets: diskFree,
        recentOperations: operations,
        removedByCategory: categories,
        reclaimTotals: totals,
        recordingSince: store.recordingSince,
        historyStatus: SectionStatus.ready,
      ),
    );
  }
}
