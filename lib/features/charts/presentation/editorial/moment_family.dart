import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';

/// The kinds of story Sonus Moments tells (SN-45). Every family has its
/// own headlines; a story belongs to exactly one, decided from its
/// recorded facts.
enum MomentFamily {
  // Songs.
  songDebutNumberOne,
  songDebutTop10,
  songDebut,
  songBubblingUnderDebut,
  songHot100Breakthrough,
  songFirstNumberOne,
  songReturnsToNumberOne,
  songNewPeak,
  songPeakMatch,
  songBigClimb,
  songBiggestGainer,
  songReentry,
  songStreamMilestone,
  songWeeksMilestone,

  // Artists.
  artistFirstHot100,
  artistFirstTop10,
  artistNthTop10,
  artistFirstNumberOne,
  artistNthNumberOne,
  artistTopArtist,
  artistStreamMilestone,
  artistSimultaneous,

  // Releases (Albums and EPs; Singles never chart as releases).
  releaseDebutNumberOne,
  releaseDebut,
  releaseReachesNumberOne,
  releaseReturnsToNumberOne,
  releaseNewPeak,
  releaseReentry,
  releaseStreamMilestone,
  releaseWeeksMilestone,
  artistFirstNumberOneRelease,
  artistNthNumberOneRelease;

  /// How much a story matters (SN-45 spam control). Minor stories are
  /// capped per day; the others always appear.
  MomentTier tierFor(int? rank) => switch (this) {
    songDebut =>
      rank != null && rank <= 40 ? MomentTier.notable : MomentTier.minor,
    songBubblingUnderDebut || releaseDebut => MomentTier.minor,
    songStreamMilestone ||
    releaseStreamMilestone ||
    songReentry ||
    releaseReentry ||
    songWeeksMilestone ||
    releaseWeeksMilestone => MomentTier.notable,
    songHot100Breakthrough ||
    songBigClimb ||
    songBiggestGainer ||
    songNewPeak ||
    songPeakMatch ||
    releaseNewPeak ||
    artistFirstHot100 ||
    artistNthTop10 ||
    artistStreamMilestone ||
    artistSimultaneous => MomentTier.notable,
    _ => MomentTier.major,
  };

  bool get isRelease => switch (this) {
    releaseDebutNumberOne ||
    releaseDebut ||
    releaseReachesNumberOne ||
    releaseReturnsToNumberOne ||
    releaseNewPeak ||
    releaseReentry ||
    releaseStreamMilestone ||
    releaseWeeksMilestone ||
    artistFirstNumberOneRelease ||
    artistNthNumberOneRelease => true,
    _ => false,
  };

  bool get isNumberOne => switch (this) {
    songDebutNumberOne ||
    songFirstNumberOne ||
    songReturnsToNumberOne ||
    artistFirstNumberOne ||
    artistNthNumberOne ||
    releaseDebutNumberOne ||
    releaseReachesNumberOne ||
    releaseReturnsToNumberOne ||
    artistFirstNumberOneRelease ||
    artistNthNumberOneRelease => true,
    _ => false,
  };

