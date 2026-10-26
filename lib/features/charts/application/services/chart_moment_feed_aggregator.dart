import '../models/chart_moment_feed_item.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';

class ChartMomentFeedAggregator {
  const ChartMomentFeedAggregator();

  List<ChartMomentFeedItem> aggregate(Iterable<ChartMomentEvent> source) {
    final groups = <String, List<ChartMomentEvent>>{};

    for (final event in source) {
      final key = _groupKey(event);

      groups.putIfAbsent(key, () => <ChartMomentEvent>[]).add(event);
    }

    final items = <ChartMomentFeedItem>[
      for (final group in groups.entries)
        _buildItem(groupKey: group.key, events: group.value),
    ];

    items.sort(_compareFeedItems);

    return List<ChartMomentFeedItem>.unmodifiable(items);
  }

  static ChartMomentFeedItem _buildItem({
    required String groupKey,
    required List<ChartMomentEvent> events,
  }) {
    if (events.isEmpty) {
      throw ArgumentError.value(
        events,
        'events',
        'Feed group cannot be empty.',
      );
    }

    final ordered = List<ChartMomentEvent>.of(events)
      ..sort(_compareEventsWithinStory);

    final dominant = ordered.first;

    final occurredAt = events
        .map((event) => event.occurredAt.toUtc())
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final relatedEntity = ordered
        .where((event) => event.relatedEntity != null)
        .map((event) => event.relatedEntity!)
        .cast()
        .firstOrNull;

    final artistLevel = events.any(_isArtistLevelCatalogEvent);

    return ChartMomentFeedItem(
      id: 'moment-feed:$groupKey',
      subjectType: artistLevel
          ? ChartMomentFeedSubjectType.artist
          : ChartMomentFeedSubjectType.entity,
      chartType: dominant.chartType,
      scope: dominant.scope,
      weekStartUtc: dominant.weekStartUtc.toUtc(),
      weekEndUtc: dominant.weekEndUtc.toUtc(),
      occurredAt: occurredAt,
      entity: dominant.entity,
      relatedEntity: relatedEntity,
      artistId: artistLevel ? dominant.entity.artistId : null,
      events: List<ChartMomentEvent>.unmodifiable(ordered),
      dominantEventType: dominant.eventType,
    );
  }

  static String _groupKey(ChartMomentEvent event) {
    final base =
        '${event.scope.name}:'
        '${event.chartType.name}:'
        '${event.weekStartUtc.toUtc().millisecondsSinceEpoch}:';

    if (_isArtistLevelCatalogEvent(event)) {
      final artistId = event.entity.artistId?.trim();

      if (artistId != null && artistId.isNotEmpty) {
        return '${base}artist:$artistId';
      }
    }

    final entityKey = 'entity:${event.entity.entityId}';

    if (event.scope == ChartMomentScope.finalized) {
      return '$base$entityKey';
    }

    final sourceId = event.sourceId?.trim();

    // Everything one play achieved on one chart is one story: the song's
    // achievement, its artist's career fact, the artist ranking.
    if (event.scope == ChartMomentScope.allTime &&
        sourceId != null &&
        sourceId.isNotEmpty) {
      return '${base}source:$sourceId';
    }

    final transitionKey = sourceId != null && sourceId.isNotEmpty
        ? 'source:$sourceId'
        : 'occurred:${event.occurredAt.toUtc().microsecondsSinceEpoch}';

    return '$base$entityKey:$transitionKey';
  }

  static bool _isArtistLevelCatalogEvent(ChartMomentEvent event) {
    return switch (event.eventType) {
      ChartMomentEventType.artistSimultaneousThresholdSongs ||
      ChartMomentEventType.artistSimultaneousThresholdAlbums => true,
      _ => false,
    };
  }

  static int _compareFeedItems(ChartMomentFeedItem a, ChartMomentFeedItem b) {
    final occurred = b.occurredAt.compareTo(a.occurredAt);

    if (occurred != 0) {
      return occurred;
    }

    return a.id.compareTo(b.id);
  }

  static int _compareEventsWithinStory(ChartMomentEvent a, ChartMomentEvent b) {
    final priority = _priority(b.eventType).compareTo(_priority(a.eventType));

    if (priority != 0) {
      return priority;
    }

    final thresholdA = a.threshold ?? 1 << 30;
    final thresholdB = b.threshold ?? 1 << 30;

    final threshold = thresholdA.compareTo(thresholdB);

    if (threshold != 0) {
      return threshold;
    }

    return a.id.compareTo(b.id);
  }

  static int _priority(ChartMomentEventType type) {
    return switch (type) {
      ChartMomentEventType.firstNumberOne => 1000,
      ChartMomentEventType.returnToNumberOne => 990,
      ChartMomentEventType.artistReturnsToNumberOneSong ||
      ChartMomentEventType.artistReturnsToNumberOneAlbum => 980,
      ChartMomentEventType.artistFirstNumberOneSong ||
      ChartMomentEventType.artistFirstNumberOneAlbum => 970,
      ChartMomentEventType.artistNthNumberOneSong ||
      ChartMomentEventType.artistNthNumberOneAlbum => 960,

      ChartMomentEventType.artistBecomesTopArtist => 920,
      ChartMomentEventType.newPeak => 900,
      ChartMomentEventType.artistHighestChartingSong ||
      ChartMomentEventType.artistHighestChartingAlbum => 890,

      ChartMomentEventType.debut => 850,
      ChartMomentEventType.reentry => 840,

      ChartMomentEventType.rankRise => 800,
      ChartMomentEventType.rankFall => 790,
      ChartMomentEventType.rankSame => 780,

      ChartMomentEventType.firstThresholdEntry => 750,
      ChartMomentEventType.thresholdReturn => 740,

      ChartMomentEventType.artistFirstThresholdSong ||
      ChartMomentEventType.artistFirstThresholdAlbum => 730,
      ChartMomentEventType.artistNthThresholdSong ||
      ChartMomentEventType.artistNthThresholdAlbum => 720,

      ChartMomentEventType.artistSimultaneousThresholdSongs ||
      ChartMomentEventType.artistSimultaneousThresholdAlbums => 700,

      ChartMomentEventType.lifetimeStreamMilestone => 650,
      ChartMomentEventType.artistStreamMilestone => 645,
      ChartMomentEventType.consecutiveWeeksMilestone => 640,
      ChartMomentEventType.totalWeeksMilestone => 630,
      ChartMomentEventType.consecutiveThresholdWeeksMilestone => 620,
      ChartMomentEventType.totalThresholdWeeksMilestone => 610,

      ChartMomentEventType.peakMatch => 500,

      ChartMomentEventType.losesNumberOne => 400,
      ChartMomentEventType.thresholdExit => 390,
      ChartMomentEventType.chartExit => 380,
    };
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (!iterator.moveNext()) {
      return null;
    }

    return iterator.current;
  }
}
