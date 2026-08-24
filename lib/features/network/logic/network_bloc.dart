import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/features/network/data/models/network_series.dart';
import 'package:tidy/features/network/data/services/network_service.dart';
import 'package:tidy/features/network/logic/network_event.dart';
import 'package:tidy/features/network/logic/network_state.dart';

export 'network_event.dart';
export 'network_state.dart';

/// The Network page's state.
///
/// There is no timer here, and that is the point: the native sampler is already
/// reading the counters once a second for the menu bar, so this subscribes to
/// what it publishes rather than starting a second clock over the same numbers.
/// What the bloc owns is *when the tap is open* — see [NetworkVisibilityChanged].
class NetworkBloc extends Bloc<NetworkEvent, NetworkState> {
  NetworkBloc(this._service) : super(const NetworkState()) {
    on<LoadNetwork>(_onLoad);
    on<NetworkRangeChanged>(_onRangeChanged);
    on<NetworkSampled>(_onSampled);
    on<NetworkVisibilityChanged>(_onVisibilityChanged);
  }

  final NetworkService _service;
  StreamSubscription<NetworkSample>? _samples;

  Future<void> _onLoad(LoadNetwork event, Emitter<NetworkState> emit) async {
    if (event.refresh) _service.invalidate();
    emit(state.copyWith(status: NetworkStatus.loading));

    final results = await Future.wait([
      _service.series(state.range, refresh: event.refresh),
      _service.headline(),
    ]);

    emit(
      state.copyWith(
        status: NetworkStatus.ready,
        series: results[0] as NetworkSeries,
        headline: results[1] as NetworkHeadline,
      ),
    );
  }

  Future<void> _onRangeChanged(
    NetworkRangeChanged event,
    Emitter<NetworkState> emit,
  ) async {
    if (event.range == state.range) return;
    // The range moves immediately and the chart catches up. Holding the old
    // chart until the new buckets arrive makes the segmented control feel like
    // it did not register the click.
    emit(state.copyWith(range: event.range, status: NetworkStatus.loading));
    final series = await _service.series(event.range);
    emit(state.copyWith(status: NetworkStatus.ready, series: series));
  }

  void _onSampled(NetworkSampled event, Emitter<NetworkState> emit) {
    final sample = event.sample;

    // The first payload of a subscription carries the sampler's whole ring, so
    // a page that has just opened draws a populated chart rather than filling
    // one in a pixel at a time over the next five minutes.
    final ticks =
        sample.recent.isNotEmpty
            ? List<NetworkTick>.from(sample.recent)
            : <NetworkTick>[...state.ticks, sample.tick];

    if (ticks.length > NetworkState.liveCapacity) {
      ticks.removeRange(0, ticks.length - NetworkState.liveCapacity);
    }

    emit(state.copyWith(sample: sample, ticks: ticks));
  }

  Future<void> _onVisibilityChanged(
    NetworkVisibilityChanged event,
    Emitter<NetworkState> emit,
  ) async {
    if (event.visible == state.live) return;

    if (!event.visible) {
      await _samples?.cancel();
      _samples = null;
      await _service.stopLive();
      emit(state.copyWith(live: false));
      return;
    }

    _samples = _service.onSample.listen((sample) => add(NetworkSampled(sample)));
    emit(state.copyWith(live: true));

    // Opening the tap answers with the reading that was already there, ring and
    // all, so the chart is populated before the next tick arrives.
    final sample = await _service.startLive();
    if (sample.isKnown) add(NetworkSampled(sample));

    // Coming back to the page after a while: buckets have closed since the last
    // read, so the totals on screen are stale.
    add(const LoadNetwork(refresh: true));
  }

  @override
  Future<void> close() async {
    await _samples?.cancel();
    await _service.stopLive();
    return super.close();
  }
}
