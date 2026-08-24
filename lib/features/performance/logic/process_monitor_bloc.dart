import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/features/performance/data/models/process_sample.dart';
import 'package:mac_uninstaller/features/performance/data/services/process_monitor_service.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_state.dart';

// ─── Events ─────────────────────────────────────────────────────────────────

sealed class ProcessMonitorEvent extends Equatable {
  const ProcessMonitorEvent();

  @override
  List<Object?> get props => const [];
}

/// Begins polling. Safe to send repeatedly — a second start is ignored rather
/// than stacking a second timer.
class MonitorStarted extends ProcessMonitorEvent {
  const MonitorStarted();
}

/// Stops polling. Sent whenever the section stops being visible, including
/// when the window is hidden.
class MonitorStopped extends ProcessMonitorEvent {
  const MonitorStopped();
}

class MonitorTicked extends ProcessMonitorEvent {
  const MonitorTicked();
}

class ProcessSortChanged extends ProcessMonitorEvent {
  const ProcessSortChanged(this.sort);

  final ProcessSort sort;

  @override
  List<Object?> get props => [sort];
}

class ProcessQuitRequested extends ProcessMonitorEvent {
  const ProcessQuitRequested(this.pid, {this.force = false});

  final int pid;

  /// Skips the app's chance to save. Offered only after a polite quit has
  /// visibly not worked.
  final bool force;

  @override
  List<Object?> get props => [pid, force];
}

class MonitorNoticeDismissed extends ProcessMonitorEvent {
  const MonitorNoticeDismissed();
}

// ─── State ──────────────────────────────────────────────────────────────────

class ProcessMonitorState extends Equatable {
  const ProcessMonitorState({
    this.snapshot = ProcessSnapshot.empty,
    this.sort = ProcessSort.cpu,
    this.icons = const {},
    this.busyPids = const {},
    this.running = false,
    this.sampled = false,
    this.notice,
  });

  final ProcessSnapshot snapshot;
  final ProcessSort sort;
  final Map<String, Uint8List> icons;

  /// Processes with a quit in flight.
  final Set<int> busyPids;

  final bool running;

  /// True once a first list has arrived. Separate from "has CPU figures",
  /// which needs a second tick.
  final bool sampled;

  final PerformanceNotice? notice;

  List<ProcessSample> get ordered =>
      ProcessMonitorService.sorted(snapshot.processes, sort);

  ProcessMonitorState copyWith({
    ProcessSnapshot? snapshot,
    ProcessSort? sort,
    Map<String, Uint8List>? icons,
    Set<int>? busyPids,
    bool? running,
    bool? sampled,
    PerformanceNotice? notice,
    bool clearNotice = false,
  }) {
    return ProcessMonitorState(
      snapshot: snapshot ?? this.snapshot,
      sort: sort ?? this.sort,
      icons: icons ?? this.icons,
      busyPids: busyPids ?? this.busyPids,
      running: running ?? this.running,
      sampled: sampled ?? this.sampled,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  @override
  List<Object?> get props => [
    snapshot,
    sort,
    busyPids,
    running,
    sampled,
    notice,
    icons.length,
  ];
}

// ─── Bloc ───────────────────────────────────────────────────────────────────

/// Polls what is running, on its own timer.
///
/// The timer is the reason this is a separate bloc. Everything else on the
/// Performance page is a list that is read once; this samples twice a second's
/// worth of work every couple of seconds, and it has to stop the moment the
/// section is no longer on screen. An app that keeps sampling every process on
/// the Mac while minimised is the kind of thing people uninstall.
class ProcessMonitorBloc
    extends Bloc<ProcessMonitorEvent, ProcessMonitorState> {
  ProcessMonitorBloc(this._service) : super(const ProcessMonitorState()) {
    on<MonitorStarted>(_onStart);
    on<MonitorStopped>(_onStop);
    on<MonitorTicked>(_onTick);
    on<ProcessSortChanged>(
      (event, emit) => emit(state.copyWith(sort: event.sort)),
    );
    on<ProcessQuitRequested>(_onQuit);
    on<MonitorNoticeDismissed>(
      (_, emit) => emit(state.copyWith(clearNotice: true)),
    );
  }

  /// Slow enough to be cheap, fast enough that quitting something shows up
  /// before the user wonders whether the button worked.
  static const Duration _interval = Duration(seconds: 2);

  final ProcessMonitorService _service;

  Timer? _timer;
  bool _sampling = false;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }

  Future<void> _onStart(
    MonitorStarted event,
    Emitter<ProcessMonitorState> emit,
  ) async {
    if (state.running) return;

    // CPU is a delta between two samples. Clearing the native history means the
    // first figure covers the seconds since the user opened this, not since the
    // last time the page happened to be visible.
    await _service.start();

    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => add(const MonitorTicked()));

    emit(state.copyWith(running: true, clearNotice: true));
    add(const MonitorTicked());
  }

  void _onStop(MonitorStopped event, Emitter<ProcessMonitorState> emit) {
    _timer?.cancel();
    _timer = null;
    emit(state.copyWith(running: false));
  }

  Future<void> _onTick(
    MonitorTicked event,
    Emitter<ProcessMonitorState> emit,
  ) async {
    // A tick that arrives while the previous one is still out is dropped rather
    // than queued: falling behind should mean sampling less often, not building
    // a backlog of stale readings.
    if (_sampling || isClosed) return;
    _sampling = true;
    try {
      final snapshot = await _service.sample();
      if (isClosed) return;
      emit(
        state.copyWith(
          snapshot: snapshot,
          icons: _service.icons,
          sampled: true,
        ),
      );
    } finally {
      _sampling = false;
    }
  }

  Future<void> _onQuit(
    ProcessQuitRequested event,
    Emitter<ProcessMonitorState> emit,
  ) async {
    emit(
      state.copyWith(
        busyPids: {...state.busyPids, event.pid},
        clearNotice: true,
      ),
    );

    String? name;
    for (final process in state.snapshot.processes) {
      if (process.pid == event.pid) {
        name = process.name;
        break;
      }
    }

    final outcome = await _service.quit(event.pid, force: event.force);

    emit(
      state.copyWith(
        busyPids: {...state.busyPids}..remove(event.pid),
        notice: PerformanceNotice(
          message:
              outcome.ok
                  ? (event.force
                      ? '${name ?? 'That process'} was forced to quit.'
                      : 'Asked ${name ?? 'that process'} to quit. If it has unsaved '
                          'work it will ask you first.')
                  : (outcome.message ?? 'That process could not be quit.'),
          ok: outcome.ok,
        ),
      ),
    );
  }
}
