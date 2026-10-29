import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/application/services/this_week_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/services/chart_week_resolver.dart';
import 'package:sonus_next/features/charts/domain/services/release_chart_eligibility.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  QualifiedPlay play({
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

  PlaybackSession playbackSession({
    required String id,
    required String songId,
    required String albumId,
    String? songTitle,
    String? artistName,
    String? albumTitle,
  }) {
    return PlaybackSession(
      id: id,
      songId: songId,
      artistId: 'artist-$albumId',
      albumId: albumId,
      albumEditionId: 'edition-$albumId',
      songTitle: songTitle ?? 'Historical $songId',
      artistName: artistName ?? 'Historical Artist $albumId',
      albumTitle: albumTitle ?? 'Historical Album $albumId',
      albumEditionTitle: albumTitle ?? 'Historical Album $albumId',
      startedAt: DateTime.utc(2026, 9, 28, 10),
      endedAt: DateTime.utc(2026, 9, 28, 10, 3),
      listenedDuration: const Duration(minutes: 3),
      trackDuration: const Duration(minutes: 3),
      finalPosition: const Duration(minutes: 3),
      createdAt: DateTime.utc(2026, 9, 28, 10),
      updatedAt: DateTime.utc(2026, 9, 28, 10, 3),
    );
  }

  LibraryTrack track({
    required String songId,
    required String albumId,
    bool blocked = false,
    bool available = true,
  }) {
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
      isAvailable: available,
      isSongBlocked: blocked,
    );
  }

  LibraryAlbum album(String albumId) {
    return LibraryAlbum(
      albumId: albumId,
      title: 'Album $albumId',
      artistId: 'artist-$albumId',
      artistName: 'Artist $albumId',
      trackCount: 1,
      dateAdded: DateTime.utc(2026, 9, 1),
    );
  }

  test('builds song chart from qualified plays', () async {
    final qualifiedPlays = _FakeQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: '2',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 29, 10),
      ),
      play(
        id: '3',
        songId: 'song-b',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 30, 10),
      ),
    ]);

    final library = _FakeLibraryQueryRepository(
      tracks: [
        track(songId: 'song-a', albumId: 'album-a'),
        track(songId: 'song-b', albumId: 'album-b'),
      ],
      albums: [album('album-a'), album('album-b')],
    );

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      charts: _FakeChartRepository(),
    );

    final snapshot = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(snapshot.chartType, ChartType.songs);
    expect(snapshot.isLive, isTrue);
    expect(snapshot.entries, hasLength(2));

    expect(snapshot.entries[0].entity.entityId, 'song-a');
    expect(snapshot.entries[0].entity.artistId, 'artist-album-a');
    expect(snapshot.entries[0].qualifiedStreamCount, 2);
    expect(snapshot.entries[0].rank, 1);

    expect(snapshot.entries[1].entity.entityId, 'song-b');
    expect(snapshot.entries[1].qualifiedStreamCount, 1);
    expect(snapshot.entries[1].rank, 2);
  });

  test('one qualified song play contributes one album chart unit', () async {
    final qualifiedPlays = _FakeQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a1',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: '2',
        songId: 'song-a2',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 29, 10),
      ),
      play(
        id: '3',
        songId: 'song-b1',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 30, 10),
      ),
    ]);

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: qualifiedPlays,
      library: _FakeLibraryQueryRepository(
        tracks: [
          track(songId: 'song-a1', albumId: 'album-a'),
          track(songId: 'song-a2', albumId: 'album-a'),
          track(songId: 'song-b1', albumId: 'album-b'),
        ],
        albums: [album('album-a'), album('album-b')],
      ),
      charts: _FakeChartRepository(),
    );

    final snapshot = await builder.build(
      chartType: ChartType.albums,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(snapshot.entries, hasLength(2));

    expect(snapshot.entries[0].entity.entityId, 'album-a');
    expect(snapshot.entries[0].entity.artistId, 'artist-album-a');
    expect(snapshot.entries[0].qualifiedStreamCount, 2);

    expect(snapshot.entries[1].entity.entityId, 'album-b');
    expect(snapshot.entries[1].qualifiedStreamCount, 1);
  });

  test('blocked song is excluded from current song chart', () async {
    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'blocked-song',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
        play(
          id: '2',
          songId: 'active-song',
          albumId: 'album-b',
          qualifiedAt: DateTime.utc(2026, 9, 28, 11),
        ),
      ]),
      library: _FakeLibraryQueryRepository(
        tracks: [
          track(songId: 'blocked-song', albumId: 'album-a', blocked: true),
          track(songId: 'active-song', albumId: 'album-b'),
        ],
        albums: [album('album-a'), album('album-b')],
      ),
      charts: _FakeChartRepository(),
    );

    final snapshot = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(snapshot.entries, hasLength(1));
    expect(snapshot.entries.single.entity.entityId, 'active-song');
  });

  test('unavailable song can remain in chart standings', () async {
    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'missing-file-song',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]),
      library: _FakeLibraryQueryRepository(
        tracks: [
          track(
            songId: 'missing-file-song',
            albumId: 'album-a',
            available: false,
          ),
        ],
        albums: [album('album-a')],
      ),
      charts: _FakeChartRepository(),
    );

    final snapshot = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(snapshot.entries, hasLength(1));
    expect(snapshot.entries.single.entity.entityId, 'missing-file-song');
  });

  test('deleted library entity is excluded from live snapshot', () async {
    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'deleted-song',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]),
      library: _FakeLibraryQueryRepository(
        tracks: const [],
        albums: [album('album-a')],
      ),
      charts: _FakeChartRepository(),
    );

    final snapshot = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(snapshot.entries, isEmpty);
  });

  test('finalized Top 100 entry increments weeks on chart', () async {
    final previous = ChartSnapshot(
      id: 'previous',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 20),
      weekEndUtc: DateTime.utc(2026, 9, 27),
      finalizedAt: DateTime.utc(2026, 9, 27),
      entries: [
        ChartEntry(
          entity: const ChartEntitySnapshot(
            entityId: 'song-a',
            title: 'Old Song A',
            artistName: 'Old Artist',
            albumTitle: 'Old Album',
          ),
          rank: 8,
          qualifiedStreamCount: 4,
          lastQualifiedAt: DateTime.utc(2026, 9, 26),
          previousFinalRank: null,
          peakRank: 3,
          peakAchievedAt: DateTime.utc(2026, 9, 22),
          weeksOnChart: 1,
          movement: ChartMovement.newEntry,
        ),
      ],
    );

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
        play(
          id: '2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 29, 10),
        ),
      ]),
      library: _FakeLibraryQueryRepository(
        tracks: [track(songId: 'song-a', albumId: 'album-a')],
        albums: [album('album-a')],
      ),
      charts: _FakeChartRepository(history: [previous]),
      playbackSessions: _FakePlaybackSessionRepository([
        playbackSession(id: 'session-1', songId: 'song-a', albumId: 'album-a'),
        playbackSession(id: 'session-2', songId: 'song-a', albumId: 'album-a'),
      ]),
    );

    final snapshot = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
      finalizedAt: DateTime.utc(2026, 10, 4),
    );

    final entry = snapshot.entries.single;

    expect(entry.previousFinalRank, 8);
    expect(entry.weeksOnChart, 2);
    expect(entry.movement, ChartMovement.up);

    // The song reached #1 this week, improving its previous #3 peak.
    expect(entry.peakRank, 1);
  });

  test(
    'finalized snapshot does not promote provisional intraweek peak to career peak',
    () async {
      final plays = <QualifiedPlay>[
        play(
          id: 'target',
          songId: 'song-c',
          albumId: 'album-c',
          qualifiedAt: DateTime.utc(2026, 9, 28, 1),
        ),
      ];

      for (var index = 0; index < 6; index++) {
        final songId = 'song-${index + 1}';
        final albumId = 'album-${index + 1}';

        plays.add(
          play(
            id: 'competitor-${index + 1}-a',
            songId: songId,
            albumId: albumId,
            qualifiedAt: DateTime.utc(
              2026,
              9,
              28,
              2,
            ).add(Duration(minutes: index * 2)),
          ),
        );

        plays.add(
          play(
            id: 'competitor-${index + 1}-b',
            songId: songId,
            albumId: albumId,
            qualifiedAt: DateTime.utc(
              2026,
              9,
              28,
              2,
            ).add(Duration(minutes: index * 2 + 1)),
          ),
        );
      }

      final sessions = [
        playbackSession(
          id: 'session-target',
          songId: 'song-c',
          albumId: 'album-c',
        ),
        for (var index = 0; index < 6; index++) ...[
          playbackSession(
            id: 'session-competitor-${index + 1}-a',
            songId: 'song-${index + 1}',
            albumId: 'album-${index + 1}',
          ),
          playbackSession(
            id: 'session-competitor-${index + 1}-b',
            songId: 'song-${index + 1}',
            albumId: 'album-${index + 1}',
          ),
        ],
      ];

      final builder = ChartSnapshotBuilderService(
        qualifiedPlays: _FakeQualifiedPlayRepository(plays),
        library: _FakeLibraryQueryRepository(
          tracks: const [],
          albums: const [],
        ),
        charts: _FakeChartRepository(),
        playbackSessions: _FakePlaybackSessionRepository(sessions),
      );

      final snapshot = await builder.build(
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        finalizedAt: DateTime.utc(2026, 10, 4),
      );

      final target = snapshot.entries.singleWhere(
        (entry) => entry.entity.entityId == 'song-c',
      );

      // song-c temporarily held #1 after its first qualified play, but six
      // two-stream competitors finish ahead of it. Its official career peak
      // therefore comes from the finalized weekly rank, not that live #1.
      expect(target.rank, 7);
      expect(target.peakRank, 7);
      expect(target.peakAchievedAt, target.lastQualifiedAt);
    },
  );
  test('live snapshot does not increment finalized weeks on chart', () async {
    final previous = ChartSnapshot(
      id: 'previous',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 20),
      weekEndUtc: DateTime.utc(2026, 9, 27),
      finalizedAt: DateTime.utc(2026, 9, 27),
      entries: [
        ChartEntry(
          entity: const ChartEntitySnapshot(
            entityId: 'song-a',
            title: 'Old Song A',
            artistName: 'Old Artist',
            albumTitle: 'Old Album',
          ),
          rank: 8,
          qualifiedStreamCount: 4,
          lastQualifiedAt: DateTime.utc(2026, 9, 26),
          previousFinalRank: null,
          peakRank: 3,
          peakAchievedAt: DateTime.utc(2026, 9, 22),
          weeksOnChart: 1,
          movement: ChartMovement.newEntry,
        ),
      ],
    );

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]),
      library: _FakeLibraryQueryRepository(
        tracks: [track(songId: 'song-a', albumId: 'album-a')],
        albums: [album('album-a')],
      ),
      charts: _FakeChartRepository(history: [previous]),
      playbackSessions: _FakePlaybackSessionRepository([
        playbackSession(id: 'session-1', songId: 'song-a', albumId: 'album-a'),
        playbackSession(id: 'session-2', songId: 'song-a', albumId: 'album-a'),
      ]),
    );

    final snapshot = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(snapshot.entries.single.weeksOnChart, 1);
  });

  test(
    'rebuilding a finalized week ignores that week and future weeks in history',
    () async {
      final previous = ChartSnapshot(
        id: 'previous',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 20),
        weekEndUtc: DateTime.utc(2026, 9, 27),
        finalizedAt: DateTime.utc(2026, 9, 27),
        entries: [
          ChartEntry(
            entity: const ChartEntitySnapshot(
              entityId: 'song-a',
              title: 'Song A',
              artistName: 'Artist A',
              albumTitle: 'Album A',
            ),
            rank: 8,
            qualifiedStreamCount: 5,
            lastQualifiedAt: DateTime.utc(2026, 9, 26),
            previousFinalRank: null,
            peakRank: 3,
            peakAchievedAt: DateTime.utc(2026, 9, 22),
            weeksOnChart: 1,
            movement: ChartMovement.newEntry,
          ),
        ],
      );

      final existingCurrent = ChartSnapshot(
        id: 'current-existing',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        finalizedAt: DateTime.utc(2026, 10, 4),
        revision: 1,
        entries: [
          ChartEntry(
            entity: const ChartEntitySnapshot(
              entityId: 'song-a',
              title: 'Song A',
              artistName: 'Artist A',
              albumTitle: 'Album A',
            ),
            rank: 4,
            qualifiedStreamCount: 7,
            lastQualifiedAt: DateTime.utc(2026, 10, 3),
            previousFinalRank: 8,
            peakRank: 2,
            peakAchievedAt: DateTime.utc(2026, 9, 29),
            weeksOnChart: 2,
            movement: ChartMovement.up,
          ),
        ],
      );

      final future = ChartSnapshot(
        id: 'future',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 10, 4),
        weekEndUtc: DateTime.utc(2026, 10, 11),
        finalizedAt: DateTime.utc(2026, 10, 11),
        entries: [
          ChartEntry(
            entity: const ChartEntitySnapshot(
              entityId: 'song-a',
              title: 'Song A',
              artistName: 'Artist A',
              albumTitle: 'Album A',
            ),
            rank: 2,
            qualifiedStreamCount: 12,
            lastQualifiedAt: DateTime.utc(2026, 10, 10),
            previousFinalRank: 4,
            peakRank: 1,
            peakAchievedAt: DateTime.utc(2026, 10, 6),
            weeksOnChart: 3,
            movement: ChartMovement.up,
          ),
        ],
      );

      final builder = ChartSnapshotBuilderService(
        qualifiedPlays: _FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 10),
          ),
          play(
            id: '2',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 29, 10),
          ),
        ]),
        library: _FakeLibraryQueryRepository(
          tracks: [track(songId: 'song-a', albumId: 'album-a')],
          albums: [album('album-a')],
        ),
        charts: _FakeChartRepository(
          history: [future, existingCurrent, previous],
        ),
        playbackSessions: _FakePlaybackSessionRepository([
          playbackSession(
            id: 'session-1',
            songId: 'song-a',
            albumId: 'album-a',
          ),
          playbackSession(
            id: 'session-2',
            songId: 'song-a',
            albumId: 'album-a',
          ),
        ]),
      );

      final rebuilt = await builder.build(
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        finalizedAt: DateTime.utc(2026, 10, 4),
        revision: 2,
      );

      final entry = rebuilt.entries.single;

      expect(entry.previousFinalRank, 8);
      expect(entry.weeksOnChart, 2);

      // Current/future stored snapshots must not leak their later peaks backward.
      expect(entry.peakRank, 1);
      expect(entry.peakAchievedAt, DateTime.utc(2026, 9, 29, 10));
    },
  );
  test(
    'finalized history uses playback-session identity even when song is no longer in library',
    () async {
      final qualifiedPlays = _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'deleted-song',
          albumId: 'deleted-album',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final builder = ChartSnapshotBuilderService(
        qualifiedPlays: qualifiedPlays,
        library: _FakeLibraryQueryRepository(
          tracks: const [],
          albums: const [],
        ),
        charts: _FakeChartRepository(),
        playbackSessions: _FakePlaybackSessionRepository([
          playbackSession(
            id: 'session-1',
            songId: 'deleted-song',
            albumId: 'deleted-album',
            songTitle: 'Original Song Title',
            artistName: 'Original Artist',
            albumTitle: 'Original Album',
          ),
        ]),
      );

      final snapshot = await builder.build(
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        finalizedAt: DateTime.utc(2026, 10, 4),
      );

      expect(snapshot.entries, hasLength(1));

      final entry = snapshot.entries.single;

      expect(entry.entity.entityId, 'deleted-song');
      expect(entry.entity.title, 'Original Song Title');
      expect(entry.entity.artistId, 'artist-deleted-album');
      expect(entry.entity.artistName, 'Original Artist');
      expect(entry.entity.albumTitle, 'Original Album');
    },
  );
  test('deterministic snapshot id is stable for type and week', () async {
    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository(const []),
      library: _FakeLibraryQueryRepository(tracks: const [], albums: const []),
      charts: _FakeChartRepository(),
    );

    final first = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    final second = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
    );

    expect(first.id, second.id);
    expect(first.id, contains('songs'));
  });

  group('SN-50 one eligibility policy (E-Q19)', () {
    final weekStart = DateTime.utc(2026, 9, 27);
    final weekEnd = DateTime.utc(2026, 10, 4);

    final plays = [
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: '2',
        songId: 'blocked-song',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 28, 11),
      ),
      play(
        id: '3',
        songId: 'blocked-song',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 28, 12),
      ),
      play(
        id: '4',
        songId: 'song-c',
        albumId: 'album-c',
        qualifiedAt: DateTime.utc(2026, 9, 28, 13),
      ),
    ];

    ChartSnapshotBuilderService builderFor() => ChartSnapshotBuilderService(
      qualifiedPlays: _FakeQualifiedPlayRepository(plays),
      library: _FakeLibraryQueryRepository(
        tracks: [
          track(songId: 'song-a', albumId: 'album-a'),
          track(songId: 'blocked-song', albumId: 'album-b', blocked: true),
          track(songId: 'song-c', albumId: 'album-c'),
        ],
        albums: [album('album-a'), album('album-b'), album('album-c')],
      ),
      charts: _FakeChartRepository(),
      playbackSessions: _FakePlaybackSessionRepository([
        for (final qualified in plays)
          playbackSession(
            id: qualified.playbackSessionId,
            songId: qualified.songId,
            albumId: qualified.albumId,
          ),
      ]),
    );

    test('a song blocked when the week is finalized is left out', () async {
      final finalized = await builderFor().build(
        chartType: ChartType.songs,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        finalizedAt: weekEnd,
      );

      expect(finalized.entries.map((entry) => entry.entity.entityId), [
        'song-c',
        'song-a',
      ]);
      expect(finalized.entries.map((entry) => entry.rank), [1, 2]);
    });

    test(
      'provisional and finalized builds rank the same plays alike',
      () async {
        final builder = builderFor();

        for (final chartType in ChartType.values) {
          final provisional = await builder.build(
            chartType: chartType,
            weekStartUtc: weekStart,
            weekEndUtc: weekEnd,
          );
          final finalized = await builder.build(
            chartType: chartType,
            weekStartUtc: weekStart,
            weekEndUtc: weekEnd,
            finalizedAt: weekEnd,
          );

          List<(String, int, ChartMovement)> ranking(ChartSnapshot snapshot) =>
              [
                for (final entry in snapshot.entries)
                  (entry.entity.entityId, entry.rank, entry.movement),
              ];

          expect(
            ranking(provisional),
            ranking(finalized),
            reason: '$chartType',
          );
        }
      },
    );
  });

  group('SN-50 future album owner attribution (E-Q13)', () {
    final weekStart = DateTime.utc(2026, 9, 27);
    final weekEnd = DateTime.utc(2026, 10, 4);

    // A made-up soundtrack whose songs are sung by different artists.
    final plays = [
      play(
        id: '1',
        songId: 'song-one',
        albumId: 'soundtrack',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: '2',
        songId: 'song-two',
        albumId: 'soundtrack',
        qualifiedAt: DateTime.utc(2026, 9, 28, 11),
      ),
    ];
    final sessions = _FakePlaybackSessionRepository([
      playbackSession(
        id: 'session-1',
        songId: 'song-one',
        albumId: 'soundtrack',
        artistName: 'Lead Singer',
        albumTitle: 'Harbor Lights (Original Soundtrack)',
      ),
      playbackSession(
        id: 'session-2',
        songId: 'song-two',
        albumId: 'soundtrack',
        artistName: 'Duet Partner',
        albumTitle: 'Harbor Lights (Original Soundtrack)',
      ),
    ]);

    Future<ChartSnapshot> finalizedAlbums(List<LibraryAlbum> albums) {
      return ChartSnapshotBuilderService(
        qualifiedPlays: _FakeQualifiedPlayRepository(plays),
        library: _FakeLibraryQueryRepository(tracks: const [], albums: albums),
        charts: _FakeChartRepository(),
        playbackSessions: sessions,
      ).build(
        chartType: ChartType.albums,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        finalizedAt: weekEnd,
      );
    }

    test('a newly finalized album entry credits the album artist, not the '
        'last song played', () async {
      final snapshot = await finalizedAlbums([
        LibraryAlbum(
          albumId: 'soundtrack',
          title: 'Harbor Lights (Original Soundtrack)',
          artistId: 'artist-cast',
          artistName: 'Harbor Lights Cast',
          trackCount: 2,
          dateAdded: DateTime.utc(2026, 9, 1),
        ),
      ]);

      final entity = snapshot.entries.single.entity;
      expect(entity.artistId, 'artist-cast');
      expect(entity.artistName, 'Harbor Lights Cast');
      expect(entity.title, 'Harbor Lights (Original Soundtrack)');
    });

    test('an album no longer in the library keeps the artist recorded at '
        'play time', () async {
      final entity = (await finalizedAlbums(const [])).entries.single.entity;

      expect(entity.artistId, 'artist-soundtrack');
      expect(entity.artistName, 'Duet Partner');
    });
  });

  group('SN-50 This Week (E-Q5, E-Q18)', () {
    final now = DateTime(2026, 10, 7, 12);
    final week = const ChartWeekResolver().resolve(now);

    ChartSnapshot finalizedLastWeek(List<(String, int)> ranks) {
      final start = week.startUtc.subtract(const Duration(days: 7));
      return ChartSnapshot(
        id: 'last-week',
        chartType: ChartType.songs,
        weekStartUtc: start,
        weekEndUtc: week.startUtc,
        finalizedAt: week.startUtc,
        entries: [
          for (final (songId, rank) in ranks)
            ChartEntry(
              entity: ChartEntitySnapshot(
                entityId: songId,
                title: 'Stored $songId',
                artistName: 'Stored Artist',
              ),
              rank: rank,
              qualifiedStreamCount: 1,
              lastQualifiedAt: start,
              peakRank: rank,
              peakAchievedAt: start,
              weeksOnChart: 1,
              movement: ChartMovement.newEntry,
            ),
        ],
      );
    }

    test('is provisional, compares with the last finalized week and keeps '
        'its best so far apart from the peak', () async {
      DateTime at(int hours) => week.startUtc.add(Duration(hours: hours));
      final plays = [
        play(id: '1', songId: 'song-a', albumId: 'album-a', qualifiedAt: at(1)),
        play(id: '2', songId: 'song-b', albumId: 'album-b', qualifiedAt: at(2)),
        play(id: '3', songId: 'song-b', albumId: 'album-b', qualifiedAt: at(3)),
        play(
          id: '4',
          songId: 'blocked',
          albumId: 'album-x',
          qualifiedAt: at(4),
        ),
      ];

      final service = ThisWeekChartService(
        // Its chart repository refuses every write.
        builder: ChartSnapshotBuilderService(
          qualifiedPlays: _FakeQualifiedPlayRepository(plays),
          library: _FakeLibraryQueryRepository(
            tracks: [
              track(songId: 'song-a', albumId: 'album-a'),
              track(songId: 'song-b', albumId: 'album-b'),
              track(songId: 'blocked', albumId: 'album-x', blocked: true),
            ],
            albums: [album('album-a'), album('album-b')],
          ),
          charts: _FakeChartRepository(
            history: [
              finalizedLastWeek([('song-a', 3), ('song-b', 1)]),
            ],
          ),
        ),
      );

      final thisWeek = await service.load(
        chartType: ChartType.songs,
        referenceLocal: now,
      );
      final snapshot = thisWeek.snapshot;

      expect(snapshot.isFinalized, isFalse);
      expect(snapshot.weekStartUtc, week.startUtc);
      expect(snapshot.weekEndUtc, week.endUtc);
      expect(snapshot.entries.map((entry) => entry.entity.entityId), [
        'song-b',
        'song-a',
      ]);

      final songA = snapshot.entries[1];
      expect(songA.previousFinalRank, 3);
      expect(songA.movement, ChartMovement.up);
      expect(snapshot.entries[0].movement, ChartMovement.same);

      // song-a led after the first play of the week.
      expect(thisWeek.bestSoFarRank('song-a'), 1);
      expect(thisWeek.bestSoFarRank('song-b'), 1);
      expect(thisWeek.bestSoFarRank('blocked'), isNull);
    });

    test('Singles stay off the provisional release chart', () async {
      final service = ThisWeekChartService(
        builder: ChartSnapshotBuilderService(
          qualifiedPlays: _FakeQualifiedPlayRepository([
            play(
              id: '1',
              songId: 'song-a',
              albumId: 'album-a',
              qualifiedAt: week.startUtc.add(const Duration(hours: 1)),
            ),
            play(
              id: '2',
              songId: 'single-song',
              albumId: 'single',
              qualifiedAt: week.startUtc.add(const Duration(hours: 2)),
            ),
          ]),
          library: _FakeLibraryQueryRepository(
            tracks: const [],
            albums: [album('album-a'), album('single')],
          ),
          charts: _FakeChartRepository(),
        ),
        releaseEligibility: const _Singles({'single'}),
      );

      final thisWeek = await service.load(
        chartType: ChartType.albums,
        referenceLocal: now,
      );

      expect(thisWeek.snapshot.entries.map((entry) => entry.entity.entityId), [
        'album-a',
      ]);
    });
  });
}

