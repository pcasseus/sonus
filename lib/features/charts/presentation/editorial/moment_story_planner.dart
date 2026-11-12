import 'chart_jump_facts.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_moment_feed_aggregator.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_artist_dominance.dart';
import '../../domain/moments/chart_moment_artist_joint_control.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';

export 'chart_jump_facts.dart';

/// One story the desk writes, from the facts in [item].
class PlannedMoment {
  const PlannedMoment(
    this.item,
    this.family, {
    this.mandatory = false,
    this.excludedVariants = const {},
    this.jump,
  });

  final ChartMomentFeedItem item;
  final MomentFamily family;

  /// The verified movement and stream facts of a chart-jump story.
  final ChartJumpFacts? jump;

  /// A guaranteed chart entry (F-Q1/F-Q31): never limited by the daily
  /// cap on minor stories (F-Q12).
  final bool mandatory;

  /// Headline ids of [family] whose wording this story's facts do not
  /// support, such as a move "from Bubbling Under" for a song that was off
  /// the chart last week.
  final Set<String> excludedVariants;
}

/// Approved news held back from publication (SN-50). Since Batch 5 the
/// BUG-04 falls and exits are told (songBubblingUnderFall, songHot100Exit).
enum GatedMomentKind {
  /// A story planned under the SN-50 rules whose family has no approved
  /// headlines yet (see MomentHeadlines.approvedFamilies): held, never
  /// published, never told with a plain fallback headline.
  unapprovedCopy,
}

/// A detected [GatedMomentKind] story, with the id it would publish under.
class GatedMoment {
  const GatedMoment(this.id, this.kind, this.event, {this.family, this.story});

  final String id;
  final GatedMomentKind kind;
  final ChartMomentEvent event;

  /// For [GatedMomentKind.unapprovedCopy]: the family it would be told in.
  final MomentFamily? family;

  /// For [GatedMomentKind.unapprovedCopy]: the planned story, with all of
  /// its events.
  final ChartMomentFeedItem? story;
}

/// The stories of one recorded group under the SN-50 rules (Session F):
///
/// - every debut and re-entry on a song or release chart, #1–200, is a
///   story of its own, and so is a song's first Hot 100 entry from
///   Bubbling Under, also when the same move reaches #1 (R3);
/// - a debut's story tells every zone its position reaches (a #1 debut is
///   one "debuts at #1" story), so a debut has no zone stories;
/// - after the entry, a move's first #1 and first Top 10 each get their
///   own story, and every other zone it enters for the first time (Top
///   75 … Top 2, and a release's Top 100) is named in one shared story
///   (R3, F-Q14/F-Q14B);
/// - a song's move between Bubbling Under and the Hot 100 is told against
///   verified history (SN-50 BUG-04): a first Hot 100 entry is a Hot 100
///   arrival, also when the song returns to the chart after charting only
///   on Bubbling Under; a song back from Bubbling Under that was on the
///   Hot 100 before is a Hot 100 re-entry. Neither is told as a climb;
/// - every weekly climb of [bubblingUnderRiseMinimum] or more places within
///   Bubbling Under is a story of its own, outside the daily cap (approved
///   BUG-04 rule 1); falls and notable Hot 100 exits are only detected
///   ([copyGated]) until their headlines are approved;
/// - #1 stories name only the verified displaced leader, and an artist
///   replacing their own song at #1 gets self-replacement wording;
/// - distinct achievements of one play stay distinct stories (F-Q6/F-Q9).
///
/// Stories take their ids from the group and their kind, so planning the
/// same recorded facts again yields the same stories.
class MomentStoryPlanner {
  MomentStoryPlanner(
    Iterable<ChartMomentFeedItem> items, {
    required Set<String> biggestGainers,
  }) : _leaders = _displacedLeaders(items),
       _gainers = biggestGainers,
       _fiveHot100Weeks = _fiveHot100WeeksReached(items),
       _weeklyMoves = _weeklyMovesFrom(items);

  /// The zone below #1 whose first entry is told on its own; the others
  /// a move enters are told together. #1 is its own story.
  static const int majorThreshold = 10;

  /// The largest zone an artist roundup is told for, songs and releases.
  static const int roundupThreshold = 10;

