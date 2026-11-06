import 'package:flutter/foundation.dart';

/// The Git commit this build was made from, passed by
/// `tool/build-release.ps1` as `--dart-define=SONUS_BUILD_COMMIT=...`.
/// Empty when the build was made without it.
const String sonusBuildCommit = String.fromEnvironment('SONUS_BUILD_COMMIT');

/// When this build was made (UTC, ISO 8601), passed as
/// `--dart-define=SONUS_BUILD_TIME=...`. Empty when not recorded.
const String sonusBuildTime = String.fromEnvironment('SONUS_BUILD_TIME');

/// How this build was compiled.
enum SonusBuildMode {
  debug('Debug'),
  profile('Profile'),
  release('Release');

  const SonusBuildMode(this.label);

  final String label;

  static SonusBuildMode get current => kReleaseMode
      ? release
      : kProfileMode
      ? profile
      : debug;
}

/// Identifies the installed build, so a device report can be matched to
/// the exact commit. Holds no personal data and no configuration values.
@immutable
class SonusBuildInfo {
  const SonusBuildInfo({
    required this.commit,
    required this.time,
    required this.mode,
  });

  /// This build, from the compile-time defines.
  static final SonusBuildInfo current = SonusBuildInfo(
    commit: sonusBuildCommit,
    time: sonusBuildTime,
    mode: SonusBuildMode.current,
  );

  static const String commitNotRecorded =
      'Not recorded — built without Git metadata';
  static const String timeNotRecorded = 'Not recorded';

  final String commit;
  final String time;
  final SonusBuildMode mode;

  bool get hasCommit => commit.trim().isNotEmpty;

  String get commitLabel => hasCommit ? commit.trim() : commitNotRecorded;

  String get timeLabel => time.trim().isEmpty ? timeNotRecorded : time.trim();

  String get modeLabel => mode.label;

  /// One line for reports, e.g. "4d640c4 · Debug · 2026-11-06T10:00:00Z".
  String get displayString => [
    commitLabel,
    modeLabel,
    if (time.trim().isNotEmpty) time.trim(),
  ].join(' · ');
}
