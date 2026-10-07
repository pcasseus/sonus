typedef MusicBrainzClock = DateTime Function();
typedef MusicBrainzDelay = Future<void> Function(Duration duration);

class MusicBrainzRateLimiter {
  MusicBrainzRateLimiter({
    this.minimumInterval = const Duration(seconds: 1),
    MusicBrainzClock? clock,
    MusicBrainzDelay? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final Duration minimumInterval;
  final MusicBrainzClock _clock;
  final MusicBrainzDelay _delay;

  DateTime? _lastStartedAt;
  Future<void> _tail = Future<void>.value();

  Future<void> waitForTurn() {
    final next = _tail.then((_) => _waitForTurnInternal());

    _tail = next.then<void>((_) {}, onError: (_) {});

    return next;
  }

  Future<void> _waitForTurnInternal() async {
    final lastStartedAt = _lastStartedAt;

    if (lastStartedAt != null) {
      final now = _clock();
      final elapsed = now.difference(lastStartedAt);

      if (elapsed < minimumInterval) {
        await _delay(minimumInterval - elapsed);
      }
    }

    _lastStartedAt = _clock();
  }
}