  /// Zones whose longevity is news (F-Q2/F-Q3): #1, the Top 10 and the
  /// official chart (Top 100).
  static const Set<int> longevityThresholds = {1, 10, 100};

  /// The smallest stream total told as its own story beside another
  /// achievement of the same play (F-Q7).
  static const int majorStreamMilestone = 1000;

  static bool isMajorStreamMilestone(ChartMomentEvent event) =>
      (event.milestoneValue ?? 0) >= majorStreamMilestone;

  /// Hot 100 arrival headlines that tell a move up from Bubbling Under
  /// without naming last week's rank; untrue for a song that was off the
  /// chart last week.
  static const Set<String> fromBubblingUnderVariants = {
    'song-break-d5',
    'song-break-d6',
    'song-break-p2',
    'song-break-p4',
  };

  /// Per finalized chart week, the previous week's #1 that lost the spot.
  final Map<String, ChartEntitySnapshot> _leaders;
  final Set<String> _gainers;

  /// Per song, the first finalized week its fifth Hot 100 week was
  /// recorded, from stored longevity milestones.
  final Map<String, DateTime> _fiveHot100Weeks;

  /// The smallest weekly climb within Bubbling Under told as a story.
  static const int bubblingUnderRiseMinimum = 20;

  /// The smallest weekly fall within Bubbling Under that is news.
  static const int bubblingUnderFallMinimum = 30;

  /// Chart jumps (SN-50, approved): the smallest weekly climb within the
  /// Hot 100 told as a major jump, and the shortest run of consecutive
  /// weekly Hot 100 climbs with the smallest total it must reach.
  static const int hot100MajorClimbMinimum = 25;
  static const int hot100ClimbRunWeeks = 3;
  static const int hot100ClimbRunMinimum = 30;

  /// A major jump finishing at or above this rank is never capped.
  static const int majorJumpUncappedRank = 40;

  /// Per song, its finalized weekly chart entries keyed by the week's end:
  /// the verified history jump detection reads. Weeks before Moments were
  /// recorded are absent, and missing history never counts.
  final Map<String, Map<int, ChartMomentEvent>> _weeklyMoves;

  /// A Hot 100 exit into Bubbling Under is news after a peak at or above
  /// this rank, or after [notableExitWeeks] Hot 100 weeks.
  static const int notableExitPeak = 40;
  static const int notableExitWeeks = 5;

  /// Hot 100 arrival headlines that state last week's rank without saying
  /// it was a Bubbling Under rank, so they read as a Hot 100 climb (E-Q1).
  ///
  /// Empty since Batch 4: refined stories tell `song-break-p3` with its
  /// BU-001 wording, which names the Bubbling Under rank.
  static const Set<String> misleadingArrivalVariants = {};

  /// The artist-dominance story of an artist's chart week (REF-19), told
  /// on its own as the week's one artist story:
  /// 1. a solo sweep of the Top 3 or more;
  /// 2. joint control, told once, from the artist holding #1;
  /// 3. otherwise the most notable recorded dominance (a Top 2 sweep, then
  ///    the Top 10, then the Hot 100).
  /// Every recorded fact stays stored; only the story is chosen. Families
  /// whose lines await approval are passed over; with none left the artist
  /// roundup is told exactly as before.
  static (MomentFamily, ChartMomentEvent)? dominanceStory(
    ChartMomentFeedItem item, {
    Set<MomentFamily> approved = MomentHeadlines.approvedFamilies,
  }) {
    ChartMomentEvent? lead;
    ArtistDominance? leadFact;
    ChartMomentEvent? joint;
    for (final event in item.events) {
      final fact = ArtistDominance.of(event);
      if (fact != null) {
        if (!approved.contains(familyOf(fact.kind))) continue;
        if (leadFact == null || fact.kind.index < leadFact.kind.index) {
          lead = event;
          leadFact = fact;
        }
      } else if (ArtistJointControl.of(event) != null &&
          event.currentRank == 1 &&
          approved.contains(MomentFamily.artistJointControl)) {
        joint = event;
      }
    }
    if (lead != null &&
        leadFact != null &&
        leadFact.kind == ArtistDominanceKind.sweep &&
        leadFact.tier >= 3) {
      return (MomentFamily.artistChartSweep, lead);
    }
    if (joint != null) return (MomentFamily.artistJointControl, joint);
    if (lead == null || leadFact == null) return null;
    return (familyOf(leadFact.kind), lead);
  }

