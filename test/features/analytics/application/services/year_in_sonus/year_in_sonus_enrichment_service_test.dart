import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_month.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_recap.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_enrichment_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  group('YearInSonusEnrichmentService', () {
    test(
      'prefers current library metadata over historical snapshots',
      () async {
        final library = _FakeLibraryQueryRepository(
          tracks: [
            _track(
              songId: 'song_1',
              title: 'Current Track',
              artistId: 'artist_1',
              artistName: 'Current Artist',
              albumId: 'album_1',
              albumTitle: 'Current Album',
            ),
          ],
          artists: [
            LibraryArtist(
              artistId: 'artist_1',
              name: 'Current Artist',
              albumCount: 1,
              songCount: 1,
              dateAdded: DateTime(2026, 1, 1),
              topArtistsArtworkPath: 'artist.jpg',
            ),
          ],
          albums: [
            LibraryAlbum(
              albumId: 'album_1',
              title: 'Current Album',
              artistId: 'artist_1',
              artistName: 'Current Artist',
              trackCount: 1,
              dateAdded: DateTime(2026, 1, 1),
              artworkPath: 'album.jpg',
            ),
          ],
        );

        final sessions = _FakePlaybackSessionRepository([
          _session(
            id: 'session_1',
            songId: 'song_1',
            songTitle: 'Historical Track',
            artistId: 'artist_1',
            artistName: 'Historical Artist',
            albumId: 'album_1',
            albumTitle: 'Historical Album',
            startedAt: DateTime.utc(2026, 6, 1),
          ),
        ]);

        final service = YearInSonusEnrichmentService(
          library: library,
          playbackSessions: sessions,
        );

        final result = await service.enrich(_recap());

        expect(result.tracks.single.title, 'Current Track');
        expect(result.tracks.single.artistName, 'Current Artist');
        expect(result.tracks.single.albumTitle, 'Current Album');

        expect(result.artists.single.name, 'Current Artist');
        expect(result.artists.single.artworkPath, 'artist.jpg');

        expect(result.albums.single.title, 'Current Album');
        expect(result.albums.single.artistName, 'Current Artist');
        expect(result.albums.single.artworkPath, 'album.jpg');

        expect(result.months.single.topSongTitle, 'Current Track');
        expect(result.months.single.topArtistName, 'Current Artist');
      },
    );

    test(
      'falls back to historical session snapshots for deleted entities',
      () async {
        final service = YearInSonusEnrichmentService(
          library: _FakeLibraryQueryRepository(),
          playbackSessions: _FakePlaybackSessionRepository([
            _session(
              id: 'session_1',
              songId: 'song_1',
              songTitle: 'Historical Track',
              artistId: 'artist_1',
              artistName: 'Historical Artist',
              albumId: 'album_1',
              albumTitle: 'Historical Album',
              startedAt: DateTime.utc(2026, 6, 1),
            ),
          ]),
        );

        final result = await service.enrich(_recap());

        final track = result.tracks.single;
        expect(track.track, isNull);
        expect(track.title, 'Historical Track');
        expect(track.artistName, 'Historical Artist');
        expect(track.albumTitle, 'Historical Album');
        expect(track.hasCurrentLibraryEntity, isFalse);
        expect(track.canPlay, isFalse);

        final artist = result.artists.single;
        expect(artist.artist, isNull);
        expect(artist.name, 'Historical Artist');
        expect(artist.subtitle, 'Historical artist');

        final album = result.albums.single;
        expect(album.album, isNull);
        expect(album.title, 'Historical Album');
        expect(album.artistName, 'Historical Artist');

        expect(result.months.single.topSongTitle, 'Historical Track');
        expect(result.months.single.topArtistName, 'Historical Artist');
      },
    );

    test('uses latest historical session for snapshot metadata', () async {
      final service = YearInSonusEnrichmentService(
        library: _FakeLibraryQueryRepository(),
        playbackSessions: _FakePlaybackSessionRepository([
          _session(
            id: 'session_old',
            songId: 'song_1',
            songTitle: 'Old Title',
            artistId: 'artist_1',
            artistName: 'Old Artist',
            albumId: 'album_1',
            albumTitle: 'Old Album',
            startedAt: DateTime.utc(2026, 2, 1),
          ),
          _session(
            id: 'session_new',
            songId: 'song_1',
            songTitle: 'New Title',
            artistId: 'artist_1',
            artistName: 'New Artist',
            albumId: 'album_1',
            albumTitle: 'New Album',
            startedAt: DateTime.utc(2026, 10, 1),
          ),
        ]),
      );

      final result = await service.enrich(_recap());

      expect(result.tracks.single.title, 'New Title');
      expect(result.artists.single.name, 'New Artist');
      expect(result.albums.single.title, 'New Album');
    });

    test(
      'uses unknown fallbacks when no current or historical metadata exists',
      () async {
        final service = YearInSonusEnrichmentService(
          library: _FakeLibraryQueryRepository(),
          playbackSessions: _FakePlaybackSessionRepository(),
        );

        final result = await service.enrich(_recap());

        expect(result.tracks.single.title, 'Unknown Track');
        expect(result.tracks.single.artistName, 'Unknown Artist');
        expect(result.tracks.single.albumTitle, 'Unknown Album');

        expect(result.artists.single.name, 'Unknown Artist');

        expect(result.albums.single.title, 'Unknown Album');
        expect(result.albums.single.artistName, 'Unknown Artist');

        expect(result.months.single.topSongTitle, 'Unknown Track');
        expect(result.months.single.topArtistName, 'Unknown Artist');
      },
    );

    test(
      'keeps historical track non-playable when no current library entity exists',
      () async {
        final service = YearInSonusEnrichmentService(
          library: _FakeLibraryQueryRepository(),
          playbackSessions: _FakePlaybackSessionRepository([
            _session(
              id: 'session_1',
              songId: 'song_1',
              songTitle: 'Historical Track',
              artistId: 'artist_1',
              artistName: 'Historical Artist',
              albumId: 'album_1',
              albumTitle: 'Historical Album',
              startedAt: DateTime.utc(2026, 5, 1),
            ),
          ]),
        );

        final result = await service.enrich(_recap());

        expect(result.tracks.single.hasCurrentLibraryEntity, isFalse);
        expect(result.tracks.single.canPlay, isFalse);
      },
    );
  });
}

