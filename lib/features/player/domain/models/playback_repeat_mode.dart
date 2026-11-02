enum PlaybackRepeatMode {
  off,
  one,
  all;

  /// The mode a repeat button moves to, the same everywhere (in the app,
  /// the notification and the car): Off, All, One, then Off again.
  PlaybackRepeatMode get next => switch (this) {
    PlaybackRepeatMode.off => PlaybackRepeatMode.all,
    PlaybackRepeatMode.all => PlaybackRepeatMode.one,
    PlaybackRepeatMode.one => PlaybackRepeatMode.off,
  };
}
