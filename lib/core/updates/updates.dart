/// Checking for, downloading and installing a new version of the app.
///
/// The split across this folder follows where the work can honestly be done:
/// Dart finds the release and streams the download, because that is where
/// progress can be reported into the UI; `macos/Runner/Updater.swift` verifies
/// the result and exchanges the bundle, because a code signature check and an
/// atomic swap of a running app are platform facts, not Dart ones.
library;

export 'package:tidy/core/updates/app_version.dart';
export 'package:tidy/core/updates/github_release_client.dart';
export 'package:tidy/core/updates/logic/update_bloc.dart';
export 'package:tidy/core/updates/update_bridge.dart';
export 'package:tidy/core/updates/update_release.dart';
export 'package:tidy/core/updates/update_service.dart';
