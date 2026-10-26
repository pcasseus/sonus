import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../models/chart_moment_feed_copy.dart';

class ChartMomentFeedCopyFormatter {
  const ChartMomentFeedCopyFormatter();

  ChartMomentFeedCopy format(ChartMomentFeedItem item) {
    final dominant = item.events.firstWhere(
      (event) => event.eventType == item.dominantEventType,
    );

    if (item.isAllTime) {
      return _allTime(item, dominant);
    }

    return switch (item.dominantEventType) {
      ChartMomentEventType.firstNumberOne => _numberOne(
        item,
        dominant,
        first: true,
      ),

      ChartMomentEventType.returnToNumberOne => _numberOne(
        item,
        dominant,
        returning: true,
      ),

      ChartMomentEventType.artistReturnsToNumberOneSong ||
      ChartMomentEventType.artistReturnsToNumberOneAlbum =>
        _artistReturnToNumberOne(item, dominant),

      ChartMomentEventType.artistFirstNumberOneSong ||
      ChartMomentEventType.artistFirstNumberOneAlbum => _artistNumberOne(
        item,
        dominant,
        first: true,
      ),

      ChartMomentEventType.artistNthNumberOneSong ||
      ChartMomentEventType.artistNthNumberOneAlbum => _artistNumberOne(
        item,
        dominant,
      ),

      ChartMomentEventType.newPeak => _newPeak(item, dominant),

      ChartMomentEventType.artistHighestChartingSong ||
      ChartMomentEventType.artistHighestChartingAlbum => _artistCareerBest(
        item,
        dominant,
      ),

      ChartMomentEventType.debut => _debut(item, dominant),

      ChartMomentEventType.reentry => _reentry(item, dominant),

      ChartMomentEventType.rankRise => _rise(item, dominant),

      ChartMomentEventType.rankFall => _fall(item, dominant),

      ChartMomentEventType.rankSame => _holds(item, dominant),

      ChartMomentEventType.firstThresholdEntry => _threshold(
        item,
        dominant,
        returning: false,
      ),

      ChartMomentEventType.thresholdReturn => _threshold(
        item,
        dominant,
        returning: true,
      ),

      ChartMomentEventType.artistFirstThresholdSong ||
      ChartMomentEventType.artistFirstThresholdAlbum => _artistThreshold(
        item,
        dominant,
        first: true,
      ),

      ChartMomentEventType.artistNthThresholdSong ||
      ChartMomentEventType.artistNthThresholdAlbum => _artistThreshold(
        item,
        dominant,
      ),

      ChartMomentEventType.artistSimultaneousThresholdSongs ||
      ChartMomentEventType.artistSimultaneousThresholdAlbums => _simultaneous(
        item,
        dominant,
      ),

      ChartMomentEventType.lifetimeStreamMilestone => _streamMilestone(
        item,
        dominant,
      ),

      ChartMomentEventType.consecutiveWeeksMilestone => _weeksMilestone(
        item,
        dominant,
        consecutive: true,
      ),

      ChartMomentEventType.totalWeeksMilestone => _weeksMilestone(
        item,
        dominant,
      ),

      ChartMomentEventType.consecutiveThresholdWeeksMilestone =>
        _thresholdWeeksMilestone(item, dominant, consecutive: true),

      ChartMomentEventType.totalThresholdWeeksMilestone =>
        _thresholdWeeksMilestone(item, dominant),

      ChartMomentEventType.peakMatch => _peakMatch(item, dominant),

      ChartMomentEventType.losesNumberOne => _losesNumberOne(item, dominant),

      ChartMomentEventType.thresholdExit => _thresholdExit(item, dominant),

      ChartMomentEventType.chartExit => _chartExit(item, dominant),
    };
  }

