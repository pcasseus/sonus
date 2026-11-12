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
  artistNthNumberOneRelease,

  // SN-50: new event pathways, told only by the story planner.

  /// An artist's song replaces the same artist's song at #1.
  songSelfReplacement,

  /// A first entry into one chart zone (Top 75 … Top 2).
  songFirstThreshold,

  /// First entries into several zones in one move, named together.
  songThresholds,

  /// An artist's repeat #1 on a weekly chart, counted on that chart.
  artistRepeatNumberOne,
  releaseSelfReplacement,
  releaseFirstThreshold,
  releaseThresholds,
  artistRepeatNumberOneRelease,

  /// Several releases by one artist in a zone at once.
  artistSimultaneousReleases,

  /// SN-50 chart jumps (approved): a weekly climb of 25+ places within the
  /// Hot 100.
  songHot100MajorJump,

  /// SN-50 chart jumps (approved): 3+ consecutive weekly Hot 100 climbs
  /// worth 30+ places together.
  songHot100ClimbRun,

  /// SN-50 BUG-04 (approved rule 2): a weekly fall of 30+ places within
  /// Sonus Bubbling Under. Refined rules only.
  songBubblingUnderFall,

  /// SN-50 BUG-04 (approved rule 3): a notable weekly exit from the Hot
  /// 100 into Sonus Bubbling Under. Refined rules only.
  songHot100Exit,

  // SN-50 complete coverage: a release climbing the Albums & EPs chart
  // (device-polish stories only; ClimbHeadlines has its lines).
  releaseClimb,

  // App Update 1.1 (Moments chronicle): all-time stories from the
  // chronicle start, told by MomentChronicle.

  /// One play's climb told with the new peak and the zone it enters (for
  /// the first time) or returns to: one story, not one per fact.
  songChartMove,
  releaseChartMove,

  /// #1 at the close of a completed chart day, with its consecutive days.
  songNumberOneHold,
  releaseNumberOneHold,

  /// Back on the Hot 100 from Bubbling Under, having charted on it before.
  songHot100Return,

  /// Pushed off the Hot 100 onto Bubbling Under (#101).
  songHot100Departure,

  /// Pushed out of the Top 200: off the Sonus charts.
  songChartDeparture,
  releaseChartDeparture,

  // App Update 1.2 (REF-19): artist dominance on the weekly Sonus Hot 100,
  // told by the story planner once their lines are approved.

  /// Every position from #1 to #3, #5 or #10 belongs to one artist.
  artistChartSweep,

  /// One artist has 3, 5 or 10 songs in the Top 10.
  artistTop10Presence,

  /// One artist has 5, 10, 15 or 20 songs on the Hot 100.
  artistHot100Presence;

  /// The App Update 1.2 artist-dominance families.
  bool get isArtistDominance => switch (this) {
    artistChartSweep || artistTop10Presence || artistHot100Presence => true,
    _ => false,
  };

  /// The App Update 1.1 chronicle families.
  bool get isChronicle => switch (this) {
    songChartMove ||
    releaseChartMove ||
    songNumberOneHold ||
    releaseNumberOneHold ||
    songHot100Return ||
    songHot100Departure ||
    songChartDeparture ||
    releaseChartDeparture => true,
    _ => false,
  };

  /// How much a story matters (SN-45 spam control). Minor stories are
  /// capped per day; the others always appear.
  MomentTier tierFor(int? rank) => switch (this) {
    songDebut || songHot100MajorJump =>
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
    releaseClimb ||
    artistFirstHot100 ||
    artistNthTop10 ||
    artistStreamMilestone ||
    artistSimultaneous ||
    songThresholds ||
    releaseThresholds ||
    artistSimultaneousReleases ||
    artistTop10Presence ||
    artistHot100Presence ||
    songHot100ClimbRun => MomentTier.notable,
    // Capped like other minor stories; an exit after a verified Top 40
    // peak is planned as mandatory (uncapped) instead.
    songBubblingUnderFall || songHot100Exit => MomentTier.minor,
    _ => MomentTier.major,
  };

  bool get isRelease => switch (this) {
    releaseChartMove ||
    releaseNumberOneHold ||
    releaseChartDeparture ||
    releaseClimb ||
    releaseDebutNumberOne ||
    releaseDebut ||
    releaseReachesNumberOne ||
    releaseReturnsToNumberOne ||
    releaseNewPeak ||
    releaseReentry ||
    releaseStreamMilestone ||
    releaseWeeksMilestone ||
    artistFirstNumberOneRelease ||
    artistNthNumberOneRelease ||
    releaseSelfReplacement ||
    releaseFirstThreshold ||
    releaseThresholds ||
    artistRepeatNumberOneRelease ||
    artistSimultaneousReleases => true,
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
    artistNthNumberOneRelease ||
    songSelfReplacement ||
    releaseSelfReplacement ||
    artistRepeatNumberOne ||
    artistRepeatNumberOneRelease => true,
    _ => false,
  };

  /// The story [item] tells, or null when its facts are not news (most
  /// weekly movement, or what the permanent chart already told).
  /// [biggestGainer] marks the week's largest verified climb.
  ///
  /// With [complete] (the SN-50 device polish), every recorded debut,
  /// re-entry, new peak and climb is news, on the weekly charts too and at
  /// any position: [ofEveryAchievement].
  static MomentFamily? of(
    ChartMomentFeedItem item, {
    bool biggestGainer = false,
    bool complete = false,
  }) {
    if (complete) {
      final every = ofEveryAchievement(item, biggestGainer: biggestGainer);
      if (every != null) return every;
    }
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
            when worthWeeks(dominant) =>
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
          when worthWeeks(dominant) =>
        songWeeksMilestone,
      ChartMomentEventType.artistSimultaneousThresholdSongs
          when (dominant.threshold ?? 99) <= 10 =>
        artistSimultaneous,
      _ => null,
    };
  }

  /// Chart achievements the earlier rules left untold (weekly debuts below
  /// the Top 10, Bubbling Under and #101–200 release debuts, weekly
  /// re-entries and new peaks at any position, and every weekly climb); null
  /// for everything [of] already tells, which keeps its own family.
  ///
  /// A weekly climb between Bubbling Under and the Hot 100 is a change of
  /// chart: it is told as reaching the Hot 100, never as a number of places.
  static MomentFamily? ofEveryAchievement(
    ChartMomentFeedItem item, {
    bool biggestGainer = false,
  }) {
    if (item.scope == ChartMomentScope.live) return null;
    final weekly = item.scope == ChartMomentScope.finalized;
    final dominant = item.events.firstWhere(
      (event) => event.eventType == item.dominantEventType,
    );
    final rank = dominant.currentRank;
    final previous = dominant.previousRank;
    if (rank == null) return null;
    const limit = ChartRankingEngine.officialChartLimit;

    if (item.chartType == ChartType.albums) {
      return switch (item.dominantEventType) {
        ChartMomentEventType.debut when rank > 1 => releaseDebut,
        ChartMomentEventType.newPeak when rank > 1 => releaseNewPeak,
        ChartMomentEventType.reentry when rank > 1 => releaseReentry,
        ChartMomentEventType.rankRise
            when rank > 1 && previous != null && previous > rank =>
          releaseClimb,
        _ => null,
      };
    }

    final hasCareerNews = item.events.any(
      (event) =>
          event.eventType == ChartMomentEventType.artistFirstNumberOneSong ||
          event.eventType == ChartMomentEventType.artistNthNumberOneSong ||
          event.eventType == ChartMomentEventType.artistFirstThresholdSong ||
          event.eventType == ChartMomentEventType.artistNthThresholdSong,
    );
    if (hasCareerNews && !weekly) return null;

    return switch (item.dominantEventType) {
      ChartMomentEventType.debut when weekly && rank > 10 =>
        rank <= limit ? songDebut : songBubblingUnderDebut,
      ChartMomentEventType.newPeak when weekly && rank > 1 => songNewPeak,
      ChartMomentEventType.reentry when rank > 1 => songReentry,
      // From Bubbling Under into the Hot 100: an arrival, on either chart.
      ChartMomentEventType.rankRise
          when previous != null && previous > limit && rank <= limit =>
        songHot100Breakthrough,
      ChartMomentEventType.rankRise
          when weekly &&
              !biggestGainer &&
              previous != null &&
              previous > rank =>
        songBigClimb,
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
  static bool worthWeeks(ChartMomentEvent event) {
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
