import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_moment_feed_aggregator.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/all_time_history_replay.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_climb.dart';
import 'moment_editorial_desk.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';
import 'moment_publisher.dart';
import 'moment_story_planner.dart';
import 'moment_visuals.dart';

/// The App Update 1.1 Moments chronicle: how all-time stories from the
/// chronicle start are planned and written.
///
/// Planning ([revise]) works on the stories the desk would otherwise
/// publish for one recorded group:
///
/// - a completed day at #1 is one hold story ([MomentFamily.songNumberOneHold]);
/// - an entity pushed off the Hot 100 or out of the Top 200 is one
///   departure story;
/// - a song back on the Hot 100 from Bubbling Under is one return story;
/// - a play that climbs and reaches a new peak and/or enters a zone (Top
///   50, 25, 20, 15, 10, 5 or 3) for the first time or again is ONE chart
///   move story naming every one of those facts; the separate peak, zone
///   and climb stories it replaces are not published. A #1, a debut, a
///   re-entry, a first Hot 100 entry, career records and milestones keep
///   their own stories, which already tell the bigger fact.
///
/// Writing ([write]) only states recorded facts: places climbed from the
/// recorded previous rank, the recorded rank, zones from recorded zone
/// events, a new peak only when the rank beats the recorded previous peak,
/// and days only from completed chart days. When a fact is missing the
/// headline is narrower; nothing is guessed.
abstract final class MomentChronicle {
  /// The zones a chart move names, smallest (most significant) first.
  static const List<int> zones = [3, 5, 10, 15, 20, 25, 50];

  static const Set<MomentFamily> _replacedByMove = {
    MomentFamily.songNewPeak,
    MomentFamily.releaseNewPeak,
    MomentFamily.songPeakMatch,
    MomentFamily.songFirstThreshold,
    MomentFamily.releaseFirstThreshold,
    MomentFamily.songThresholds,
    MomentFamily.releaseThresholds,
    MomentFamily.songBigClimb,
    MomentFamily.releaseClimb,
  };

  /// Whether [item] is told by the chronicle under [chronicles].
  static bool applies(
    ChartMomentFeedItem item,
    bool Function(DateTime occurredAt) chronicles,
  ) =>
      item.scope == ChartMomentScope.allTime &&
      item.subjectType == ChartMomentFeedSubjectType.entity &&
      chronicles(item.occurredAt);