  ChartMomentFeedCopy _numberOne(
    ChartMomentFeedItem item,
    ChartMomentEvent event, {
    bool first = false,
    bool returning = false,
  }) {
    final title = item.entity.title;

    if (item.isLive) {
      return ChartMomentFeedCopy(
        headline: '$title rises to #1',
        body: '$title reaches #1 on this week’s Sonus Hot 100.',
      );
    }

    if (returning) {
      return ChartMomentFeedCopy(
        headline: '$title returns to #1',
        body: '$title returns to the top of the weekly Sonus Hot 100.',
      );
    }

    return ChartMomentFeedCopy(
      headline: first ? '$title earns its first #1' : '$title reaches #1',
      body: '$title is officially #1 on the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _artistReturnToNumberOne(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final artist = item.entity.artistName;
    final gap = event.milestoneValue;

    return ChartMomentFeedCopy(
      headline: '$artist returns to #1',
      body: gap != null && gap > 0
          ? '$artist returns to the top of the weekly chart after $gap ${_plural(gap, 'week')}.'
          : '$artist returns to the top of the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _artistNumberOne(
    ChartMomentFeedItem item,
    ChartMomentEvent event, {
    bool first = false,
  }) {
    final artist = item.entity.artistName;
    final noun = _entityNoun(item.chartType);
    final count = event.milestoneValue;

    if (first || count == null || count <= 1) {
      return ChartMomentFeedCopy(
        headline: '$artist earns a first #1 $noun',
        body: '${item.entity.title} gives $artist a first #1 $noun.',
      );
    }

    return ChartMomentFeedCopy(
      headline: '$artist earns a ${_ordinal(count)} #1 $noun',
      body:
          '${item.entity.title} becomes $artist’s ${_ordinal(count)} #1 $noun.',
    );
  }

  ChartMomentFeedCopy _newPeak(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final rank = event.currentRank ?? event.currentPeakRank;

    if (rank == null) {
      return ChartMomentFeedCopy(
        headline: '${item.entity.title} reaches a new peak',
        body: '${item.entity.title} sets a new weekly Sonus Hot 100 high.',
      );
    }

    final companion = _careerCompanion(item);

    return ChartMomentFeedCopy(
      headline: '${item.entity.title} reaches a new peak of #$rank',
      body:
          companion ??
          (item.isLive
              ? '${item.entity.title} rises to #$rank on this week’s Sonus Hot 100.'
              : '${item.entity.title} earns a new weekly peak of #$rank.'),
    );
  }

  ChartMomentFeedCopy _artistCareerBest(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final rank = event.currentPeakRank ?? event.currentRank;
    final artist = item.entity.artistName;
    final noun = _entityNoun(item.chartType);

    return ChartMomentFeedCopy(
      headline: '$artist sets a new career-best $noun',
      body: rank == null
          ? '${item.entity.title} becomes $artist’s highest-charting $noun.'
          : '${item.entity.title} becomes $artist’s highest-charting $noun at #$rank.',
    );
  }

  ChartMomentFeedCopy _debut(ChartMomentFeedItem item, ChartMomentEvent event) {
    final rank = event.currentRank;

    return ChartMomentFeedCopy(
      headline:
          '${item.entity.title} debuts${rank == null ? '' : ' at #$rank'}',
      body: item.isLive
          ? '${item.entity.title} enters this week’s Sonus Hot 100.'
          : '${item.entity.title} makes its weekly Sonus Hot 100 debut.',
    );
  }

  ChartMomentFeedCopy _reentry(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final rank = event.currentRank;

    return ChartMomentFeedCopy(
      headline:
          '${item.entity.title} re-enters${rank == null ? '' : ' at #$rank'}',
      body: '${item.entity.title} returns to the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _rise(ChartMomentFeedItem item, ChartMomentEvent event) {
    final current = event.currentRank;
    final previous = event.previousRank;

    if (current != null && previous != null) {
      final distance = previous - current;

      return ChartMomentFeedCopy(
        headline: '${item.entity.title} rises to #$current',
        body: distance > 0
            ? '${item.entity.title} climbs $distance ${_plural(distance, 'spot')}.'
            : '${item.entity.title} moves up the weekly Sonus Hot 100.',
      );
    }

    return ChartMomentFeedCopy(
      headline: '${item.entity.title} moves up',
      body: '${item.entity.title} rises on the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _fall(ChartMomentFeedItem item, ChartMomentEvent event) {
    final current = event.currentRank;
    final previous = event.previousRank;

    if (current != null && previous != null) {
      final distance = current - previous;

      return ChartMomentFeedCopy(
        headline: '${item.entity.title} falls to #$current',
        body: distance > 0
            ? '${item.entity.title} drops $distance ${_plural(distance, 'spot')}.'
            : '${item.entity.title} moves down the weekly Sonus Hot 100.',
      );
    }

    return ChartMomentFeedCopy(
      headline: '${item.entity.title} moves down',
      body: '${item.entity.title} falls on the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _holds(ChartMomentFeedItem item, ChartMomentEvent event) {
    final rank = event.currentRank;

    return ChartMomentFeedCopy(
      headline:
          '${item.entity.title} holds${rank == null ? ' steady' : ' at #$rank'}',
      body: '${item.entity.title} remains steady on the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _threshold(
    ChartMomentFeedItem item,
    ChartMomentEvent event, {
    required bool returning,
  }) {
    final threshold = event.threshold;

    if (threshold == null) {
      return ChartMomentFeedCopy(
        headline: returning
            ? '${item.entity.title} returns to chart territory'
            : '${item.entity.title} reaches new chart territory',
        body:
            '${item.entity.title} marks another weekly Sonus Hot 100 milestone.',
      );
    }

    return ChartMomentFeedCopy(
      headline: returning
          ? '${item.entity.title} returns to the Top $threshold'
          : '${item.entity.title} reaches the Top $threshold',
      body: returning
          ? '${item.entity.title} is back inside the Top $threshold.'
          : '${item.entity.title} reaches the Top $threshold for the first time.',
    );
  }

  ChartMomentFeedCopy _artistThreshold(
    ChartMomentFeedItem item,
    ChartMomentEvent event, {
    bool first = false,
  }) {
    final artist = item.entity.artistName;
    final threshold = event.threshold;
    final count = event.milestoneValue;
    final noun = _entityNoun(item.chartType);

    if (threshold == null) {
      return ChartMomentFeedCopy(
        headline: '$artist adds another chart achievement',
        body:
            '${item.entity.title} adds to $artist’s weekly Sonus Hot 100 history.',
      );
    }

    if (first || count == null || count <= 1) {
      return ChartMomentFeedCopy(
        headline: '$artist earns a first Top $threshold $noun',
        body:
            '${item.entity.title} becomes $artist’s first $noun to reach the Top $threshold.',
      );
    }

    return ChartMomentFeedCopy(
      headline: '$artist earns a ${_ordinal(count)} Top $threshold $noun',
      body:
          '${item.entity.title} becomes $artist’s ${_ordinal(count)} $noun to reach the Top $threshold.',
    );
  }

  ChartMomentFeedCopy _simultaneous(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final artist = item.entity.artistName;
    final threshold = event.threshold;
    final count = event.milestoneValue ?? item.events.length;
    final noun = _entityNoun(item.chartType);

    return ChartMomentFeedCopy(
      headline: threshold == null
          ? '$artist charts $count ${_plural(count, noun)} at once'
          : '$artist lands $count ${_plural(count, noun)} in the Top $threshold',
      body: threshold == null
          ? '$artist has multiple ${_plural(count, noun)} charting simultaneously.'
          : '$artist has $count ${_plural(count, noun)} inside the Top $threshold at the same time.',
    );
  }

  ChartMomentFeedCopy _streamMilestone(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final count = event.milestoneValue;

    return ChartMomentFeedCopy(
      headline: count == null
          ? '${item.entity.title} reaches a stream milestone'
          : '${item.entity.title} reaches $count streams',
      body: count == null
          ? '${item.entity.title} reaches a new qualified Sonus listening milestone.'
          : '${item.entity.title} has now earned $count qualified Sonus streams.',
    );
  }

  ChartMomentFeedCopy _weeksMilestone(
    ChartMomentFeedItem item,
    ChartMomentEvent event, {
    bool consecutive = false,
  }) {
    final count = event.milestoneValue;

    return ChartMomentFeedCopy(
      headline: count == null
          ? '${item.entity.title} reaches a chart longevity milestone'
          : '${item.entity.title} reaches $count ${consecutive ? 'straight ' : ''}${_plural(count, 'week')} on chart',
      body: count == null
          ? '${item.entity.title} adds another longevity milestone.'
          : '${item.entity.title} has spent $count ${consecutive ? 'consecutive ' : ''}${_plural(count, 'week')} on the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _thresholdWeeksMilestone(
    ChartMomentFeedItem item,
    ChartMomentEvent event, {
    bool consecutive = false,
  }) {
    final count = event.milestoneValue;
    final threshold = event.threshold;

    if (count == null || threshold == null) {
      return ChartMomentFeedCopy(
        headline: '${item.entity.title} reaches a chart longevity milestone',
        body:
            '${item.entity.title} adds another weekly Sonus Hot 100 achievement.',
      );
    }

    return ChartMomentFeedCopy(
      headline:
          '${item.entity.title} reaches $count ${consecutive ? 'straight ' : ''}${_plural(count, 'week')} in the Top $threshold',
      body:
          '${item.entity.title} has spent $count ${consecutive ? 'consecutive ' : ''}${_plural(count, 'week')} inside the Top $threshold.',
    );
  }

  ChartMomentFeedCopy _peakMatch(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final rank = event.currentRank ?? event.currentPeakRank;

    return ChartMomentFeedCopy(
      headline: rank == null
          ? '${item.entity.title} matches its peak'
          : '${item.entity.title} matches its #$rank peak',
      body:
          '${item.entity.title} returns to its career-best weekly chart position.',
    );
  }

  ChartMomentFeedCopy _losesNumberOne(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    return ChartMomentFeedCopy(
      headline: '${item.entity.title} leaves #1',
      body:
          '${item.entity.title} gives up the top spot on the weekly Sonus Hot 100.',
    );
  }

  ChartMomentFeedCopy _thresholdExit(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final threshold = event.threshold;

    return ChartMomentFeedCopy(
      headline: threshold == null
          ? '${item.entity.title} falls below a chart milestone'
          : '${item.entity.title} exits the Top $threshold',
      body: threshold == null
          ? '${item.entity.title} moves below a tracked chart threshold.'
          : '${item.entity.title} moves outside the Top $threshold.',
    );
  }

  ChartMomentFeedCopy _chartExit(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    return ChartMomentFeedCopy(
      headline: '${item.entity.title} exits the chart',
      body:
          '${item.entity.title} moves outside the weekly Sonus Hot 100 standings.',
    );
  }

  String? _careerCompanion(ChartMomentFeedItem item) {
    for (final event in item.events) {
      if (event.eventType == ChartMomentEventType.artistHighestChartingSong ||
          event.eventType == ChartMomentEventType.artistHighestChartingAlbum) {
        final rank = event.currentPeakRank ?? event.currentRank;
        final noun = _entityNoun(item.chartType);

        if (rank != null) {
          return '${item.entity.title} also becomes ${item.entity.artistName}’s highest-charting $noun at #$rank.';
        }

        return '${item.entity.title} also becomes ${item.entity.artistName}’s highest-charting $noun.';
      }
    }

    return null;
  }

  /// All-time stories rank lifetime streams, so they never borrow the
  /// weekly wording.
  /// All-time stories rank lifetime streams, so they never borrow the
  /// weekly wording or a chart-cycle reset.
  ///
  /// Patterns adopted from the legacy Sonus Daily / PulsePop desk
  /// (sonus_app chart_narrative_service and sonus_feed_adapter): the
  /// "Title by Artist" byline, breakthrough verbs scaled to the zone
  /// (breaks into the Top 10, enters the Top 25, reaches the Top 50),
  /// climb verbs scaled to the move (surges, jumps), and the decks "A new
  /// leader takes over", "A fresh entry" and "its highest position so far".
  ChartMomentFeedCopy _allTime(
    ChartMomentFeedItem item,
    ChartMomentEvent event,
  ) {
    final title = item.entity.title;
    final artist = item.entity.artistName.trim();
    final who = artist.isEmpty ? title : '$title by $artist';
    final chart = allTimeChartName(item.chartType);
    final rank = event.currentRank;
    final streams = event.qualifiedStreamCount;
    final withStreams = streams == null || streams <= 0
        ? ''
        : ' with $streams lifetime ${_plural(streams, 'stream')}';
    final atRank = rank == null ? '' : ' at #$rank';

    return switch (event.eventType) {
      ChartMomentEventType.firstNumberOne => ChartMomentFeedCopy(
        headline: '$who takes #1 all-time',
        body:
            'A new leader takes over the $chart: $title is #1 for the '
            'first time$withStreams.',
      ),
      ChartMomentEventType.returnToNumberOne => ChartMomentFeedCopy(
        headline: '$who is back at #1 all-time',
        body: '$title retakes the top of the $chart$withStreams.',
      ),
      ChartMomentEventType.newPeak when event.threshold != null =>
        ChartMomentFeedCopy(
          headline: switch (event.threshold!) {
            2 => '$who rises to #2 all-time',
            10 => '$who breaks into the all-time Top 10',
            25 => '$who enters the all-time Top 25',
            50 => '$who reaches the all-time Top 50',
            final zone => '$who climbs into the all-time Top $zone',
          },
          body: rank == null
              ? '$title sets a new high on the $chart.'
              : '$title climbs to #$rank on the $chart, its highest '
                    'position so far.',
        ),
      ChartMomentEventType.firstThresholdEntry => ChartMomentFeedCopy(
        headline: '$who enters the all-time Top ${event.threshold ?? 100}',
        body: rank == null
            ? '$title breaks into the $chart Top ${event.threshold ?? 100}.'
            : '$title moves up to #$rank on the $chart$withStreams.',
      ),
      ChartMomentEventType.debut => ChartMomentFeedCopy(
        headline: rank == null
            ? '$who debuts on the all-time chart'
            : '$who debuts at #$rank all-time',
        body: 'A fresh entry: $title lands on the $chart$withStreams.',
      ),
      ChartMomentEventType.reentry => ChartMomentFeedCopy(
        headline: '$who re-enters the all-time chart$atRank',
        body: '$title returns to the $chart after dropping out.',
      ),
      ChartMomentEventType.rankRise
          when rank != null && event.previousRank != null =>
        ChartMomentFeedCopy(
          headline:
              '$who ${event.previousRank! - rank >= surgePlaces ? 'surges' : 'jumps'} '
              '${event.previousRank! - rank} places all-time',
          body:
              '$title climbs from #${event.previousRank} to #$rank on the $chart.',
        ),
      _ => ChartMomentFeedCopy(
        headline: '$who moves on the all-time chart',
        body: rank == null
            ? '$title moves on the $chart.'
            : '$title is now #$rank on the $chart.',
      ),
    };
  }

  /// A climb this large reads as a surge rather than a jump.
  static const int surgePlaces = 30;

  /// For example "all-time Sonus Hot 100".
  static String allTimeChartName(ChartType type) => switch (type) {
    ChartType.songs => 'all-time Sonus Hot 100',
    ChartType.albums => 'all-time Sonus Top 200 Albums',
  };

  String _entityNoun(ChartType type) {
    return type == ChartType.songs ? 'song' : 'album';
  }

  String _plural(int value, String noun) {
    return value == 1 ? noun : '${noun}s';
  }

  String _ordinal(int value) {
    final mod100 = value % 100;

    if (mod100 >= 11 && mod100 <= 13) {
      return '${value}th';
    }

    return switch (value % 10) {
      1 => '${value}st',
      2 => '${value}nd',
      3 => '${value}rd',
      _ => '${value}th',
    };
  }
}
