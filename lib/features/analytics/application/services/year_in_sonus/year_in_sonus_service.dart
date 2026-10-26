// ignore_for_file: prefer_initializing_formals

import '../../models/analytics_period.dart';
import '../../models/analytics_ranked_entity.dart';
import '../../models/year_in_sonus/year_in_sonus_month.dart';
import '../../models/year_in_sonus/year_in_sonus_ranked_entity.dart';
import '../../models/year_in_sonus/year_in_sonus_recap.dart';
import '../../../domain/entities/qualified_play.dart';
import '../../../domain/repositories/qualified_play_repository.dart';
import '../analytics_behavior_metrics_service.dart';
import '../analytics_entity_ranking_service.dart';
import '../analytics_listening_duration_service.dart';
import '../analytics_summary_service.dart';
import '../listening_artist_attribution.dart';

abstract interface class YearInSonusLoader {
  Future<YearInSonusRecap> load({required int year});
}

class YearInSonusService implements YearInSonusLoader {
  const YearInSonusService({
    required AnalyticsSummaryService summaries,
    required AnalyticsListeningDurationService listeningDurations,
    required AnalyticsBehaviorMetricsService behaviorMetrics,
    required AnalyticsEntityRankingService rankings,
    required QualifiedPlayRepository qualifiedPlays,
    ListeningArtistAttribution? artistAttribution,
  }) : _summaries = summaries,
       _listeningDurations = listeningDurations,
       _behaviorMetrics = behaviorMetrics,
       _rankings = rankings,
       _qualifiedPlays = qualifiedPlays,
       _artistAttribution = artistAttribution;

  final AnalyticsSummaryService _summaries;
  final AnalyticsListeningDurationService _listeningDurations;
  final AnalyticsBehaviorMetricsService _behaviorMetrics;
  final AnalyticsEntityRankingService _rankings;
  final QualifiedPlayRepository _qualifiedPlays;
  final ListeningArtistAttribution? _artistAttribution;

  @override
  Future<YearInSonusRecap> load({required int year}) async {
    if (year < 1) {
      throw ArgumentError.value(year, 'year', 'Must be greater than zero.');
    }

    final referenceLocal = DateTime(year, 1, 1);
    final startLocal = DateTime(year);
    final endLocal = DateTime(year + 1);

    final startUtc = startLocal.toUtc();
    final endUtc = endLocal.toUtc();

    final attributor = await ArtistAttributor.of(_artistAttribution);
    String artistOf(QualifiedPlay play) =>
        attributor.artistFor(artistId: play.artistId, albumId: play.albumId);

    final summaryFuture = _summaries.load(
      period: AnalyticsPeriod.year,
      referenceLocal: referenceLocal,
    );

    final listeningFuture = _listeningDurations.load(
      period: AnalyticsPeriod.year,
      referenceLocal: referenceLocal,
    );

    final behaviorFuture = _behaviorMetrics.load(
      period: AnalyticsPeriod.year,
      referenceLocal: referenceLocal,
    );

    final rankingsFuture = _rankings.load(
      period: AnalyticsPeriod.year,
      referenceLocal: referenceLocal,
    );

    final playsFuture = _qualifiedPlays.getAll(
      qualifiedAtOrAfter: startUtc,
      qualifiedBefore: endUtc,
    );

    final historicalPlaysFuture = _qualifiedPlays.getAll(
      qualifiedBefore: endUtc,
    );

    final monthlyListeningFutures = [
      for (var month = 1; month <= 12; month++)
        _listeningDurations.load(
          period: AnalyticsPeriod.month,
          referenceLocal: DateTime(year, month, 1),
        ),
    ];

    final summary = await summaryFuture;
    final listening = await listeningFuture;
    final behavior = await behaviorFuture;
    final rankings = await rankingsFuture;
    final plays = await playsFuture;
    final historicalPlays = await historicalPlaysFuture;
    final monthlyListening = await Future.wait(monthlyListeningFutures);

    return YearInSonusRecap(
      year: year,
      summary: summary,
      audibleListeningDuration: listening.totalAudibleListeningDuration,
      behavior: behavior,
      topTracks: _mapRanking(rankings.songs, limit: 25),
      topArtists: _mapRanking(rankings.artists, limit: 10),
      topAlbums: _mapRanking(rankings.albums, limit: 10),
      months: _buildMonths(
        year: year,
        plays: plays,
        artistOf: artistOf,
        monthlyListeningDurations: [
          for (final duration in monthlyListening)
            duration.totalAudibleListeningDuration,
        ],
      ),
      longestListeningStreakDays: _longestListeningStreak(plays),
      newArtistIds: _discoveries(
        year: year,
        plays: historicalPlays,
        entityId: artistOf,
      ),
      newAlbumIds: _discoveries(
        year: year,
        plays: historicalPlays,
        entityId: (play) => play.albumId,
      ),
    );
  }

