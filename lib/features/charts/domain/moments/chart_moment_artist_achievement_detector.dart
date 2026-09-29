import '../entities/chart_entry.dart';
import '../entities/chart_snapshot.dart';
import '../models/chart_entity_snapshot.dart';
import '../models/chart_type.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_finalized_detector.dart';
import 'chart_moment_scope.dart';

class ChartMomentArtistAchievementDetector {
  const ChartMomentArtistAchievementDetector();

  static final List<int> thresholds = List<int>.unmodifiable(
    ChartMomentFinalizedDetector.thresholds.where(
      (threshold) => threshold != 1,
    ),
  );

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required DateTime createdAt,
    String? userId,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'Artist achievement detection requires a finalized chart snapshot.',
      );
    }

    final weekStartUtc = snapshot.weekStartUtc.toUtc();

    final earlierHistory = history
        .where(
          (historical) =>
              historical.isFinalized &&
              historical.chartType == snapshot.chartType &&
              historical.weekStartUtc.toUtc().isBefore(weekStartUtc),
        )
        .toList(growable: false);

    final historicalByArtist = _buildHistoricalCatalog(earlierHistory);

    final currentByArtist = <String, List<ChartEntry>>{};

    for (final entry in snapshot.entries) {
      final artistId = entry.entity.artistId;

      if (artistId == null || artistId.isEmpty) {
        continue;
      }

      currentByArtist.putIfAbsent(artistId, () => <ChartEntry>[]).add(entry);
    }

    final events = <ChartMomentEvent>[];

    for (final artistGroup in currentByArtist.entries) {
      final artistId = artistGroup.key;

      final entries = artistGroup.value.toList(growable: false)
        ..sort((a, b) {
          final rankComparison = a.rank.compareTo(b.rank);

          if (rankComparison != 0) {
            return rankComparison;
          }

          return a.entity.entityId.compareTo(b.entity.entityId);
        });

      final catalog =
          historicalByArtist[artistId] ?? const _ArtistCatalogHistory.empty();

      events.addAll(
        _detectNumberOneReturn(
          snapshot: snapshot,
          history: earlierHistory,
          artistId: artistId,
          entries: entries,
          createdAt: createdAt,
          userId: userId,
        ),
      );

      events.addAll(
        _detectSimultaneousThresholds(
          snapshot: snapshot,
          history: earlierHistory,
          artistId: artistId,
          entries: entries,
          createdAt: createdAt,
          userId: userId,
        ),
      );

      final previousCareerBest = catalog.bestRank;
      final bestCurrentEntry = entries.first;

      if (previousCareerBest == null ||
          bestCurrentEntry.rank < previousCareerBest) {
        events.add(
          _event(
            snapshot: snapshot,
            entry: bestCurrentEntry,
            createdAt: createdAt,
            eventType: _highestChartingEventType(snapshot.chartType),
            previousPeakRank: previousCareerBest,
            currentPeakRank: bestCurrentEntry.rank,
            relatedEntity: catalog.bestEntity,
            userId: userId,
          ),
        );
      }

      final workingPeakByEntityId = Map<String, int>.from(
        catalog.peakByEntityId,
      );

      for (final entry in entries) {
        final entityId = entry.entity.entityId;
        final previousEntityPeak = workingPeakByEntityId[entityId];

        for (final threshold in thresholds) {
          final newlyReachedByEntity =
              entry.rank <= threshold &&
              (previousEntityPeak == null || previousEntityPeak > threshold);

          if (!newlyReachedByEntity) {
            continue;
          }

          final previousDistinctCount = workingPeakByEntityId.values
              .where((peak) => peak <= threshold)
              .length;

          final ordinal = previousDistinctCount + 1;

          events.add(
            _event(
              snapshot: snapshot,
              entry: entry,
              createdAt: createdAt,
              eventType: _thresholdEventType(
                chartType: snapshot.chartType,
                ordinal: ordinal,
              ),
              threshold: threshold,
              milestoneValue: ordinal,
              userId: userId,
            ),
          );
        }

        final newlyReachedNumberOne =
            entry.rank == 1 &&
            (previousEntityPeak == null || previousEntityPeak > 1);

        if (newlyReachedNumberOne) {
          final previousNumberOnes = workingPeakByEntityId.values
              .where((peak) => peak == 1)
              .length;

          final ordinal = previousNumberOnes + 1;

          events.add(
            _event(
              snapshot: snapshot,
              entry: entry,
              createdAt: createdAt,
              eventType: _numberOneEventType(
                chartType: snapshot.chartType,
                ordinal: ordinal,
              ),
              threshold: 1,
              milestoneValue: ordinal,
              userId: userId,
            ),
          );
        }

        final existingPeak = workingPeakByEntityId[entityId];

        if (existingPeak == null || entry.peakRank < existingPeak) {
          workingPeakByEntityId[entityId] = entry.peakRank;
        }
      }
    }

    return List<ChartMomentEvent>.unmodifiable(events);
  }

  static Map<String, _ArtistCatalogHistory> _buildHistoricalCatalog(
    Iterable<ChartSnapshot> history,
  ) {
    final mutable = <String, _MutableArtistCatalogHistory>{};

    for (final snapshot in history) {
      for (final entry in snapshot.entries) {
        final artistId = entry.entity.artistId;

        if (artistId == null || artistId.isEmpty) {
          continue;
        }

        final catalog = mutable.putIfAbsent(
          artistId,
          _MutableArtistCatalogHistory.new,
        );

        catalog.observe(entry);
      }
    }

    return {for (final item in mutable.entries) item.key: item.value.freeze()};
  }

  static List<ChartMomentEvent> _detectNumberOneReturn({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required String artistId,
    required List<ChartEntry> entries,
    required DateTime createdAt,
    required String? userId,
  }) {
    final currentNumberOnes = entries
        .where((entry) => entry.rank == 1)
        .toList(growable: false);

    if (currentNumberOnes.isEmpty) {
      return const [];
    }

    final historical = history.toList(
      growable: false,
    )..sort((a, b) => b.weekStartUtc.toUtc().compareTo(a.weekStartUtc.toUtc()));

    ChartSnapshot? lastNumberOneSnapshot;
    ChartEntry? lastNumberOneEntry;

    for (final historicalSnapshot in historical) {
      for (final historicalEntry in historicalSnapshot.entries) {
        if (historicalEntry.entity.artistId == artistId &&
            historicalEntry.rank == 1) {
          lastNumberOneSnapshot = historicalSnapshot;
          lastNumberOneEntry = historicalEntry;
          break;
        }
      }

      if (lastNumberOneSnapshot != null) {
        break;
      }
    }

    if (lastNumberOneSnapshot == null || lastNumberOneEntry == null) {
      return const [];
    }

    final elapsedHours = snapshot.weekStartUtc
        .toUtc()
        .difference(lastNumberOneSnapshot.weekStartUtc.toUtc())
        .inHours;

    final weekDistance = (elapsedHours / (24 * 7)).round();
    final gapWeeks = weekDistance - 1;

    if (gapWeeks <= 0) {
      return const [];
    }

    final current = currentNumberOnes.first;

    return [
      _event(
        snapshot: snapshot,
        entry: current,
        createdAt: createdAt,
        eventType: _numberOneReturnEventType(snapshot.chartType),
        threshold: 1,
        milestoneValue: gapWeeks,
        relatedEntity: lastNumberOneEntry.entity,
        userId: userId,
      ),
    ];
  }

  static List<ChartMomentEvent> _detectSimultaneousThresholds({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required String artistId,
    required List<ChartEntry> entries,
    required DateTime createdAt,
    required String? userId,
  }) {
    final immediatelyPrevious = history
        .where(
          (historical) =>
              historical.isFinalized &&
              historical.chartType == snapshot.chartType &&
              historical.weekEndUtc.toUtc() == snapshot.weekStartUtc.toUtc(),
        )
        .toList(growable: false);

    if (immediatelyPrevious.length > 1) {
      throw StateError(
        'Multiple finalized previous-week snapshots exist for '
        '${snapshot.chartType.name} at '
        '${snapshot.weekStartUtc.toUtc().toIso8601String()}.',
      );
    }

    final previousEntries = immediatelyPrevious.isEmpty
        ? const <ChartEntry>[]
        : immediatelyPrevious.single.entries
              .where((entry) => entry.entity.artistId == artistId)
              .toList(growable: false);

    final events = <ChartMomentEvent>[];

    for (final threshold in thresholds) {
      final currentAtThreshold = entries
          .where((entry) => entry.rank <= threshold)
          .toList(growable: false);

      if (currentAtThreshold.length < 2) {
        continue;
      }

      final previousCount = previousEntries
          .where((entry) => entry.rank <= threshold)
          .length;

      if (currentAtThreshold.length <= previousCount) {
        continue;
      }

      events.add(
        _event(
          snapshot: snapshot,
          entry: currentAtThreshold.first,
          createdAt: createdAt,
          eventType: _simultaneousEventType(snapshot.chartType),
          threshold: threshold,
          milestoneValue: currentAtThreshold.length,
          relatedEntity: currentAtThreshold.length > 1
              ? currentAtThreshold[1].entity
              : null,
          userId: userId,
        ),
      );
    }

    return List<ChartMomentEvent>.unmodifiable(events);
  }

  static ChartMomentEventType _numberOneReturnEventType(ChartType chartType) {
    switch (chartType) {
      case ChartType.songs:
        return ChartMomentEventType.artistReturnsToNumberOneSong;

      case ChartType.albums:
        return ChartMomentEventType.artistReturnsToNumberOneAlbum;
    }
  }

  static ChartMomentEventType _simultaneousEventType(ChartType chartType) {
    switch (chartType) {
      case ChartType.songs:
        return ChartMomentEventType.artistSimultaneousThresholdSongs;

      case ChartType.albums:
        return ChartMomentEventType.artistSimultaneousThresholdAlbums;
    }
  }

  static ChartMomentEventType _thresholdEventType({
    required ChartType chartType,
    required int ordinal,
  }) {
    switch (chartType) {
      case ChartType.songs:
        return ordinal == 1
            ? ChartMomentEventType.artistFirstThresholdSong
            : ChartMomentEventType.artistNthThresholdSong;

      case ChartType.albums:
        return ordinal == 1
            ? ChartMomentEventType.artistFirstThresholdAlbum
            : ChartMomentEventType.artistNthThresholdAlbum;
    }
  }

  static ChartMomentEventType _numberOneEventType({
    required ChartType chartType,
    required int ordinal,
  }) {
    switch (chartType) {
      case ChartType.songs:
        return ordinal == 1
            ? ChartMomentEventType.artistFirstNumberOneSong
            : ChartMomentEventType.artistNthNumberOneSong;

      case ChartType.albums:
        return ordinal == 1
            ? ChartMomentEventType.artistFirstNumberOneAlbum
            : ChartMomentEventType.artistNthNumberOneAlbum;
    }
  }

  static ChartMomentEventType _highestChartingEventType(ChartType chartType) {
    switch (chartType) {
      case ChartType.songs:
        return ChartMomentEventType.artistHighestChartingSong;

      case ChartType.albums:
        return ChartMomentEventType.artistHighestChartingAlbum;
    }
  }

  static ChartMomentEvent _event({
    required ChartSnapshot snapshot,
    required ChartEntry entry,
    required DateTime createdAt,
    required ChartMomentEventType eventType,
    required String? userId,
    int? threshold,
    int? milestoneValue,
    int? previousPeakRank,
    int? currentPeakRank,
    ChartEntitySnapshot? relatedEntity,
  }) {
    final deduplicationKey = _deduplicationKey(
      snapshot: snapshot,
      artistId: entry.entity.artistId!,
      entityId: entry.entity.entityId,
      eventType: eventType,
      threshold: threshold,
      milestoneValue: milestoneValue,
      previousPeakRank: previousPeakRank,
      currentPeakRank: currentPeakRank,
    );

    return ChartMomentEvent(
      id: deduplicationKey,
      deduplicationKey: deduplicationKey,
      userId: userId,
      sourceId: snapshot.id,
      chartType: snapshot.chartType,
      scope: ChartMomentScope.finalized,
      eventType: eventType,
      entity: entry.entity,
      relatedEntity: relatedEntity,
      weekStartUtc: snapshot.weekStartUtc.toUtc(),
      weekEndUtc: snapshot.weekEndUtc.toUtc(),
      occurredAt: snapshot.finalizedAt!.toUtc(),
      createdAt: createdAt.toUtc(),
      previousRank: entry.previousFinalRank,
      currentRank: entry.rank,
      threshold: threshold,
      previousPeakRank: previousPeakRank,
      currentPeakRank: currentPeakRank ?? entry.peakRank,
      qualifiedStreamCount: entry.qualifiedStreamCount,
      milestoneValue: milestoneValue,
    );
  }

  static String _deduplicationKey({
    required ChartSnapshot snapshot,
    required String artistId,
    required String entityId,
    required ChartMomentEventType eventType,
    required int? threshold,
    required int? milestoneValue,
    required int? previousPeakRank,
    required int? currentPeakRank,
  }) {
    return [
      'moment',
      'finalized',
      snapshot.chartType.name,
      snapshot.weekStartUtc.toUtc().millisecondsSinceEpoch,
      artistId,
      entityId,
      snapshot.id,
      eventType.name,
      threshold ?? '-',
      milestoneValue ?? '-',
      previousPeakRank ?? '-',
      currentPeakRank ?? '-',
    ].join(':');
  }
}

