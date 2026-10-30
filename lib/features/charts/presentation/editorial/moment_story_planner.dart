import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_moment_feed_aggregator.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_family.dart';

/// One story the desk writes, from the facts in [item].
class PlannedMoment {
  const PlannedMoment(this.item, this.family, {this.mandatory = false});

  final ChartMomentFeedItem item;
  final MomentFamily family;

  /// A guaranteed chart entry (F-Q1/F-Q31): never limited by the daily
  /// cap on minor stories (F-Q12).
  final bool mandatory;
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
       _gainers = biggestGainers;

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

  /// Per finalized chart week, the previous week's #1 that lost the spot.
  final Map<String, ChartEntitySnapshot> _leaders;
  final Set<String> _gainers;

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
    }) => stories.add(
      PlannedMoment(
        ChartMomentFeedAggregator.storyItem(
          id: '${item.id}#$kind',
          events: events,
        ),
        family,
        mandatory: mandatory,
      ),
    );

    ChartMomentEvent? find(Set<ChartMomentEventType> types) {
      for (final event in item.events) {
        if (types.contains(event.eventType)) return event;
      }
      return null;
    }

    if (item.subjectType == ChartMomentFeedSubjectType.artist) {
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
      add('entry', _entryFamily(entry, albums), [entry], mandatory: true);
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
      final others = <ChartMomentEvent>[];
      for (final event in crossed) {
        final zone = event.threshold!;
        if (!albums && zone == ChartRankingEngine.officialChartLimit) {
          // From Bubbling Under; a re-entry story already tells a return
          // straight into the Hot 100.
          if (event.previousRank != null) {
            add('hot-100', MomentFamily.songHot100Breakthrough, [
              event,
            ], mandatory: true);
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