  /// The family a recorded dominance kind is told in.
  static MomentFamily familyOf(ArtistDominanceKind kind) => switch (kind) {
    ArtistDominanceKind.sweep => MomentFamily.artistChartSweep,
    ArtistDominanceKind.top10 => MomentFamily.artistTop10Presence,
    ArtistDominanceKind.hot100 => MomentFamily.artistHot100Presence,
  };

  List<PlannedMoment> plan(ChartMomentFeedItem item) {
    if (item.scope == ChartMomentScope.live) return const [];
    final weekly = item.scope == ChartMomentScope.finalized;
    final albums = item.chartType == ChartType.albums;
    final stories = <PlannedMoment>[];

    void add(
      String kind,
      MomentFamily family,
      List<ChartMomentEvent> events, {
      bool mandatory = false,
      Set<String> excludedVariants = const {},
      ChartJumpFacts? jump,
    }) => stories.add(
      PlannedMoment(
        ChartMomentFeedAggregator.storyItem(
          id: '${item.id}#$kind',
          events: events,
        ),
        family,
        mandatory: mandatory,
        excludedVariants: excludedVariants,
        jump: jump,
      ),
    );

    ChartMomentEvent? find(Set<ChartMomentEventType> types) {
      for (final event in item.events) {
        if (types.contains(event.eventType)) return event;
      }
      return null;
    }

    if (item.subjectType == ChartMomentFeedSubjectType.artist) {
      if (dominanceStory(item) case (final family, final event)) {
        add('dominance', family, [event]);
        return stories;
      }
      final threshold = item.events.first.threshold;
      if (threshold != null && threshold <= roundupThreshold) {
        add(
          'roundup',
          albums
              ? MomentFamily.artistSimultaneousReleases
              : MomentFamily.artistSimultaneous,
          item.events,
        );
      }
      return stories;
    }

    final one = find(const {
      ChartMomentEventType.firstNumberOne,
      ChartMomentEventType.returnToNumberOne,
    });
    final entry = find(const {
      ChartMomentEventType.debut,
      ChartMomentEventType.reentry,
    });
    final debutAtOne =
        one?.eventType == ChartMomentEventType.firstNumberOne &&
        (weekly
            ? entry?.eventType == ChartMomentEventType.debut
            : one!.previousRank == null && one.previousPeakRank == null);
    final debut = debutAtOne || entry?.eventType == ChartMomentEventType.debut;

    ChartEntitySnapshot? rival;
    var self = false;
    if (one != null) {
      final displaced = weekly
          ? _leaders[_weekKey(item.chartType, item.weekStartUtc)]
          : one.relatedEntity;
      if (displaced != null && displaced.entityId != one.entity.entityId) {
        switch (_sameArtist(displaced, one.entity)) {
          case true:
            rival = displaced;
            self = true;
          case false:
            rival = displaced;
          case null:
            break;
        }
      }
    }

    // Guaranteed entry.
    if (debutAtOne) {
      add(
        'entry',
        albums
            ? MomentFamily.releaseDebutNumberOne
            : MomentFamily.songDebutNumberOne,
        [_named(one!, self ? null : rival)],
        mandatory: true,
      );
    } else if (entry != null && entry.currentRank != null) {
      final firstHot100 = albums || debut
          ? null
          : _zoneEvent(
              item,
              ChartMomentEventType.firstThresholdEntry,
              ChartRankingEngine.officialChartLimit,
            );
      if (firstHot100 != null) {
        // Back on the chart, but never on the Hot 100 before: its first
        // Hot 100 entry, not a Hot 100 re-entry.
        add(
          'entry',
          MomentFamily.songHot100Breakthrough,
          [firstHot100],
          mandatory: true,
          excludedVariants: fromBubblingUnderVariants,
        );
      } else {
        add('entry', _entryFamily(entry, albums), [entry], mandatory: true);
      }
    }

    // #1.
    if (one != null) {
      final career = find(const {
        ChartMomentEventType.artistFirstNumberOneSong,
        ChartMomentEventType.artistNthNumberOneSong,
        ChartMomentEventType.artistFirstNumberOneAlbum,
        ChartMomentEventType.artistNthNumberOneAlbum,
      });
      // The career count is for the artist the entity counts for.
      final named = _named(one, rival, entity: weekly ? career?.entity : null);
      if (self) {
        add(
          'number-one',
          albums
              ? MomentFamily.releaseSelfReplacement
              : MomentFamily.songSelfReplacement,
          [named],
        );
      } else if (career != null) {
        add('number-one', _careerNumberOne(career, albums, weekly), [
          named,
          career,
        ]);
      } else if (!debutAtOne) {
        final first = one.eventType == ChartMomentEventType.firstNumberOne;
        add(
          'number-one',
          switch ((albums, first)) {
            (true, true) => MomentFamily.releaseReachesNumberOne,
            (true, false) => MomentFamily.releaseReturnsToNumberOne,
            (false, true) => MomentFamily.songFirstNumberOne,
            (false, false) => MomentFamily.songReturnsToNumberOne,
          },
          [named],
        );
      }
    }

    // An artist's career Top 10 / Top 100 (all-time songs); a #1 already
    // tells the bigger career fact.
    int? careerZone;
    if (!weekly && !albums && one == null) {
      final top10 = _career(
        item,
        ChartMomentEventType.artistFirstThresholdSong,
        10,
      );
      final nthTop10 = _career(
        item,
        ChartMomentEventType.artistNthThresholdSong,
        10,
      );
      final hot100 = _career(
        item,
        ChartMomentEventType.artistFirstThresholdSong,
        ChartRankingEngine.officialChartLimit,
      );
      if (top10 != null || nthTop10 != null) {
        careerZone = 10;
        add(
          'career',
          top10 != null
              ? MomentFamily.artistFirstTop10
              : MomentFamily.artistNthTop10,
          [top10 ?? nthTop10!],
        );
      } else if (hot100 != null) {
        careerZone = ChartRankingEngine.officialChartLimit;
        add('career', MomentFamily.artistFirstHot100, [hot100]);
      }
    }

    // First entries into zones; a debut's position already tells them.
    var zoned = false;
    if (!debut) {
      final crossed = [
        for (final event in item.events)
          if (event.eventType == ChartMomentEventType.firstThresholdEntry &&
              event.threshold != null &&
              event.threshold! > 1 &&
              event.threshold! < ChartRankingEngine.extendedStandingsLimit &&
              event.threshold != careerZone)
            event,
      ];
      // Back from Bubbling Under to a Hot 100 it was on before: an
      // official re-entry, never a climb from last week's rank (E-Q1).
      final hot100Return = albums || entry != null
          ? null
          : _zoneEvent(
              item,
              ChartMomentEventType.thresholdReturn,
              ChartRankingEngine.officialChartLimit,
            );
      if (hot100Return != null && hot100Return.previousRank != null) {
        add('hot-100', MomentFamily.songReentry, [
          hot100Return,
        ], mandatory: true);
      }
      final others = <ChartMomentEvent>[];
      for (final event in crossed) {
        final zone = event.threshold!;
        if (!albums && zone == ChartRankingEngine.officialChartLimit) {
          // From Bubbling Under; a re-entry story already tells a return
          // straight into the Hot 100.
          if (event.previousRank != null) {
            add(
              'hot-100',
              MomentFamily.songHot100Breakthrough,
              [event],
              mandatory: true,
              excludedVariants: misleadingArrivalVariants,
            );
          }
        } else if (zone == majorThreshold) {
          add('top-$zone', _firstThreshold(albums), [event], mandatory: true);
        } else {
          others.add(event);
        }
      }
      if (others.length == 1) {
        add(
          'top-${others.single.threshold}',
          _firstThreshold(albums),
          others,
          mandatory: true,
        );
      } else if (others.length > 1) {
        add(
          'thresholds',
          albums ? MomentFamily.releaseThresholds : MomentFamily.songThresholds,
          others,
          mandatory: true,
        );
      }
      zoned = crossed.isNotEmpty;
    }

    // A best position without a new zone.
    if (one == null && entry == null && careerZone == null && !zoned) {
      final peak = find(const {ChartMomentEventType.newPeak});
      final match = find(const {ChartMomentEventType.peakMatch});
      final climbed = find(const {ChartMomentEventType.rankRise}) != null;
      if (peak != null && (!weekly || (peak.currentRank ?? 99) <= 10)) {
        add(
          'peak',
          albums ? MomentFamily.releaseNewPeak : MomentFamily.songNewPeak,
          [peak],
        );
      } else if (weekly &&
          !albums &&
          climbed &&
          match != null &&
          (match.currentRank ?? 99) <= 10) {
        // Only a climb back to the peak: holding it is not a return.
        add('peak-match', MomentFamily.songPeakMatch, [match]);
      }
    }

    if (weekly && !albums) {
      final longevity = _longevity(item);
      if (longevity != null) {
        add('weeks', MomentFamily.songWeeksMilestone, [longevity]);
      }
      final rise = find(const {ChartMomentEventType.rankRise});
      if (rise != null && _gainers.contains(item.id)) {
        add('gainer', MomentFamily.songBiggestGainer, [rise]);
      } else if (rise != null &&
          _withinBubblingUnder(rise) &&
          (rise.movementDistance ?? 0) >= bubblingUnderRiseMinimum) {
        // The biggest gainer's story already tells its climb.
        add('bu-climb', MomentFamily.songBigClimb, [rise], mandatory: true);
      }
      if (rise != null && _withinHot100(rise)) {
        _addChartJump(item, rise, stories, add);
      }
      // BUG-04 approved rule 2: a fall of 30+ places within Bubbling Under,
      // capped like any minor story.
      final fall = find(const {ChartMomentEventType.rankFall});
      if (fall != null &&
          _withinBubblingUnder(fall) &&
          (fall.movementDistance ?? 0) >= bubblingUnderFallMinimum) {
        add('bu-fall', MomentFamily.songBubblingUnderFall, [fall]);
      }
      // BUG-04 approved rule 3: a notable exit into Bubbling Under; never
      // capped after a verified Top 40 peak.
      final exit = _hot100Exit(item);
      if (exit != null) {
        final peak = exit.previousPeakRank;
        add('hot-100-exit', MomentFamily.songHot100Exit, [
          exit,
        ], mandatory: peak != null && peak <= notableExitPeak);
      }
    }

    if (!weekly) {
      final rise = find(const {ChartMomentEventType.rankRise});
      if (rise != null && !albums) {
        add('climb', MomentFamily.songBigClimb, [rise]);
      }
      final top = find(const {ChartMomentEventType.artistBecomesTopArtist});
      if (top != null) add('top-artist', MomentFamily.artistTopArtist, [top]);

      // A stream milestone is its own story when the play did nothing else
      // or when it is a major one; a smaller one is left to the other
      // story's supporting text (F-Q7).
      final quiet = stories.isEmpty;
      bool told(ChartMomentEvent? event) =>
          event != null && (quiet || isMajorStreamMilestone(event));
      final streams = find(const {
        ChartMomentEventType.lifetimeStreamMilestone,
      });
      final artistStreams = find(const {
        ChartMomentEventType.artistStreamMilestone,
      });
      if (told(streams)) {
        add(
          'milestone',
          albums
              ? MomentFamily.releaseStreamMilestone
              : MomentFamily.songStreamMilestone,
          [streams!],
        );
      } else if (told(artistStreams)) {
        add('milestone', MomentFamily.artistStreamMilestone, [artistStreams!]);
      }
    }

    return stories;
  }

