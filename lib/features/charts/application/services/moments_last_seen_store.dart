/// The newest Moments story when the feed was last open, for the Moments
/// new-content dot (SN-50 R6). No per-story read state.
///
/// Stories are ordered by occurred time, then id, so stories published at
/// the same instant always have one order and marking them seen again
/// changes nothing.
class MomentsSeenMark {
  const MomentsSeenMark({
    required DateTime this.occurredAtUtc,
    required this.storyId,
  });

  /// The feed was open while it had no stories: every story is newer.
  const MomentsSeenMark.empty() : occurredAtUtc = null, storyId = '';

  final DateTime? occurredAtUtc;
  final String storyId;

  /// Whether a story that occurred at [occurredAt] with [id] is newer.
  bool isOlderThan(DateTime occurredAt, String id) {
    final seen = occurredAtUtc;
    if (seen == null) return true;

    final byTime = occurredAt.toUtc().compareTo(seen.toUtc());
    return byTime > 0 || (byTime == 0 && id.compareTo(storyId) > 0);
  }
}

/// Where the newest story seen is kept.
///
/// Until the feed is first open there is no mark, and that first visit
/// records one without showing the dot, however many older stories exist.
/// The same happens after the mark is lost (cleared or restored
/// preferences without it). After that, only stories ordered after the
/// mark show the dot: a story synced in later with an earlier occurred
/// time counts as seen and shows none.
abstract interface class MomentsLastSeenStore {
  /// Null until Moments have been seen on this device.
  Future<MomentsSeenMark?> read();

  Future<void> write(MomentsSeenMark newestSeen);
}