  /// The stories to publish for [item], from the desk's own [planned].
  static List<PlannedMoment> revise(
    ChartMomentFeedItem item,
    List<PlannedMoment> planned,
  ) {
    final albums = item.chartType == ChartType.albums;

    ChartMomentEvent? find(bool Function(ChartMomentEvent) test) {
      for (final event in item.events) {
        if (test(event)) return event;
      }
      return null;
    }

    PlannedMoment story(
      String kind,
      MomentFamily family,
      List<ChartMomentEvent> events,
    ) => PlannedMoment(
      ChartMomentFeedAggregator.storyItem(
        id: '${item.id}#chronicle-$kind',
        events: events,
      ),
      family,
      mandatory: true,
    );

    final hold = find(
      (e) => e.isDailyNumberOneHold,
    );
    if (hold != null) {
      return [
        story(
          'hold',
          albums
              ? MomentFamily.releaseNumberOneHold
              : MomentFamily.songNumberOneHold,
          [hold],
        ),
      ];
    }

    final chartExit = find(
      (e) => e.eventType == ChartMomentEventType.chartExit,
    );
    if (chartExit != null) {
      return [
        story(
          'chart-exit',
          albums
              ? MomentFamily.releaseChartDeparture
              : MomentFamily.songChartDeparture,
          [chartExit],
        ),
      ];
    }
    final hot100Exit = find(
      (e) =>
          e.eventType == ChartMomentEventType.thresholdExit &&
          e.threshold == ChartRankingEngine.officialChartLimit,
    );
    if (hot100Exit != null) {
      // A release leaving the album chart's top 100 is not news.
      return albums
          ? const []
          : [
              story('hot-100-exit', MomentFamily.songHot100Departure, [
                hot100Exit,
              ]),
            ];
    }

    // The bigger stories of this play keep their own telling.
    final bigger = find(
      (e) => switch (e.eventType) {
        ChartMomentEventType.firstNumberOne ||
        ChartMomentEventType.returnToNumberOne ||
        ChartMomentEventType.debut ||
        ChartMomentEventType.reentry => true,
        ChartMomentEventType.firstThresholdEntry =>
          e.threshold == ChartRankingEngine.officialChartLimit,
        _ => false,
      },
    );
    if (bigger != null) return planned;

    final hot100Return = find(
      (e) =>
          e.eventType == ChartMomentEventType.thresholdReturn &&
          e.threshold == ChartRankingEngine.officialChartLimit &&
          (e.previousRank ?? 0) > ChartRankingEngine.officialChartLimit,
    );

    final zoneEvents = [
      for (final event in item.events)
        if ((event.eventType == ChartMomentEventType.firstThresholdEntry ||
                event.eventType == ChartMomentEventType.thresholdReturn) &&
            zones.contains(event.threshold))
          event,
    ];
    final peak = find((e) => e.eventType == ChartMomentEventType.newPeak);
    final rise = find((e) => e.eventType == ChartMomentEventType.rankRise);

    final kept = [
      for (final moment in planned)
        if (!_replacedByMove.contains(moment.family) &&
            !(hot100Return != null &&
                (moment.family == MomentFamily.songReentry ||
                    moment.family == MomentFamily.songHot100Breakthrough)))
          moment,
    ];

    if (hot100Return != null && !albums) {
      return [
        ...kept,
        story('hot-100-return', MomentFamily.songHot100Return, [
          hot100Return,
          ...zoneEvents,
          ?peak,
        ]),
      ];
    }
    if (zoneEvents.isEmpty && peak == null) {
      // Only a climb: the desk's climb story (and developing thread) tells
      // it as before.
      return planned;
    }
    final move = [?rise, ?peak, ...zoneEvents];
    if (move.every((e) => e.previousRank == null || e.currentRank == null)) {
      return planned;
    }
    return [
      ...kept,
      story(
        'move',
        albums ? MomentFamily.releaseChartMove : MomentFamily.songChartMove,
        move,
      ),
    ];
  }

  /// The story for a chronicle [moment], written in its publisher's voice.
  static MomentStory write(
    PlannedMoment moment,
    MomentLookups lookups, {
    required String? previousVariant,
  }) {
    final item = moment.item;
    final family = moment.family;
    final facts = MomentFacts.of(item, lookups, polished: true);
    final telling = _tell(item, family, facts);
    final options = [
      for (final line in telling.lines)
        if (line.publisher == telling.publisher) line,
    ];
    var index = _hash('${item.id}|headline') % options.length;
    if (options[index].id == previousVariant && options.length > 1) {
      index = (index + 1) % options.length;
    }
    final line = options[index];
    final variant = HeadlineVariant(
      line.id,
      line.publisher,
      (_) => line.text,
      requires: const {MomentFact.rank},
    );
    return MomentStory(
      item: item,
      family: family,
      facts: facts,
      publisher: line.publisher,
      variantId: line.id,
      headline: line.text,
      body: telling.body,
      kicker: facts.chartName,
      status: telling.status,
      rank: telling.rank,
      climb: telling.climb,
      visual: MomentVisuals.select(
        item: item,
        family: family,
        facts: facts,
        variant: variant,
        lookups: lookups,
        headline: line.text,
      ),
    );
  }

