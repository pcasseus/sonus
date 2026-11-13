import '../../analytics/application/models/analytics_time_window.dart';

/// One qualified play's genre: the genre of the edition it was played from,
/// else of its release's primary edition; null when neither has one.
class WrappedGenrePlay {
  const WrappedGenrePlay({required this.at, required this.genre});

  /// When the play qualified (UTC).
  final DateTime at;
  final String? genre;
}

/// A finalized weekly Sonus Hot 100 #1, as stored.
class WrappedChartLeader {
  const WrappedChartLeader({
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.songId,
    required this.title,
    required this.artistName,
  });

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  final String songId;
  final String title;
  final String artistName;
}

/// The recorded history Sonus Wrapped reads beside Sonus Pulse. Read only:
/// nothing here writes, derives or stores anything.
abstract interface class WrappedHistoryReader {
  /// Every qualified play in [window] with its genre.
  Future<List<WrappedGenrePlay>> genrePlays(AnalyticsTimeWindow window);

  /// Qualified plays before [utc], all time.
  Future<int> streamsBefore(DateTime utc);

  /// When the [n]th qualified play ever recorded (1-based, in order of
  /// qualification, then id) qualified; null when there are fewer.
  Future<DateTime?> nthStreamAt(int n);

  /// Every finalized weekly Sonus Hot 100 #1, oldest first.
  Future<List<WrappedChartLeader>> weeklyNumberOnes();
}