  List<YearInSonusRankedEntity> _mapRanking(
    List<AnalyticsRankedEntity> rankings, {
    required int limit,
  }) {
    final visible = rankings.take(limit).toList(growable: false);

    return List<YearInSonusRankedEntity>.unmodifiable(
      List<YearInSonusRankedEntity>.generate(
        visible.length,
        (index) => YearInSonusRankedEntity(
          entityId: visible[index].entityId,
          rank: index + 1,
          streams: visible[index].qualifiedStreamCount,
        ),
      ),
    );
  }

  List<YearInSonusMonth> _buildMonths({
    required int year,
    required List<QualifiedPlay> plays,
    required String Function(QualifiedPlay play) artistOf,
    required List<Duration> monthlyListeningDurations,
  }) {
    final byMonth = <int, List<QualifiedPlay>>{};

    for (final play in plays) {
      final local = play.qualifiedAt.toLocal();

      if (local.year != year) {
        continue;
      }

      byMonth.putIfAbsent(local.month, () => <QualifiedPlay>[]).add(play);
    }

    return List<YearInSonusMonth>.unmodifiable(
      List<YearInSonusMonth>.generate(12, (index) {
        final monthNumber = index + 1;
        final monthPlays = byMonth[monthNumber] ?? const <QualifiedPlay>[];

        return YearInSonusMonth(
          month: DateTime(year, monthNumber),
          streams: monthPlays.length,
          listeningDuration: monthlyListeningDurations[index],
          topSongId: _topEntity(monthPlays, entityId: (play) => play.songId),
          topArtistId: _topEntity(monthPlays, entityId: artistOf),
        );
      }),
    );
  }

  String? _topEntity(
    List<QualifiedPlay> plays, {
    required String Function(QualifiedPlay play) entityId,
  }) {
    if (plays.isEmpty) {
      return null;
    }

    final stats = <String, _EntityMonthStats>{};

    for (final play in plays) {
      final id = entityId(play);
      final current = stats[id];

      if (current == null) {
        stats[id] = _EntityMonthStats(
          streams: 1,
          lastQualifiedAt: play.qualifiedAt,
        );
        continue;
      }

      stats[id] = _EntityMonthStats(
        streams: current.streams + 1,
        lastQualifiedAt: play.qualifiedAt.isAfter(current.lastQualifiedAt)
            ? play.qualifiedAt
            : current.lastQualifiedAt,
      );
    }

    final entries = stats.entries.toList()
      ..sort((a, b) {
        final streamComparison = b.value.streams.compareTo(a.value.streams);

        if (streamComparison != 0) {
          return streamComparison;
        }

        final recencyComparison = b.value.lastQualifiedAt.compareTo(
          a.value.lastQualifiedAt,
        );

        if (recencyComparison != 0) {
          return recencyComparison;
        }

        return a.key.compareTo(b.key);
      });

    return entries.first.key;
  }

  List<String> _discoveries({
    required int year,
    required List<QualifiedPlay> plays,
    required String Function(QualifiedPlay play) entityId,
  }) {
    final firstPlayByEntity = <String, QualifiedPlay>{};

    for (final play in plays) {
      final id = entityId(play);
      final current = firstPlayByEntity[id];

      if (current == null ||
          play.qualifiedAt.isBefore(current.qualifiedAt) ||
          (play.qualifiedAt == current.qualifiedAt &&
              play.id.compareTo(current.id) < 0)) {
        firstPlayByEntity[id] = play;
      }
    }

    final discovered =
        firstPlayByEntity.entries
            .where((entry) => entry.value.qualifiedAt.toLocal().year == year)
            .toList()
          ..sort((a, b) {
            final timeComparison = a.value.qualifiedAt.compareTo(
              b.value.qualifiedAt,
            );

            if (timeComparison != 0) {
              return timeComparison;
            }

            return a.key.compareTo(b.key);
          });

    return List<String>.unmodifiable(discovered.map((entry) => entry.key));
  }

  int _longestListeningStreak(List<QualifiedPlay> plays) {
    if (plays.isEmpty) {
      return 0;
    }

    final days =
        plays
            .map((play) {
              final local = play.qualifiedAt.toLocal();

              return DateTime(local.year, local.month, local.day);
            })
            .toSet()
            .toList()
          ..sort();

    var longest = 1;
    var current = 1;

    for (var index = 1; index < days.length; index++) {
      final previous = days[index - 1];

      final expectedNext = DateTime(
        previous.year,
        previous.month,
        previous.day + 1,
      );

      if (days[index].isAtSameMomentAs(expectedNext)) {
        current++;

        if (current > longest) {
          longest = current;
        }
      } else {
        current = 1;
      }
    }

    return longest;
  }
}

class _EntityMonthStats {
  const _EntityMonthStats({
    required this.streams,
    required this.lastQualifiedAt,
  });

  final int streams;
  final DateTime lastQualifiedAt;
}
