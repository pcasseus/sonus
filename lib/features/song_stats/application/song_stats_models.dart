import '../../charts/domain/entities/chart_entry.dart';
import '../../library/application/models/library_track.dart';

/// Where the song stands in the library now (the Pulse / chart labels).
enum SongStatsStatus {
  current,
  blacklisted,
  unavailable,
  historical;

  /// "BLACKLISTED", "UNAVAILABLE", "HISTORICAL", or null.
  String? get badge => switch (this) {
    SongStatsStatus.current => null,
    SongStatsStatus.blacklisted => 'BLACKLISTED',
    SongStatsStatus.unavailable => 'UNAVAILABLE',
    SongStatsStatus.historical => 'HISTORICAL',
  };

  static SongStatsStatus of(LibraryTrack? track) => track == null
      ? SongStatsStatus.historical
      : track.isBlocked
      ? SongStatsStatus.blacklisted
      : !track.isAvailable || (track.filePath?.trim().isEmpty ?? true)
      ? SongStatsStatus.unavailable
      : SongStatsStatus.current;
}

/// The song's name, credit and artwork: from the library when it is there,
/// otherwise from what was recorded (last play, then the chart), never
/// invented.
class SongStatsIdentity {
  const SongStatsIdentity({
    required this.songId,
    required this.title,
    required this.artistLine,
    required this.status,
    this.albumTitle,
    this.artworkPath,
    this.track,
  });

  final String songId;
  final String title;
  final String artistLine;
  final String? albumTitle;
  final String? artworkPath;
  final SongStatsStatus status;

  /// The library track, when the song is still in the library.
  final LibraryTrack? track;

  bool get isPlayable => status == SongStatsStatus.current && track != null;
}

/// How a finalized week relates to the song's previous recorded week.
enum SongChartWeekEvent {
  /// First recorded Top 200 appearance.
  debut,

  /// Back after at least one week off the Top 200.
  reentry,

  /// Same chart as last week: up, down or unchanged.
  up,
  down,
  same,

  /// From Bubbling Under into the Hot 100.
  promoted,

  /// From the Hot 100 down to Bubbling Under.
  demoted,
}

/// One finalized week the song held a position in (Top 200).
class SongChartWeek {
  const SongChartWeek({
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.rank,
    required this.event,
    required this.newPeak,
    required this.hot100Debut,
    this.previousRank,
    this.weeksOff = 0,
  });

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  final int rank;

  /// The rank in the immediately preceding chart week; null when the song
  /// was not in that week's Top 200.
  final int? previousRank;

  final SongChartWeekEvent event;

  /// Better than every earlier finalized position (never on a debut).
  final bool newPeak;

  /// The first recorded week inside the Hot 100.
  final bool hot100Debut;

  /// Weeks off the chart before a re-entry.
  final int weeksOff;

  bool get isHot100 => rank <= 100;

  /// Places moved within one chart (positive = up); null across charts,
  /// on debuts and re-entries.
  int? get positions => switch (event) {
    SongChartWeekEvent.up ||
    SongChartWeekEvent.down ||
    SongChartWeekEvent.same => previousRank! - rank,
    _ => null,
  };
}

/// The song's place on the chart week in progress (provisional).
class SongLiveChart {
  const SongLiveChart({
    required this.entry,
    required this.weekStartUtc,
    required this.weekEndUtc,
    this.bestSoFarRank,
  });

  final ChartEntry entry;
  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  final int? bestSoFarRank;

  int get rank => entry.rank;
  bool get isHot100 => entry.rank <= 100;
}

/// The song's place in the career standings: the all-time chart the
/// Charts page opens on ("Career standings"), ranked by lifetime streams.
/// It is a different chart from the live week: a song played a lot this
/// week but rarely before can be high this week and low in its career.
class SongCareerStanding {
  const SongCareerStanding({required this.rank});

  final int rank;
  bool get isHot100 => rank <= 100;
}

/// The song's recorded chart history: finalized weeks (permanent) and the
/// live week (provisional), kept apart, and its career standing.
class SongChartHistory {
  SongChartHistory({required List<SongChartWeek> weeks, this.live, this.career})
    : weeks = List.unmodifiable(weeks);

  static final SongChartHistory none = SongChartHistory(weeks: const []);

  /// Finalized weeks, oldest first.
  final List<SongChartWeek> weeks;
  final SongLiveChart? live;

  /// Null when the song is not in the career standings' top 200.
  final SongCareerStanding? career;

  bool get isEmpty => weeks.isEmpty && live == null && career == null;
  bool get hasFinalized => weeks.isNotEmpty;

  SongChartWeek? get lastFinalized => weeks.isEmpty ? null : weeks.last;
  SongChartWeek? get debut => weeks.isEmpty ? null : weeks.first;

  SongChartWeek? get hot100Debut {
    for (final week in weeks) {
      if (week.hot100Debut) return week;
    }
    return null;
  }

  /// The best finalized position; live positions never count.
  int? get peakRank {
    int? best;
    for (final week in weeks) {
      if (best == null || week.rank < best) best = week.rank;
    }
    return best;
  }

  int get weeksAtPeak {
    final peak = peakRank;
    return peak == null ? 0 : weeks.where((w) => w.rank == peak).length;
  }

  /// The first finalized week the peak was reached.
  SongChartWeek? get firstPeakWeek {
    final peak = peakRank;
    if (peak == null) return null;
    for (final week in weeks) {
      if (week.rank == peak) return week;
    }
    return null;
  }

  int get hot100Weeks => weeks.where((w) => w.isHot100).length;
  int get bubblingUnderWeeks => weeks.where((w) => !w.isHot100).length;
  int get reentries =>
      weeks.where((w) => w.event == SongChartWeekEvent.reentry).length;
}

/// One chart week (Sunday to Sunday, local) of the song's listening.
class SongListeningWeek {
  const SongListeningWeek({
    required this.weekStartLocal,
    required this.listened,
    required this.streams,
    required this.allPlays,
    required this.inProgress,
  });

  final DateTime weekStartLocal;
  final Duration listened;
  final int streams;
  final int allPlays;

  /// The current week, still running.
  final bool inProgress;
}

/// The song's recorded listening (Sonus Pulse definitions).
class SongListeningStats {
  SongListeningStats({
    required this.streams,
    required this.listened,
    required this.allPlays,
    required this.firstPlayedAt,
    required this.lastPlayedAt,
    required List<SongListeningWeek> weeks,
    this.historyStartedAt,
  }) : weeks = List.unmodifiable(weeks);

  /// Lifetime qualified streams.
  final int streams;

  /// Audible listening time from listening segments.
  final Duration listened;

  /// Sessions with audible time.
  final int allPlays;

  /// First and most recent recorded session with audible time.
  final DateTime? firstPlayedAt;
  final DateTime? lastPlayedAt;

  /// Recent chart weeks, oldest first, never before recorded history began.
  final List<SongListeningWeek> weeks;

  /// When Sonus' recorded listening history begins (any song).
  final DateTime? historyStartedAt;

  bool get hasAny => streams > 0 || allPlays > 0 || listened > Duration.zero;
}

class SongStats {
  const SongStats({
    required this.identity,
    required this.chart,
    required this.listening,
  });

  final SongStatsIdentity identity;
  final SongChartHistory chart;
  final SongListeningStats listening;
}