class _Singles implements ReleaseChartEligibility {
  const _Singles(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> excludedAlbumIds() async => ids;
}

class _FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  _FakeQualifiedPlayRepository(this.plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return plays
        .where((play) {
          if (qualifiedAtOrAfter != null &&
              play.qualifiedAt.isBefore(qualifiedAtOrAfter)) {
            return false;
          }

          if (qualifiedBefore != null &&
              !play.qualifiedAt.isBefore(qualifiedBefore)) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<void> create(QualifiedPlay play) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(QualifiedPlay play) {
    throw UnimplementedError();
  }
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({required this.tracks, required this.albums});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryArtist>> getArtists() {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) {
    throw UnimplementedError();
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    throw UnimplementedError();
  }
}

class _FakeChartRepository implements ChartRepository {
  _FakeChartRepository({this.history = const []});

  final List<ChartSnapshot> history;

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final matching = history
        .where((snapshot) => snapshot.chartType == chartType)
        .toList(growable: false);

    if (limit == null) {
      return matching;
    }

    return matching.take(limit).toList(growable: false);
  }

  @override
  Future<ChartSnapshot?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) {
    throw UnimplementedError();
  }
}

class _FakePlaybackSessionRepository implements PlaybackSessionRepository {
  _FakePlaybackSessionRepository(this.sessions);

  final List<PlaybackSession> sessions;

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final requested = ids.toSet();

    return sessions
        .where((session) => requested.contains(session.id))
        .toList(growable: false);
  }

  @override
  Future<void> create(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<PlaybackSession?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(PlaybackSession session) {
    throw UnimplementedError();
  }
}
