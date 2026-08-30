import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/updates/logic/update_event.dart';
import 'package:tidy/core/updates/logic/update_state.dart';
import 'package:tidy/core/updates/update_service.dart';

export 'package:tidy/core/updates/logic/update_event.dart';
export 'package:tidy/core/updates/logic/update_state.dart';

/// Drives the update check, the download and the handoff to the installer.
///
/// Lives above the shell's branches rather than inside the Settings page: the
/// check runs at launch whether or not anyone opens Settings, and the toast
/// that announces a new version is shown by the shell. One instance, two
/// readers — the same reason `ScanBloc` is hoisted.
class UpdateBloc extends Bloc<UpdateEvent, UpdateState> {
  UpdateBloc(this._service, {required AppSettings settings})
    : _settings = settings,
      super(const UpdateState()) {
    on<CheckForUpdates>(_onCheck);
    on<DownloadUpdate>(_onDownload);
    on<CancelDownload>(_onCancel);
    on<InstallUpdate>(_onInstall);
    on<SkipThisVersion>(_onSkip);
    on<UpdateProgressed>(_onProgress);
    on<UpdateBootstrapped>(_onBootstrapped);

    // Ten minutes, against a thirty-minute interval in the service. The timer
    // is deliberately the faster of the two: it only *offers* a check, and the
    // service decides whether enough time has passed to take it up. Ticking
    // faster than the gate is what stops a tick that lands a minute early from
    // being swallowed and pushing the real check out by a whole period — and it
    // is how a Mac that was asleep through its slot picks the check up within
    // minutes of waking rather than hours.
    //
    // The cost of a tick that the gate declines is a comparison of two dates.
    _timer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => add(const CheckForUpdates()),
    );

