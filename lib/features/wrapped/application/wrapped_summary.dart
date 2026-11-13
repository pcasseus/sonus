import '../../analytics/application/models/pulse/pulse_period.dart';
import '../../analytics/application/services/pulse/pulse_entity_directory.dart';

/// Where a period stands against recorded history and today.
enum WrappedPeriodState {
  /// Starts after today.
  future,

  /// Ends before the first recorded session: nothing could be recorded.
  beforeHistory,

  /// Contains today: a summary so far, never a finished Wrapped.
  inProgress,

  /// Over, with history covering at least part of it.
  complete,
}

/// The headline numbers of a period. Every value comes from recorded
/// listening; see `docs/wrapped/METRICS.md` for each definition.
class WrappedTotals {
  const WrappedTotals({
    required this.streams,
    required this.listened,
    required this.allPlays,
    required this.activeDays,
    required this.songs,
    required this.artists,
    required this.albums,
  });

  /// Qualified plays.
  final int streams;

  /// Audible listening time from listening segments.
  final Duration listened;

  /// Sessions with any audible time (skips included).
  final int allPlays;

  /// Days with at least one stream.
  final int activeDays;

  /// Distinct songs, artists (lead artist) and Albums & EPs streamed.
  final int songs;
  final int artists;
  final int albums;

  static const zero = WrappedTotals(
    streams: 0,
    listened: Duration.zero,
    allPlays: 0,
    activeDays: 0,
    songs: 0,
    artists: 0,
    albums: 0,
  );
}

/// A song, artist or release in a top list, ranked by streams.
class WrappedRankedItem {
  const WrappedRankedItem({
    required this.rank,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.streams,
    required this.listened,
    required this.status,
    this.badge,
  });

  final int rank;
  final String id;
  final String title;
  final String subtitle;
  final int streams;
  final Duration listened;

  /// Current, blocked, unavailable or historical (no longer in the
  /// library), as Sonus Pulse shows it.
  final PulseEntityStatus status;

  /// The Insights label for that status ("UNAVAILABLE", "HISTORICAL" ...),
  /// or null for an ordinary current item.
  final String? badge;
}

/// A genre's streams in the period.
class WrappedGenreShare {
  const WrappedGenreShare({
    required this.genre,
    required this.streams,
    required this.share,
  });

  /// The canonical category for an exact alias, otherwise the genre as
  /// written.
  final String genre;
  final int streams;

  /// Of the period's streams that have a genre (0–1).
  final double share;
}

/// Listening in one day, week or month of the period.
class WrappedActivityPoint {
  const WrappedActivityPoint({
    required this.startLocal,
    required this.endLocal,
    required this.streams,
    required this.listened,
    required this.recorded,
  });

  final DateTime startLocal;

  /// Exclusive.
  final DateTime endLocal;
  final int streams;
  final Duration listened;

  /// False for time before history began or after today: never drawn as
  /// zero listening.
  final bool recorded;
}

/// A month of a year's table.
class WrappedMonthRow {
  const WrappedMonthRow({
    required this.period,
    required this.state,
    required this.totals,
    this.topSong,
    this.topArtist,
  });

  final PulsePeriod period;
  final WrappedPeriodState state;
  final WrappedTotals totals;
  final WrappedRankedItem? topSong;
  final WrappedRankedItem? topArtist;
}

enum WrappedComparisonState {
  available,

  /// The previous period is not fully covered by history.
  notEnoughHistory,
}

/// This period against the one before it, only when history covers both.
class WrappedComparison {
  const WrappedComparison({
    required this.previous,
    required this.state,
    this.totals,
  });

  final PulsePeriod previous;
  final WrappedComparisonState state;

  /// The previous period's totals; null unless available.
  final WrappedTotals? totals;

  bool get isAvailable => state == WrappedComparisonState.available;
}

enum WrappedMilestoneKind {
  /// The [WrappedMilestone.value]th stream ever recorded in Sonus happened
  /// in this period.
  lifetimeStreams,

  /// The most consecutive days with a stream, within the period.
  longestStreak,

  /// The day with the most streams.
  busiestDay,
}

class WrappedMilestone {
  const WrappedMilestone({
    required this.kind,
    required this.value,
    required this.atLocal,
    this.untilLocal,
  });

  final WrappedMilestoneKind kind;
  final int value;

  /// When it happened, or the first day of a streak.
  final DateTime atLocal;

  /// The last day of a streak.
  final DateTime? untilLocal;
}

/// A weekly Sonus Hot 100 #1 from a week that ended in this period.
class WrappedChartNumberOne {
  const WrappedChartNumberOne({
    required this.songId,
    required this.title,
    required this.artistName,
    required this.weeks,
    required this.firstWeekStartLocal,
  });

  final String songId;
  final String title;
  final String artistName;

  /// Weeks at #1 among the period's weeks.
  final int weeks;
  final DateTime firstWeekStartLocal;
}

/// Everything Sonus Wrapped shows for one month or year. Built only from
/// recorded listening and stored charts; nothing is estimated.
class WrappedSummary {
  const WrappedSummary({
    required this.period,
    required this.state,
    required this.historyStartLocal,
    required this.totals,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.genres,
    required this.streamsWithoutGenre,
    required this.days,
    required this.weeks,
    required this.months,
    required this.comparison,
    required this.milestones,
    required this.chartNumberOnes,
    required this.chartWeeks,
  });

  final PulsePeriod period;
  final WrappedPeriodState state;

  /// When recorded history begins, if it begins inside this period (the
  /// period is then partial); null otherwise.
  final DateTime? historyStartLocal;
  final WrappedTotals totals;
  final List<WrappedRankedItem> topSongs;
  final List<WrappedRankedItem> topArtists;
  final List<WrappedRankedItem> topAlbums;
  final List<WrappedGenreShare> genres;

  /// Streams whose release has no genre: never guessed into one.
  final int streamsWithoutGenre;

  /// Every day of the period.
  final List<WrappedActivityPoint> days;

  /// Monday-to-Sunday weeks, clipped to the period.
  final List<WrappedActivityPoint> weeks;

  /// For a year: its twelve months, each as its own monthly Wrapped would
  /// count it. Empty for a month.
  final List<WrappedMonthRow> months;
  final WrappedComparison comparison;
  final List<WrappedMilestone> milestones;
  final List<WrappedChartNumberOne> chartNumberOnes;

  /// Finalized Sonus Hot 100 weeks that ended in this period.
  final int chartWeeks;

  WrappedRankedItem? get mostPlayedSong => topSongs.firstOrNull;
  WrappedRankedItem? get mostPlayedArtist => topArtists.firstOrNull;

  /// The month with the most streams (the earlier on a tie); null for a
  /// month or a year without streams.
  WrappedMonthRow? get mostActiveMonth {
    WrappedMonthRow? best;
    for (final month in months) {
      if (month.totals.streams == 0) continue;
      if (best == null || month.totals.streams > best.totals.streams) {
        best = month;
      }
    }
    return best;
  }

  bool get hasListening =>
      totals.streams > 0 || totals.listened > Duration.zero;
  bool get isPartial =>
      state == WrappedPeriodState.inProgress || historyStartLocal != null;
}
