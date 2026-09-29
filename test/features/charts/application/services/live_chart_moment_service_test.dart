import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/application/services/live_chart_moment_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  test(
    'builds live song movement Moments from qualified-play ranking changes',
    () async {
      final plays = [
        _play(
          id: 'play-1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 12),
        ),
        _play(
          id: 'play-2',
          songId: 'song-b',
          albumId: 'album-b',
          qualifiedAt: DateTime.utc(2026, 9, 28, 12, 1),
        ),
        _play(
          id: 'play-3',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 12, 2),
        ),
      ];

      final library = _LibraryRepository(
        tracks: [_track('song-a', 'album-a'), _track('song-b', 'album-b')],
        albums: [_album('album-a'), _album('album-b')],
      );

      final builder = ChartSnapshotBuilderService(
        qualifiedPlays: _QualifiedPlayRepository(plays),
        library: library,
        charts: _ChartRepository(),
      );

      final moments = _ChartMomentRepository();

      final service = LiveChartMomentService(
        builder: builder,
        library: library,
        moments: moments,
      );

      final result = await service.load(
        chartType: ChartType.songs,
        referenceLocal: DateTime(2026, 9, 28, 10),
      );

      expect(result.snapshot.entries, hasLength(2));

      final songAMovementEvents = result.moments
          .where(
            (event) =>
                event.entity.entityId == 'song-a' &&
                (event.eventType == ChartMomentEventType.rankRise ||
                    event.eventType == ChartMomentEventType.rankFall),
          )
          .toList(growable: false);

      expect(songAMovementEvents, hasLength(2));
      expect(songAMovementEvents.first.entity.artistId, 'artist-album-a');

      expect(songAMovementEvents[0].eventType, ChartMomentEventType.rankFall);
      expect(songAMovementEvents[0].previousRank, 1);
      expect(songAMovementEvents[0].currentRank, 2);

      expect(songAMovementEvents[1].eventType, ChartMomentEventType.rankRise);
      expect(songAMovementEvents[1].previousRank, 2);
      expect(songAMovementEvents[1].currentRank, 1);

      expect(
        songAMovementEvents[0].deduplicationKey,
        isNot(songAMovementEvents[1].deduplicationKey),
      );

      final persisted = await moments.getRecent();

      expect(persisted, hasLength(result.moments.length));
      expect(
        persisted.map((event) => event.deduplicationKey).toSet(),
        result.moments.map((event) => event.deduplicationKey).toSet(),
      );
    },
  );

  test('rebuilding live chart produces stable Moment identities', () async {
    final plays = [
      _play(
        id: 'play-1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 12),
      ),
      _play(
        id: 'play-2',
        songId: 'song-b',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 28, 12, 1),
      ),
    ];

    final library = _LibraryRepository(
      tracks: [_track('song-a', 'album-a'), _track('song-b', 'album-b')],
      albums: [_album('album-a'), _album('album-b')],
    );

    final moments = _ChartMomentRepository();

    final service = LiveChartMomentService(
      builder: ChartSnapshotBuilderService(
        qualifiedPlays: _QualifiedPlayRepository(plays),
        library: library,
        charts: _ChartRepository(),
      ),
      library: library,
      moments: moments,
    );

    final first = await service.load(
      chartType: ChartType.songs,
      referenceLocal: DateTime(2026, 9, 28, 10),
    );

    final second = await service.load(
      chartType: ChartType.songs,
      referenceLocal: DateTime(2026, 9, 28, 10),
    );

    expect(first.moments, isNotEmpty);

    expect(
      first.moments.map((event) => event.deduplicationKey).toList(),
      second.moments.map((event) => event.deduplicationKey).toList(),
    );

    final persisted = await moments.getRecent();

    expect(persisted, hasLength(first.moments.length));
    expect(
      persisted.map((event) => event.deduplicationKey).toSet(),
      first.moments.map((event) => event.deduplicationKey).toSet(),
    );
  });

  test(
    'previous finalized Top-200 standing continues without false reentry',
    () async {
      final fixture = _crowdedTop120Fixture();

      final previous = _historySnapshot(
        id: 'previous-extended',
        weekStartUtc: DateTime(2026, 9, 20).toUtc(),
        weekEndUtc: DateTime(2026, 9, 27).toUtc(),
        rank: 143,
        peakRank: 143,
      );

      final library = _LibraryRepository(
        tracks: fixture.tracks,
        albums: [_album('album-a')],
      );

      final moments = _ChartMomentRepository();

      final service = LiveChartMomentService(
        builder: ChartSnapshotBuilderService(
          qualifiedPlays: _QualifiedPlayRepository(fixture.plays),
          library: library,
          charts: _ChartRepository(history: [previous]),
        ),
        library: library,
        moments: moments,
      );

      final result = await service.load(
        chartType: ChartType.songs,
        referenceLocal: DateTime(2026, 9, 28, 10),
      );

      final targetEvents = result.moments
          .where((event) => event.entity.entityId == 'song-z')
          .toList(growable: false);

      expect(
        targetEvents.where(
          (event) => event.eventType == ChartMomentEventType.debut,
        ),
        isEmpty,
      );

      expect(
        targetEvents.where(
          (event) => event.eventType == ChartMomentEventType.reentry,
        ),
        isEmpty,
      );

      expect(
        targetEvents.where(
          (event) =>
              event.eventType == ChartMomentEventType.thresholdReturn &&
              event.threshold == 200,
        ),
        isEmpty,
      );

      final peaks = targetEvents
          .where((event) => event.eventType == ChartMomentEventType.newPeak)
          .toList(growable: false);

      expect(peaks, hasLength(1));
      expect(peaks.single.previousPeakRank, 143);
      expect(peaks.single.currentPeakRank, 120);

      final persisted = await moments.getRecent();

      expect(
        persisted.any(
          (event) =>
              event.entity.entityId == 'song-z' &&
              event.eventType == ChartMomentEventType.newPeak,
        ),
        isTrue,
      );
    },
  );

  test(
    'historical Top-200 absence becomes reentry without false new peak',
    () async {
      final fixture = _crowdedTop120Fixture();

      final historical = _historySnapshot(
        id: 'older-history',
        weekStartUtc: DateTime(2026, 9, 13).toUtc(),
        weekEndUtc: DateTime(2026, 9, 20).toUtc(),
        rank: 80,
        peakRank: 80,
      );

      final library = _LibraryRepository(
        tracks: fixture.tracks,
        albums: [_album('album-a')],
      );

      final moments = _ChartMomentRepository();

      final service = LiveChartMomentService(
        builder: ChartSnapshotBuilderService(
          qualifiedPlays: _QualifiedPlayRepository(fixture.plays),
          library: library,
          charts: _ChartRepository(history: [historical]),
        ),
        library: library,
        moments: moments,
      );

      final result = await service.load(
        chartType: ChartType.songs,
        referenceLocal: DateTime(2026, 9, 28, 10),
      );

      final targetEvents = result.moments
          .where((event) => event.entity.entityId == 'song-z')
          .toList(growable: false);

      expect(
        targetEvents.where(
          (event) => event.eventType == ChartMomentEventType.reentry,
        ),
        hasLength(1),
      );

      expect(
        targetEvents.where(
          (event) =>
              event.eventType == ChartMomentEventType.thresholdReturn &&
              event.threshold == 200,
        ),
        hasLength(1),
      );

      expect(
        targetEvents.where(
          (event) => event.eventType == ChartMomentEventType.debut,
        ),
        isEmpty,
      );

      expect(
        targetEvents.where(
          (event) => event.eventType == ChartMomentEventType.newPeak,
        ),
        isEmpty,
      );
    },
  );

  test(
    'no chart history produces debut first Top-200 entry and first live peak',
    () async {
      final fixture = _crowdedTop120Fixture();

      final library = _LibraryRepository(
        tracks: fixture.tracks,
        albums: [_album('album-a')],
      );

      final moments = _ChartMomentRepository();

      final service = LiveChartMomentService(
        builder: ChartSnapshotBuilderService(
          qualifiedPlays: _QualifiedPlayRepository(fixture.plays),
          library: library,
          charts: _ChartRepository(),
        ),
        library: library,
        moments: moments,
      );

      final result = await service.load(
        chartType: ChartType.songs,
        referenceLocal: DateTime(2026, 9, 28, 10),
      );

      final targetEvents = result.moments
          .where((event) => event.entity.entityId == 'song-z')
          .toList(growable: false);

      expect(
        targetEvents.where(
          (event) => event.eventType == ChartMomentEventType.debut,
        ),
        hasLength(1),
      );

      expect(
        targetEvents.where(
          (event) =>
              event.eventType == ChartMomentEventType.firstThresholdEntry &&
              event.threshold == 200,
        ),
        hasLength(1),
      );

      final peaks = targetEvents
          .where((event) => event.eventType == ChartMomentEventType.newPeak)
          .toList(growable: false);

      expect(peaks, hasLength(1));
      expect(peaks.single.previousPeakRank, isNull);
      expect(peaks.single.currentPeakRank, 120);

      final persisted = await moments.getRecent();

      expect(
        persisted.any(
          (event) =>
              event.entity.entityId == 'song-z' &&
              event.eventType == ChartMomentEventType.debut,
        ),
        isTrue,
      );
    },
  );
  test('supports album movement Moments through the same pipeline', () async {
    final plays = [
      _play(
        id: 'play-1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 12),
      ),
      _play(
        id: 'play-2',
        songId: 'song-b',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 28, 12, 1),
      ),
      _play(
        id: 'play-3',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 12, 2),
      ),
    ];

    final library = _LibraryRepository(
      tracks: [_track('song-a', 'album-a'), _track('song-b', 'album-b')],
      albums: [_album('album-a'), _album('album-b')],
    );

    final moments = _ChartMomentRepository();

    final service = LiveChartMomentService(
      builder: ChartSnapshotBuilderService(
        qualifiedPlays: _QualifiedPlayRepository(plays),
        library: library,
        charts: _ChartRepository(),
      ),
      library: library,
      moments: moments,
    );

    final result = await service.load(
      chartType: ChartType.albums,
      referenceLocal: DateTime(2026, 9, 28, 10),
    );

    final albumAMovementEvents = result.moments
        .where(
          (event) =>
              event.entity.entityId == 'album-a' &&
              (event.eventType == ChartMomentEventType.rankRise ||
                  event.eventType == ChartMomentEventType.rankFall),
        )
        .toList(growable: false);

    expect(albumAMovementEvents, hasLength(2));
    expect(albumAMovementEvents.first.entity.artistId, 'artist-album-a');
    expect(albumAMovementEvents.first.eventType, ChartMomentEventType.rankFall);
    expect(albumAMovementEvents.last.eventType, ChartMomentEventType.rankRise);
  });
}