  /// The story [item] tells, or null when its facts are not news (most
  /// weekly movement, or what the permanent chart already told).
  /// [biggestGainer] marks the week's largest verified climb.
  static MomentFamily? of(
    ChartMomentFeedItem item, {
    bool biggestGainer = false,
  }) {
    final weekly = item.scope == ChartMomentScope.finalized;
    if (item.scope == ChartMomentScope.live) return null;

    ChartMomentEvent? find(ChartMomentEventType type) {
      for (final event in item.events) {
        if (event.eventType == type) return event;
      }
      return null;
    }

    final dominant = item.events.firstWhere(
      (event) => event.eventType == item.dominantEventType,
    );
    final rank = dominant.currentRank;
    final debut = dominant.previousRank == null;

    if (item.dominantEventType == ChartMomentEventType.artistBecomesTopArtist) {
      return weekly ? null : artistTopArtist;
    }
    if (item.dominantEventType == ChartMomentEventType.artistStreamMilestone) {
      return weekly ? null : artistStreamMilestone;
    }

    if (item.chartType == ChartType.albums) {
      final firstNumberOne = find(
        ChartMomentEventType.artistFirstNumberOneAlbum,
      );
      final nthNumberOne = find(ChartMomentEventType.artistNthNumberOneAlbum);
      if (!weekly && firstNumberOne != null) {
        return artistFirstNumberOneRelease;
      }
      if (!weekly && nthNumberOne != null) return artistNthNumberOneRelease;

      return switch (item.dominantEventType) {
        ChartMomentEventType.firstNumberOne =>
          debut ? releaseDebutNumberOne : releaseReachesNumberOne,
        ChartMomentEventType.returnToNumberOne => releaseReturnsToNumberOne,
        ChartMomentEventType.debut
            when rank != null &&
                rank <= (weekly ? 10 : ChartRankingEngine.officialChartLimit) =>
          releaseDebut,
        ChartMomentEventType.newPeak when !weekly || (rank ?? 99) <= 10 =>
          releaseNewPeak,
        ChartMomentEventType.reentry when !weekly || (rank ?? 99) <= 25 =>
          releaseReentry,
        ChartMomentEventType.lifetimeStreamMilestone when !weekly =>
          releaseStreamMilestone,
        ChartMomentEventType.consecutiveWeeksMilestone ||
        ChartMomentEventType.totalWeeksMilestone ||
        ChartMomentEventType.consecutiveThresholdWeeksMilestone ||
        ChartMomentEventType.totalThresholdWeeksMilestone
            when _worthWeeks(dominant) =>
          releaseWeeksMilestone,
        _ => null,
      };
    }

    // Songs: an artist's career fact outranks the song's own news.
    if (!weekly) {
      if (find(ChartMomentEventType.artistFirstNumberOneSong) != null) {
        return artistFirstNumberOne;
      }
      if (find(ChartMomentEventType.artistNthNumberOneSong) != null) {
        return artistNthNumberOne;
      }
    } else {
      if (find(ChartMomentEventType.artistFirstNumberOneSong) != null &&
          item.dominantEventType == ChartMomentEventType.firstNumberOne) {
        return artistFirstNumberOne;
      }
    }

    switch (item.dominantEventType) {
      case ChartMomentEventType.firstNumberOne:
        return debut ? songDebutNumberOne : songFirstNumberOne;
      case ChartMomentEventType.returnToNumberOne:
        return songReturnsToNumberOne;
      default:
        break;
    }

    if (!weekly) {
      final top10 = _career(
        item,
        ChartMomentEventType.artistFirstThresholdSong,
        10,
      );
      if (top10 != null) return artistFirstTop10;
      final nthTop10 = _career(
        item,
        ChartMomentEventType.artistNthThresholdSong,
        10,
      );
      if (nthTop10 != null) return artistNthTop10;
      final hot100 = _career(
        item,
        ChartMomentEventType.artistFirstThresholdSong,
        ChartRankingEngine.officialChartLimit,
      );
      if (hot100 != null) return artistFirstHot100;
    }

    return switch (item.dominantEventType) {
      ChartMomentEventType.debut when rank != null && rank <= 10 =>
        songDebutTop10,
      ChartMomentEventType.debut
          when !weekly &&
              rank != null &&
              rank <= ChartRankingEngine.officialChartLimit =>
        songDebut,
      ChartMomentEventType.debut when !weekly && rank != null =>
        songBubblingUnderDebut,
      ChartMomentEventType.firstThresholdEntry
          when !weekly &&
              dominant.threshold == ChartRankingEngine.officialChartLimit =>
        songHot100Breakthrough,
      ChartMomentEventType.newPeak when !weekly || (rank ?? 99) <= 10 =>
        songNewPeak,
      ChartMomentEventType.peakMatch when weekly && (rank ?? 99) <= 10 =>
        songPeakMatch,
      ChartMomentEventType.rankRise when !weekly => songBigClimb,
      ChartMomentEventType.rankRise when biggestGainer => songBiggestGainer,
      ChartMomentEventType.reentry when !weekly || (rank ?? 99) <= 25 =>
        songReentry,
      ChartMomentEventType.lifetimeStreamMilestone when !weekly =>
        songStreamMilestone,
      ChartMomentEventType.consecutiveWeeksMilestone ||
      ChartMomentEventType.totalWeeksMilestone ||
      ChartMomentEventType.consecutiveThresholdWeeksMilestone ||
      ChartMomentEventType.totalThresholdWeeksMilestone
          when _worthWeeks(dominant) =>
        songWeeksMilestone,
      ChartMomentEventType.artistSimultaneousThresholdSongs
          when (dominant.threshold ?? 99) <= 10 =>
        artistSimultaneous,
      _ => null,
    };
  }

  static ChartMomentEvent? _career(
    ChartMomentFeedItem item,
    ChartMomentEventType type,
    int threshold,
  ) {
    for (final event in item.events) {
      if (event.eventType == type && event.threshold == threshold) {
        return event;
      }
    }
    return null;
  }

  /// Longevity worth a story: five weeks or more, or a second week at #1.
  static bool _worthWeeks(ChartMomentEvent event) {
    final weeks = event.milestoneValue ?? 0;
    return weeks >= 5 || (event.threshold == 1 && weeks >= 2);
  }
}

/// How much a story matters.
enum MomentTier {
  /// Always told: #1s, Top 10 arrivals, career firsts, artist records.
  major,

  /// Always told: climbs, peaks, re-entries, milestones.
  notable,

  /// Capped per day: deep debuts and Bubbling Under arrivals.
  minor,
}