class _MutableArtistCatalogHistory {
  final Map<String, int> peakByEntityId = {};
  final Map<String, ChartEntitySnapshot> identityByEntityId = {};

  int? bestRank;
  ChartEntitySnapshot? bestEntity;

  void observe(ChartEntry entry) {
    final entityId = entry.entity.entityId;
    final historicalPeak = entry.peakRank;
    final existingPeak = peakByEntityId[entityId];

    if (existingPeak == null || historicalPeak < existingPeak) {
      peakByEntityId[entityId] = historicalPeak;
      identityByEntityId[entityId] = entry.entity;
    }

    final currentBest = bestRank;

    if (currentBest == null || historicalPeak < currentBest) {
      bestRank = historicalPeak;
      bestEntity = entry.entity;
    }
  }

  _ArtistCatalogHistory freeze() {
    return _ArtistCatalogHistory(
      peakByEntityId: Map.unmodifiable(peakByEntityId),
      bestRank: bestRank,
      bestEntity: bestEntity,
    );
  }
}

class _ArtistCatalogHistory {
  const _ArtistCatalogHistory({
    required this.peakByEntityId,
    required this.bestRank,
    required this.bestEntity,
  });

  const _ArtistCatalogHistory.empty()
    : peakByEntityId = const {},
      bestRank = null,
      bestEntity = null;

  final Map<String, int> peakByEntityId;
  final int? bestRank;
  final ChartEntitySnapshot? bestEntity;
}