QualifiedPlay _play({
  required String id,
  required String songId,
  required String albumId,
  required DateTime qualifiedAt,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session-$id',
    songId: songId,
    artistId: 'artist-$albumId',
    albumId: albumId,
    albumEditionId: 'edition-$albumId',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

LibraryTrack _track(String songId, String albumId) {
  return LibraryTrack(
    songId: songId,
    title: 'Title $songId',
    artistId: 'artist-$albumId',
    artistName: 'Artist $albumId',
    albumId: albumId,
    albumTitle: 'Album $albumId',
    albumEditionId: 'edition-$albumId',
    albumEditionTitle: 'Album $albumId',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: true,
  );
}

LibraryAlbum _album(String albumId) {
  return LibraryAlbum(
    albumId: albumId,
    title: 'Album $albumId',
    artistId: 'artist-$albumId',
    artistName: 'Artist $albumId',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
  );
}

ChartSnapshot _historySnapshot({
  required String id,
  required DateTime weekStartUtc,
  required DateTime weekEndUtc,
  required int rank,
  required int peakRank,
}) {
  return ChartSnapshot(
    id: id,
    chartType: ChartType.songs,
    weekStartUtc: weekStartUtc,
    weekEndUtc: weekEndUtc,
    finalizedAt: weekEndUtc,
    entries: [
      ChartEntry(
        entity: const ChartEntitySnapshot(
          entityId: 'song-z',
          title: 'Historical Song Z',
          artistName: 'Historical Artist',
          albumTitle: 'Historical Album',
        ),
        rank: rank,
        qualifiedStreamCount: 1,
        lastQualifiedAt: weekEndUtc.subtract(const Duration(hours: 1)),
        previousFinalRank: null,
        peakRank: peakRank,
        peakAchievedAt: weekStartUtc.add(const Duration(days: 1)),
        weeksOnChart: rank <= 100 ? 1 : 0,
        movement: ChartMovement.newEntry,
      ),
    ],
  );
}

({List<QualifiedPlay> plays, List<LibraryTrack> tracks})
_crowdedTop120Fixture() {
  final qualifiedAt = DateTime.utc(2026, 9, 28, 12);

  final songIds = [
    for (var index = 0; index < 119; index++)
      'song-${index.toString().padLeft(3, '0')}',
    'song-z',
  ];

  return (
    plays: [
      for (final songId in songIds)
        _play(
          id: 'play-$songId',
          songId: songId,
          albumId: 'album-a',
          qualifiedAt: qualifiedAt,
        ),
    ],
    tracks: [for (final songId in songIds) _track(songId, 'album-a')],
  );
}

class _QualifiedPlayRepository implements QualifiedPlayRepository {
  _QualifiedPlayRepository(this.plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return plays
        .where((play) {
          final qualifiedAt = play.qualifiedAt.toUtc();

          if (qualifiedAtOrAfter != null &&
              qualifiedAt.isBefore(qualifiedAtOrAfter.toUtc())) {
            return false;
          }

          if (qualifiedBefore != null &&
              !qualifiedAt.isBefore(qualifiedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<void> create(QualifiedPlay play) => throw UnimplementedError();

  @override
  Future<QualifiedPlay?> getById(String id) => throw UnimplementedError();

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId) =>
      throw UnimplementedError();

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) => throw UnimplementedError();

  @override
  Future<void> save(QualifiedPlay play) => throw UnimplementedError();
}

class _LibraryRepository implements LibraryQueryRepository {
  _LibraryRepository({required this.tracks, required this.albums});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => tracks;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) =>
      throw UnimplementedError();

  @override
  Future<LibraryArtist?> getArtistById(String artistId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryArtist>> getArtists() => throw UnimplementedError();

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) =>
      throw UnimplementedError();

  @override
  Future<LibraryTrack?> getTrackById(String songId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) => throw UnimplementedError();
}

class _ChartRepository implements ChartRepository {
  _ChartRepository({List<ChartSnapshot> history = const []})
    : history = List.unmodifiable(history);

  final List<ChartSnapshot> history;

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final matching = history
        .where((snapshot) => snapshot.chartType == chartType)
        .toList(growable: false);

    if (limit == null || limit >= matching.length) {
      return List.unmodifiable(matching);
    }

    return List.unmodifiable(matching.take(limit));
  }

  @override
  Future<ChartSnapshot?> getById(String id) => throw UnimplementedError();

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) =>
      throw UnimplementedError();
}

class _ChartMomentRepository implements ChartMomentRepository {
  final Map<String, ChartMomentEvent> _eventsByDeduplicationKey = {};

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) async {
    for (final event in events) {
      _eventsByDeduplicationKey.putIfAbsent(
        event.deduplicationKey,
        () => event,
      );
    }
  }

  @override
  Future<void> replaceFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async {
    final normalizedWeekStart = weekStartUtc.toUtc();

    _eventsByDeduplicationKey.removeWhere(
      (_, event) =>
          event.scope == ChartMomentScope.finalized &&
          event.chartType == chartType &&
          event.weekStartUtc.toUtc() == normalizedWeekStart,
    );

    for (final event in events) {
      _eventsByDeduplicationKey[event.deduplicationKey] = event;
    }
  }

  @override
  Future<ChartMomentEvent?> getById(String id) async {
    for (final event in _eventsByDeduplicationKey.values) {
      if (event.id == id) {
        return event;
      }
    }

    return null;
  }

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async {
    final events = _eventsByDeduplicationKey.values.toList()
      ..sort((a, b) {
        final occurred = b.occurredAt.compareTo(a.occurredAt);

        if (occurred != 0) {
          return occurred;
        }

        return b.id.compareTo(a.id);
      });

    if (limit == null || limit >= events.length) {
      return List.unmodifiable(events);
    }

    return List.unmodifiable(events.take(limit));
  }
}