    unawaited(_readCurrentVersion());
  }

  final UpdateService _service;
  final AppSettings _settings;
  late final Timer _timer;

  Future<void> _readCurrentVersion() async {
    final version = await _service.currentVersion();
    if (isClosed) return;
    add(UpdateBootstrapped(version.display, _settings.lastUpdateCheckAt));
  }

  void _onBootstrapped(UpdateBootstrapped event, Emitter<UpdateState> emit) {
    emit(
      state.copyWith(
        currentVersion: event.currentVersion,
        lastCheckedAt: event.lastCheckedAt,
      ),
    );
  }

  Future<void> _onCheck(
    CheckForUpdates event,
    Emitter<UpdateState> emit,
  ) async {
    // A download or an install in flight outranks a timer waking up.
    if (state.isBusy || state.status == UpdateStatus.readyToInstall) return;

    // An update already on offer is not re-asked for in the background.
    //
    // Nothing a second answer could add — the release is known and the chip is
    // up — and running the check anyway would take the chip away twice over:
    // once for the `checking` emit below, which `hasUpdate` does not cover, and
    // again if the interval gate declined and answered `skipped`. On a
    // ten-minute timer that is a prompt that blinks out of the sidebar every
    // ten minutes. A manual check still runs: pressing the button is asking.
    if (!event.manual && state.hasUpdate) return;

    // What to fall back to for an outcome that establishes nothing.
    final before = state.status;
    emit(state.copyWith(status: UpdateStatus.checking, clearError: true));
    final result = await _service.check(manual: event.manual);

    final checkedAt = _settings.lastUpdateCheckAt;
    switch (result.outcome) {
      case UpdateCheckOutcome.available:
        final release = result.release!;
        // A skipped version stays skipped until a newer one arrives, and a
        // manual check overrides the skip — pressing the button is asking.
        if (!event.manual && release.tag == _settings.skippedUpdateVersion) {
          emit(
            state.copyWith(status: UpdateStatus.idle, lastCheckedAt: checkedAt),
          );
          return;
        }
        emit(
          state.copyWith(
            status: UpdateStatus.available,
            release: release,
            lastCheckedAt: checkedAt,
            receivedBytes: 0,
            totalBytes: release.zipBytes,
          ),
        );
      case UpdateCheckOutcome.upToDate:
        emit(
          state.copyWith(
            status: UpdateStatus.upToDate,
            release: result.release,
            lastCheckedAt: checkedAt,
          ),
        );
      case UpdateCheckOutcome.skipped:
        // Nothing was asked, so nothing is known that was not known a moment
        // ago. Only the `checking` status set above is undone — forcing `idle`
        // here would throw away whatever the last real check had established.
        emit(state.copyWith(status: before, lastCheckedAt: checkedAt));
      case UpdateCheckOutcome.unreachable:
        // Only a check someone asked for reports a failure. A background check
        // that could not reach GitHub is not news.
        emit(
          event.manual
              ? state.copyWith(
                status: UpdateStatus.failed,
                error:
                    'Could not reach GitHub to check for updates. '
                    'Check your connection and try again.',
                lastCheckedAt: checkedAt,
              )
              // Nor does it undo what was already known: back to whatever
              // the status was before this check started, not to `idle`.
              : state.copyWith(status: before, lastCheckedAt: checkedAt),
        );
    }
  }

  Future<void> _onDownload(
    DownloadUpdate event,
    Emitter<UpdateState> emit,
  ) async {
    final release = state.release;
    if (release == null || state.isBusy) return;

    emit(
      state.copyWith(
        status: UpdateStatus.downloading,
        receivedBytes: 0,
        totalBytes: release.zipBytes,
        clearError: true,
      ),
    );

    final file = await _service.download(
      release,
      onProgress: (received, total) {
        if (!isClosed) add(UpdateProgressed(received, total));
      },
    );

    if (isClosed) return;
    if (file == null) {
      // Cancelling lands here too, and a cancel is not a failure — the state
      // it should leave behind is the offer to try again.
      if (state.status == UpdateStatus.downloading) {
        emit(
          state.copyWith(
            status: UpdateStatus.failed,
            error:
                'The download did not finish. Check your connection and '
                'try again.',
          ),
        );
      }
      return;
    }

    emit(state.copyWith(status: UpdateStatus.verifying));
    final prepared = await _service.prepare(release);
    if (isClosed) return;

    if (!prepared.ok) {
      AppLog.updates.warn(
        'the downloaded update was rejected',
        fields: {'version': release.version.display, 'why': prepared.message},
      );
      emit(
        state.copyWith(
          status: UpdateStatus.failed,
          error: prepared.message ?? 'The update could not be verified.',
          canRetryManually: prepared.canRetryManually,
        ),
      );
      await _service.discard();
      return;
    }

    emit(state.copyWith(status: UpdateStatus.readyToInstall));
  }

  void _onProgress(UpdateProgressed event, Emitter<UpdateState> emit) {
    if (state.status != UpdateStatus.downloading) return;
    emit(
      state.copyWith(
        receivedBytes: event.received,
        totalBytes: event.total > 0 ? event.total : state.totalBytes,
      ),
    );
  }

  Future<void> _onCancel(
    CancelDownload event,
    Emitter<UpdateState> emit,
  ) async {
    if (state.status != UpdateStatus.downloading) return;
    emit(state.copyWith(status: UpdateStatus.available, receivedBytes: 0));
    await _service.discard();
  }

  Future<void> _onInstall(
    InstallUpdate event,
    Emitter<UpdateState> emit,
  ) async {
    if (state.status != UpdateStatus.readyToInstall) return;

    emit(state.copyWith(status: UpdateStatus.installing, clearError: true));
    final failure = await _service.install();

    // Reaching here at all means it did not work: on success the app is being
    // torn down while a helper waits to reopen the new copy.
    if (isClosed || failure == null) return;
    emit(
      state.copyWith(
        status: UpdateStatus.failed,
        error: failure,
        canRetryManually: true,
      ),
    );
  }

  Future<void> _onSkip(SkipThisVersion event, Emitter<UpdateState> emit) async {
    final release = state.release;
    if (release == null) return;
    _settings.skippedUpdateVersion = release.tag;
    emit(state.copyWith(status: UpdateStatus.idle, clearError: true));
    await _service.discard();
  }

  @override
  Future<void> close() async {
    _timer.cancel();
    await _service.cancelDownload();
    return super.close();
  }
}
