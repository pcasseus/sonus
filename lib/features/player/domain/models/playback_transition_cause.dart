enum PlaybackTransitionCause {
  automatic,
  skipNext,
  skipPrevious,
  skipToIndex,

  /// The playing entry ended and started over by itself (Repeat One, or
  /// Repeat All over one entry): a new play of the same entry, reported
  /// by the engine without a change of entry (BUG-11 hardening).
  repeated,
}