  static _Telling _tell(
    ChartMomentFeedItem item,
    MomentFamily family,
    MomentFacts f,
  ) {
    final s = f.subject;
    final events = item.events;
    final first = events.first;

    switch (family) {
      case MomentFamily.songNumberOneHold || MomentFamily.releaseNumberOneHold:
        final days = first.milestoneValue ?? 1;
        final chart = _chart(item);
        return _Telling(
          MomentPublisher.sonusDaily,
          status: '#1 HOLD',
          rank: 1,
          lines: days <= 1
              ? [
                  _Line(
                    'hold-1-d1',
                    MomentPublisher.sonusDaily,
                    '$s ends the day at #1 on $chart.',
                  ),
                  _Line(
                    'hold-1-d2',
                    MomentPublisher.sonusDaily,
                    '$s closes the day as $chart\'s #1.',
                  ),
                ]
              : [
                  _Line(
                    'hold-n-d1',
                    MomentPublisher.sonusDaily,
                    '$s spends a ${_ordinal(days)} straight day at #1 on '
                        '$chart.',
                  ),
                  _Line(
                    'hold-n-d2',
                    MomentPublisher.sonusDaily,
                    '$s holds #1 on $chart for a ${_ordinal(days)} '
                        'consecutive day.',
                  ),
                  _Line(
                    'hold-n-d3',
                    MomentPublisher.sonusDaily,
                    '$days days and counting: $s is still #1 on $chart.',
                  ),
                ],
          body: _streams(first),
        );

      case MomentFamily.songHot100Departure:
        final days = first.milestoneValue ?? 0;
        final peak = first.previousPeakRank;
        final peakText = peak == null ? '' : ', having peaked at #$peak';
        return _Telling(
          MomentPublisher.sonusDaily,
          status: 'EXIT (HOT 100)',
          rank: first.currentRank,
          lines: [
            _Line(
              'hot100-exit-d1',
              MomentPublisher.sonusDaily,
              '$s leaves the Sonus Hot 100 after ${_days(days)}, '
                  'slipping to #${first.currentRank ?? 101}$peakText.',
            ),
            _Line(
              'hot100-exit-d2',
              MomentPublisher.sonusDaily,
              'After ${_days(days)} on the Sonus Hot 100, $s falls to '
                  '#${first.currentRank ?? 101} on Sonus Bubbling Under.',
            ),
          ],
          body: 'It stays on the wider Sonus chart, on Bubbling Under.',
        );

      case MomentFamily.songChartDeparture ||
          MomentFamily.releaseChartDeparture:
        final days = first.milestoneValue ?? 0;
        final peak = first.previousPeakRank;
        final where = family == MomentFamily.releaseChartDeparture
            ? 'the Sonus Albums & EPs chart'
            : 'the Sonus charts';
        return _Telling(
          MomentPublisher.sonusDaily,
          status: 'CHART EXIT',
          rank: null,
          lines: [
            _Line(
              'chart-exit-d1',
              MomentPublisher.sonusDaily,
              '$s drops off $where after ${_days(days)} in the Top 200'
                  '${peak == null ? '' : ', having peaked at #$peak'}.',
            ),
            _Line(
              'chart-exit-d2',
              MomentPublisher.sonusDaily,
              '$s leaves $where after ${_days(days)}'
                  '${peak == null ? '' : ' and a #$peak peak'}.',
            ),
          ],
        );

      case MomentFamily.songHot100Return:
        final back = events.firstWhere(
          (e) => e.eventType == ChartMomentEventType.thresholdReturn,
        );
        final rank = back.currentRank!;
        final from = back.previousRank!;
        return _Telling(
          MomentPublisher.pulsePop,
          status: 'RE-ENTRY',
          rank: rank,
          climb: from - rank,
          lines: [
            _Line(
              'hot100-return-p1',
              MomentPublisher.pulsePop,
              'Back on the Hot 100! $s climbs from #$from on Bubbling '
                  'Under to #$rank on the Sonus Hot 100.',
            ),
            _Line(
              'hot100-return-p2',
              MomentPublisher.pulsePop,
              '$s is back on the Sonus Hot 100, jumping '
                  '${MomentClimb.placesText(from - rank)} to #$rank.',
            ),
          ],
        );

      default:
        return _move(item, family, f);
    }
  }