YearInSonusRecap _recap() {
  return YearInSonusRecap(
    year: 2026,
    summary: const AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: AnalyticsTimeWindow(startUtc: null, endUtc: null),
      qualifiedStreamCount: 3,
      qualifiedListeningDuration: Duration(minutes: 10),
      distinctSongCount: 1,
      distinctArtistCount: 1,
      distinctAlbumCount: 1,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: const Duration(minutes: 10),
    behavior: const AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: AnalyticsTimeWindow(startUtc: null, endUtc: null),
      sessionCount: 1,
      endedSessionCount: 1,
      completedSessionCount: 1,
      skippedSessionCount: 0,
      stoppedSessionCount: 0,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 1,
      averageQualifiedStreamsPerActiveDay: 3,
      averageQualifiedStreamsPerCalendarDay: 3,
      peakDay: null,
    ),
    topTracks: const [
      YearInSonusRankedEntity(entityId: 'song_1', rank: 1, streams: 3),
    ],
    topArtists: const [
      YearInSonusRankedEntity(entityId: 'artist_1', rank: 1, streams: 3),
    ],
    topAlbums: const [
      YearInSonusRankedEntity(entityId: 'album_1', rank: 1, streams: 3),
    ],
    months: [
      YearInSonusMonth(
        month: DateTime(2026, 6),
        streams: 3,
        topSongId: 'song_1',
        topArtistId: 'artist_1',
      ),
    ],
    longestListeningStreakDays: 1,
  );
}

LibraryTrack _track({
  required String songId,
  required String title,
  required String artistId,
  required String artistName,
  required String albumId,
  required String albumTitle,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    albumId: albumId,
    albumTitle: albumTitle,
    albumEditionId: '${albumId}_edition',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    isAvailable: true,
    filePath: 'track.mp3',
    artworkPath: 'track.jpg',
  );
}

PlaybackSession _session({
  required String id,
  required String songId,
  required String songTitle,
  required String artistId,
  required String artistName,
  required String albumId,
  required String albumTitle,
  required DateTime startedAt,
}) {
  return PlaybackSession(
    id: id,
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: '${albumId}_edition',
    songTitle: songTitle,
    artistName: artistName,
    albumTitle: albumTitle,
    albumEditionTitle: 'Standard',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 3)),
    listenedDuration: const Duration(minutes: 3),
    trackDuration: const Duration(minutes: 3),
    finalPosition: const Duration(minutes: 3),
    endReason: PlaybackSessionEndReason.completed,
    createdAt: startedAt,
    updatedAt: startedAt.add(const Duration(minutes: 3)),
  );
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
  });

  final List<LibraryTrack> tracks;
  final List<LibraryArtist> artists;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return tracks.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    for (final track in tracks) {
      if (track.songId == songId) {
        return track;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks
        .where((track) => track.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks
        .where((track) => track.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return albums.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    for (final album in albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return albums
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return artists;
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    for (final artist in artists) {
      if (artist.artistId == artistId) {
        return artist;
      }
    }

    return null;
  }
}

class _FakePlaybackSessionRepository implements PlaybackSessionRepository {
  _FakePlaybackSessionRepository([List<PlaybackSession> sessions = const []])
    : _sessions = List<PlaybackSession>.from(sessions);

  final List<PlaybackSession> _sessions;

  @override
  Future<void> create(PlaybackSession session) async {
    _sessions.add(session);
  }

  @override
  Future<void> save(PlaybackSession session) async {
    final index = _sessions.indexWhere(
      (candidate) => candidate.id == session.id,
    );

    if (index == -1) {
      _sessions.add(session);
    } else {
      _sessions[index] = session;
    }
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    for (final session in _sessions) {
      if (session.id == id) {
        return session;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();

    return _sessions
        .where((session) => idSet.contains(session.id))
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    return _sessions
        .where((session) => !session.isEnded)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return _sessions
        .where((session) {
          final startedAt = session.startedAt.toUtc();

          if (startedAtOrAfter != null &&
              startedAt.isBefore(startedAtOrAfter.toUtc())) {
            return false;
          }

          if (startedBefore != null &&
              !startedAt.isBefore(startedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final sessions = await getAll(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
    );

    return sessions.take(limit).toList(growable: false);
  }
}
