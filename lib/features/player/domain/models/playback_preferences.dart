import 'package:flutter/foundation.dart';

import 'playback_repeat_mode.dart';

/// Device-local playback preferences.
///
/// When [rememberShuffleAndRepeat] is on, [shuffleEnabled] and [repeatMode]
/// hold the last modes the listener chose and are restored at launch.
@immutable
class PlaybackPreferences {
  const PlaybackPreferences({
    this.rememberShuffleAndRepeat = false,
    this.shuffleEnabled = false,
    this.repeatMode = PlaybackRepeatMode.off,
  });

  static const int version = 1;

  final bool rememberShuffleAndRepeat;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;

  /// Persisted names; must never change once released.
  static const Map<PlaybackRepeatMode, String> repeatModeKeys = {
    PlaybackRepeatMode.off: 'off',
    PlaybackRepeatMode.one: 'one',
    PlaybackRepeatMode.all: 'all',
  };

  PlaybackPreferences copyWith({
    bool? rememberShuffleAndRepeat,
    bool? shuffleEnabled,
    PlaybackRepeatMode? repeatMode,
  }) {
    return PlaybackPreferences(
      rememberShuffleAndRepeat:
          rememberShuffleAndRepeat ?? this.rememberShuffleAndRepeat,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'rememberShuffleAndRepeat': rememberShuffleAndRepeat,
    'shuffleEnabled': shuffleEnabled,
    'repeatMode': repeatModeKeys[repeatMode]!,
  };

  /// Reads [json] field by field. A missing or invalid field falls back to
  /// its default and is reported in [issues]; the rest are kept.
  static PlaybackPreferences fromJson(
    Map<String, Object?> json,
    List<String> issues,
  ) {
    const defaults = PlaybackPreferences();

    final remember = json['rememberShuffleAndRepeat'];
    final shuffle = json['shuffleEnabled'];
    final repeatKey = json['repeatMode'];
    PlaybackRepeatMode? repeat;
    for (final entry in repeatModeKeys.entries) {
      if (entry.value == repeatKey) {
        repeat = entry.key;
      }
    }

    if (remember is! bool) issues.add('rememberShuffleAndRepeat');
    if (shuffle is! bool) issues.add('shuffleEnabled');
    if (repeat == null) issues.add('repeatMode');

    return PlaybackPreferences(
      rememberShuffleAndRepeat: remember is bool
          ? remember
          : defaults.rememberShuffleAndRepeat,
      shuffleEnabled: shuffle is bool ? shuffle : defaults.shuffleEnabled,
      repeatMode: repeat ?? defaults.repeatMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackPreferences &&
      other.rememberShuffleAndRepeat == rememberShuffleAndRepeat &&
      other.shuffleEnabled == shuffleEnabled &&
      other.repeatMode == repeatMode;

  @override
  int get hashCode =>
      Object.hash(rememberShuffleAndRepeat, shuffleEnabled, repeatMode);
}