  static MomentFamily _entryFamily(ChartMomentEvent entry, bool albums) {
    final rank = entry.currentRank!;
    final debut = entry.eventType == ChartMomentEventType.debut;
    if (albums) {
      return debut ? MomentFamily.releaseDebut : MomentFamily.releaseReentry;
    }
    if (!debut) return MomentFamily.songReentry;
    if (rank <= 10) return MomentFamily.songDebutTop10;
    return rank <= ChartRankingEngine.officialChartLimit
        ? MomentFamily.songDebut
        : MomentFamily.songBubblingUnderDebut;
  }

  static MomentFamily _careerNumberOne(
    ChartMomentEvent career,
    bool albums,
    bool weekly,
  ) {
    final first =
        career.eventType == ChartMomentEventType.artistFirstNumberOneSong ||
        career.eventType == ChartMomentEventType.artistFirstNumberOneAlbum;
    if (albums) {
      return first
          ? MomentFamily.artistFirstNumberOneRelease
          : weekly
          ? MomentFamily.artistRepeatNumberOneRelease
          : MomentFamily.artistNthNumberOneRelease;
    }
    return first
        ? MomentFamily.artistFirstNumberOne
        : weekly
        ? MomentFamily.artistRepeatNumberOne
        : MomentFamily.artistNthNumberOne;
  }