  /// One chart move: the climb, its rank, the zone it enters or returns
  /// to, and a new peak, as recorded.
  static _Telling _move(
    ChartMomentFeedItem item,
    MomentFamily family,
    MomentFacts f,
  ) {
    final s = f.subject;
    final chart = _chart(item);
    final events = item.events;
    final ranked = events.firstWhere(
      (e) => e.currentRank != null && e.previousRank != null,
      orElse: () => events.first,
    );
    final rank = ranked.currentRank!;
    final from = ranked.previousRank;
    final places = from == null || from <= rank ? null : from - rank;

    int? smallest(ChartMomentEventType type) {
      int? zone;
      for (final event in events) {
        final threshold = event.threshold;
        if (event.eventType == type &&
            threshold != null &&
            (zone == null || threshold < zone)) {
          zone = threshold;
        }
      }
      return zone;
    }

    final firstZone = smallest(ChartMomentEventType.firstThresholdEntry);
    final returnZone = smallest(ChartMomentEventType.thresholdReturn);
    // The zone named is the most significant one reached; a first entry
    // wins over a return to a larger zone.
    final zone = switch ((firstZone, returnZone)) {
      (final a?, final b?) => b < a ? b : a,
      (final a?, null) => a,
      (null, final b?) => b,
      _ => null,
    };
    final zoneIsFirst = zone != null && zone == firstZone;
    final peakEvent = events.where(
      (e) => e.eventType == ChartMomentEventType.newPeak,
    );
    final previousPeak = ranked.previousPeakRank;
    final newPeak =
        peakEvent.isNotEmpty || (previousPeak != null && rank < previousPeak);

    final climbed = places == null
        ? 'rises to #$rank'
        : 'climbs ${MomentClimb.placesText(places)} to #$rank';
    final facts = <String>[
      if (zone != null)
        zoneIsFirst
            ? 'enters the Top $zone for the first time'
            : 'returns to the Top $zone',
      if (newPeak) 'reaches a new peak',
    ];
    final daily = '$s $climbed on $chart${_andList(facts)}.';

    final pulse = <_Line>[
      if (zone != null && zoneIsFirst)
        _Line(
          'move-p1',
          MomentPublisher.pulsePop,
          'Top $zone unlocked! $s $climbed on $chart'
              '${newPeak ? ', a brand-new peak' : ''}.',
        ),
      if (zone != null && !zoneIsFirst)
        _Line(
          'move-p2',
          MomentPublisher.pulsePop,
          'Back in the Top $zone! $s $climbed on $chart'
              '${newPeak ? ', its best spot yet' : ''}.',
        ),
      if (zone == null && newPeak)
        _Line(
          'move-p3',
          MomentPublisher.pulsePop,
          'New peak alert: $s $climbed on $chart.',
        ),
    ];
    final energetic =
        (zone != null && zoneIsFirst && zone <= 10) || (places ?? 0) >= 10;

    return _Telling(
      energetic ? MomentPublisher.pulsePop : MomentPublisher.sonusDaily,
      status: zone != null
          ? zoneIsFirst
                ? 'TOP $zone ENTRY'
                : 'BACK IN TOP $zone'
          : 'NEW PEAK',
      rank: rank,
      climb: places,
      lines: [
        _Line('move-d1', MomentPublisher.sonusDaily, daily),
        ...pulse,
        if (pulse.isEmpty) _Line('move-p0', MomentPublisher.pulsePop, daily),
      ],
    );
  }

  static String _chart(ChartMomentFeedItem item) =>
      item.chartType == ChartType.albums
      ? 'the Sonus Albums & EPs chart'
      : 'the Sonus Hot 100';

  static String? _streams(ChartMomentEvent event) {
    final streams = event.qualifiedStreamCount;
    if (streams == null || streams <= 0) return null;
    return 'It has ${MomentFacts.streamCount(streams)} on Sonus.';
  }

  static String _andList(List<String> clauses) {
    if (clauses.isEmpty) return '';
    if (clauses.length == 1) return ', and ${clauses.single}';
    return ', ${clauses.sublist(0, clauses.length - 1).join(', ')} and '
        '${clauses.last}';
  }

  static String _days(int days) => days == 1 ? '1 day' : '$days days';

  static String _ordinal(int value) {
    final mod100 = value % 100;
    final suffix = mod100 >= 11 && mod100 <= 13
        ? 'th'
        : switch (value % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$value$suffix';
  }

  static int _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Exposed for tests: the replay's Hot 100 size.
  static const int hot100 = AllTimeHistoryReplay.hot100;
}

class _Line {
  const _Line(this.id, this.publisher, this.text);

  final String id;
  final MomentPublisher publisher;
  final String text;
}

class _Telling {
  const _Telling(
    this.publisher, {
    required this.status,
    required this.lines,
    this.rank,
    this.climb,
    this.body,
  });

  final MomentPublisher publisher;
  final String status;
  final List<_Line> lines;
  final int? rank;
  final int? climb;
  final String? body;
}