  static MomentFamily _firstThreshold(bool albums) => albums
      ? MomentFamily.releaseFirstThreshold
      : MomentFamily.songFirstThreshold;

  static ChartMomentEvent? _career(
    ChartMomentFeedItem item,
    ChartMomentEventType type,
    int threshold,
  ) => _zoneEvent(item, type, threshold);

  static ChartMomentEvent? _zoneEvent(
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

  /// The week's longevity milestone worth a story, in the
  /// [longevityThresholds] (#101–200 weeks are not official chart weeks):
  /// the smallest zone first, an unbroken run before a total.
  static ChartMomentEvent? _longevity(ChartMomentFeedItem item) {
    const consecutive = {
      ChartMomentEventType.consecutiveWeeksMilestone,
      ChartMomentEventType.consecutiveThresholdWeeksMilestone,
    };
    final milestones = [
      for (final event in item.events)
        if ((event.eventType ==
                    ChartMomentEventType.consecutiveThresholdWeeksMilestone ||
                event.eventType ==
                    ChartMomentEventType.totalThresholdWeeksMilestone) &&
            longevityThresholds.contains(event.threshold) &&
            MomentFamily.worthWeeks(event))
          event,
    ];
    if (milestones.isEmpty) return null;
    milestones.sort((a, b) {
      final byZone = a.threshold!.compareTo(b.threshold!);
      if (byZone != 0) return byZone;
      final aRun = consecutive.contains(a.eventType) ? 0 : 1;
      final bRun = consecutive.contains(b.eventType) ? 0 : 1;
      if (aRun != bRun) return aRun.compareTo(bRun);
      return (b.milestoneValue ?? 0).compareTo(a.milestoneValue ?? 0);
    });
    return milestones.first;
  }

  /// [event] as the story tells it: naming [rival] (or nobody), and with
  /// [entity] when the career count belongs to another artist identity.
  static ChartMomentEvent _named(
    ChartMomentEvent event,
    ChartEntitySnapshot? rival, {
    ChartEntitySnapshot? entity,
  }) => ChartMomentEvent(
    id: event.id,
    deduplicationKey: event.deduplicationKey,
    userId: event.userId,
    sourceId: event.sourceId,
    chartType: event.chartType,
    scope: event.scope,
    eventType: event.eventType,
    entity: entity ?? event.entity,
    relatedEntity: rival,
    weekStartUtc: event.weekStartUtc,
    weekEndUtc: event.weekEndUtc,
    occurredAt: event.occurredAt,
    createdAt: event.createdAt,
    previousRank: event.previousRank,
    currentRank: event.currentRank,
    threshold: event.threshold,
    previousPeakRank: event.previousPeakRank,
    currentPeakRank: event.currentPeakRank,
    qualifiedStreamCount: event.qualifiedStreamCount,
    milestoneValue: event.milestoneValue,
  );

  /// Whether two entities have the same artist: null when that cannot be
  /// verified (a missing artist identity with the same name).
  static bool? _sameArtist(ChartEntitySnapshot a, ChartEntitySnapshot b) {
    final aId = a.artistId?.trim() ?? '';
    final bId = b.artistId?.trim() ?? '';
    if (aId.isNotEmpty && bId.isNotEmpty) return aId == bId;
    final sameName =
        a.artistName.trim().toLowerCase() == b.artistName.trim().toLowerCase();
    return sameName ? null : false;
  }

  static String _weekKey(ChartType chartType, DateTime weekStartUtc) =>
      '${chartType.name}:${weekStartUtc.toUtc().millisecondsSinceEpoch}';

  /// Approved news in [item] detected but not yet told. Empty since
  /// Batch 5, which tells the BUG-04 falls and exits under the same ids
  /// (`#bu-fall`, `#hot-100-exit`).
  List<GatedMoment> copyGated(ChartMomentFeedItem item) => const [];

  /// The weekly exit from the Hot 100 into Bubbling Under in [item], when
  /// it is notable (a Top 40 peak or five earlier Hot 100 weeks).
  ChartMomentEvent? _hot100Exit(ChartMomentFeedItem item) {
    for (final event in item.events) {
      if (event.eventType == ChartMomentEventType.thresholdExit &&
          event.threshold == ChartRankingEngine.officialChartLimit &&
          (event.currentRank ?? 0) > ChartRankingEngine.officialChartLimit &&
          _notableExit(event)) {
        return event;
      }
    }
    return null;
  }

  /// Chart jumps (SN-50, approved rules 1–7 and 10): a run of weekly Hot
  /// 100 climbs is its own story, outside the daily cap, and replaces a
  /// jump in the same week. A major jump is a story unless the week's
  /// biggest gainer or a #1, Top 10, zone or peak story already tells the
  /// move (their supporting text names the climb); it is capped like a
  /// minor story unless it finishes in the Top 40. Songs only.
  void _addChartJump(
    ChartMomentFeedItem item,
    ChartMomentEvent rise,
    List<PlannedMoment> stories,
    void Function(
      String kind,
      MomentFamily family,
      List<ChartMomentEvent> events, {
      bool mandatory,
      ChartJumpFacts? jump,
    })
    add,
  ) {
    final previous = _previousWeek(rise);
    final run = _climbRun(rise, previous);
    if (run != null) {
      add(
        'hot-100-run',
        MomentFamily.songHot100ClimbRun,
        [rise],
        mandatory: true,
        jump: run,
      );
      return;
    }

    if ((rise.movementDistance ?? 0) < hot100MajorClimbMinimum ||
        _gainers.contains(item.id) ||
        stories.any(
          (story) =>
              _toldMove.contains(story.family) &&
              // Only a story that is told replaces the jump; a held draft
              // does not, or the move would go untold.
              MomentHeadlines.approvedFamilies.contains(story.family),
        )) {
      return;
    }
    add(
      'hot-100-jump',
      MomentFamily.songHot100MajorJump,
      [rise],
      mandatory: (rise.currentRank ?? 101) <= majorJumpUncappedRank,
      jump: ChartJumpFacts(
        fromRank: rise.previousRank!,
        toRank: rise.currentRank!,
        weeks: 1,
        weekStreams: rise.qualifiedStreamCount,
        previousWeekStreams: previous?.qualifiedStreamCount,
      ),
    );
  }

  /// Stories that already tell a song's move, so a jump headline would only
  /// repeat it (approved rules 6 and 7).
  static const Set<MomentFamily> _toldMove = {
    MomentFamily.songFirstNumberOne,
    MomentFamily.songReturnsToNumberOne,
    MomentFamily.songSelfReplacement,
    // A song's #1 told as its artist's career #1.
    MomentFamily.artistFirstNumberOne,
    MomentFamily.artistNthNumberOne,
    MomentFamily.artistRepeatNumberOne,
    MomentFamily.songFirstThreshold,
    MomentFamily.songThresholds,
    MomentFamily.songNewPeak,
    MomentFamily.songPeakMatch,
    MomentFamily.songBiggestGainer,
    MomentFamily.songHot100Breakthrough,
  };

  /// The run of consecutive weekly Hot 100 climbs ending with [latest],
  /// when it is long and large enough; [previous] is its week before.
  ChartJumpFacts? _climbRun(
    ChartMomentEvent latest,
    ChartMomentEvent? previous,
  ) {
    var weeks = 1;
    var fromRank = latest.previousRank!;
    var cursor = latest;
    while (true) {
      final before = _previousWeek(cursor);
      if (before == null ||
          before.eventType != ChartMomentEventType.rankRise ||
          !_withinHot100(before)) {
        break;
      }
      weeks++;
      fromRank = before.previousRank!;
      cursor = before;
    }
    if (weeks < hot100ClimbRunWeeks ||
        fromRank - latest.currentRank! < hot100ClimbRunMinimum) {
      return null;
    }
    return ChartJumpFacts(
      fromRank: fromRank,
      toRank: latest.currentRank!,
      weeks: weeks,
      weekStreams: latest.qualifiedStreamCount,
      previousWeekStreams: previous?.qualifiedStreamCount,
    );
  }

  /// The song's entry in the finalized week just before [event]'s, only
  /// when its rank is the previous rank [event] was measured against.
  ChartMomentEvent? _previousWeek(ChartMomentEvent event) {
    final before =
        _weeklyMoves[event.entity.entityId]?[event.weekStartUtc
            .toUtc()
            .millisecondsSinceEpoch];
    if (before == null || before.currentRank != event.previousRank) {
      return null;
    }
    return before;
  }

  static bool _withinHot100(ChartMomentEvent event) {
    const limit = ChartRankingEngine.officialChartLimit;
    final before = event.previousRank;
    final now = event.currentRank;
    return event.chartType == ChartType.songs &&
        before != null &&
        now != null &&
        before <= limit &&
        now <= limit;
  }

  static Map<String, Map<int, ChartMomentEvent>> _weeklyMovesFrom(
    Iterable<ChartMomentFeedItem> items,
  ) {
    const placed = {
      ChartMomentEventType.rankRise,
      ChartMomentEventType.rankFall,
      ChartMomentEventType.rankSame,
      ChartMomentEventType.debut,
      ChartMomentEventType.reentry,
    };
    final moves = <String, Map<int, ChartMomentEvent>>{};
    for (final item in items) {
      if (item.scope != ChartMomentScope.finalized ||
          item.chartType != ChartType.songs) {
        continue;
      }
      for (final event in item.events) {
        if (!placed.contains(event.eventType) || event.currentRank == null) {
          continue;
        }
        moves.putIfAbsent(
          event.entity.entityId,
          () => {},
        )[event.weekEndUtc.toUtc().millisecondsSinceEpoch] = event;
      }
    }
    return moves;
  }

  /// A verified Top 40 peak, or a fifth Hot 100 week recorded before this
  /// week. Missing history never counts.
  bool _notableExit(ChartMomentEvent exit) {
    final peak = exit.previousPeakRank;
    if (peak != null && peak <= notableExitPeak) return true;
    final reached = _fiveHot100Weeks[exit.entity.entityId];
    return reached != null && reached.isBefore(exit.weekStartUtc);
  }

  static bool _withinBubblingUnder(ChartMomentEvent event) {
    const limit = ChartRankingEngine.officialChartLimit;
    final before = event.previousRank;
    final now = event.currentRank;
    return event.chartType == ChartType.songs &&
        before != null &&
        now != null &&
        before > limit &&
        now > limit &&
        before <= ChartRankingEngine.extendedStandingsLimit &&
        now <= ChartRankingEngine.extendedStandingsLimit;
  }

  static Map<String, DateTime> _fiveHot100WeeksReached(
    Iterable<ChartMomentFeedItem> items,
  ) {
    final reached = <String, DateTime>{};
    for (final item in items) {
      if (item.scope != ChartMomentScope.finalized ||
          item.chartType != ChartType.songs) {
        continue;
      }
      for (final event in item.events) {
        if (event.eventType ==
                ChartMomentEventType.totalThresholdWeeksMilestone &&
            event.threshold == ChartRankingEngine.officialChartLimit &&
            (event.milestoneValue ?? 0) >= notableExitWeeks) {
          final id = event.entity.entityId;
          final week = event.weekStartUtc;
          final known = reached[id];
          if (known == null || week.isBefore(known)) reached[id] = week;
        }
      }
    }
    return reached;
  }

  static Map<String, ChartEntitySnapshot> _displacedLeaders(
    Iterable<ChartMomentFeedItem> items,
  ) => {
    for (final item in items)
      if (item.scope == ChartMomentScope.finalized)
        for (final event in item.events)
          if (event.eventType == ChartMomentEventType.losesNumberOne)
            _weekKey(event.chartType, event.weekStartUtc): event.entity,
  };
}
