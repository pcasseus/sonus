import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_entity_listening_durations.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_distribution.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_enrichment_service.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  group('MonthlyListeningInsightsEnrichmentService', () {
    test('enriches ranked songs artists and albums', () async {
      final library = FakeLibraryQueryRepository(
        tracks: {
          'song-1': track(
            songId: 'song-1',
            title: 'Song One',
            artistId: 'artist-1',
            artistName: 'Artist One',
            albumId: 'album-1',
            albumTitle: 'Album One',
          ),
        },
        artists: {
          'artist-1': LibraryArtist(
            artistId: 'artist-1',
            name: 'Artist One',
            albumCount: 1,
            songCount: 1,
            dateAdded: DateTime(2026, 1, 1),
          ),
        },
        albums: {
          'album-1': LibraryAlbum(
            albumId: 'album-1',
            title: 'Album One',
            artistId: 'artist-1',
            artistName: 'Artist One',
            trackCount: 1,
            dateAdded: DateTime(2026, 1, 1),
          ),
        },
      );

      final service = MonthlyListeningInsightsEnrichmentService(
        library: library,
        playbackSessions: FakePlaybackSessionRepository(),
      );

      final result = await service.enrich(
        insights(
          songs: const [
            MonthlyRankedEntity(
              entityId: 'song-1',
              rank: 1,
              previousRank: 2,
              streams: 20,
              previousStreams: 10,
              lifetimeStreams: 100,
            ),
          ],
          artists: const [
            MonthlyRankedEntity(
              entityId: 'artist-1',
              rank: 1,
              previousRank: 1,
              streams: 20,
              previousStreams: 15,
              lifetimeStreams: 120,
            ),
          ],
          albums: const [
            MonthlyRankedEntity(
              entityId: 'album-1',
              rank: 1,
              previousRank: null,
              streams: 20,
              previousStreams: 0,
              lifetimeStreams: 20,
            ),
          ],
          durations: const MonthlyEntityListeningDurations(
            songs: {'song-1': Duration(minutes: 45)},
            artists: {'artist-1': Duration(hours: 2)},
            albums: {'album-1': Duration(hours: 1)},
          ),
        ),
      );

      expect(result.tracks, hasLength(1));
      expect(result.artists, hasLength(1));
      expect(result.albums, hasLength(1));

      final trackRow = result.tracks.single;

      expect(trackRow.track?.title, 'Song One');
      expect(trackRow.title, 'Song One');
      expect(trackRow.artistName, 'Artist One');
      expect(trackRow.hasCurrentLibraryEntity, isTrue);
      expect(trackRow.rank, 1);
      expect(trackRow.previousRank, 2);
      expect(trackRow.rankMovement, 1);
      expect(trackRow.streams, 20);
      expect(trackRow.previousStreams, 10);
      expect(trackRow.streamChange, 10);
      expect(trackRow.streamPercentChange, 1.0);
      expect(trackRow.lifetimeStreams, 100);
      expect(trackRow.listeningDuration, const Duration(minutes: 45));

      final artistRow = result.artists.single;

      expect(artistRow.artist?.name, 'Artist One');
      expect(artistRow.name, 'Artist One');
      expect(artistRow.hasCurrentLibraryEntity, isTrue);
      expect(artistRow.streams, 20);
      expect(artistRow.listeningDuration, const Duration(hours: 2));

      final albumRow = result.albums.single;

      expect(albumRow.album?.title, 'Album One');
      expect(albumRow.title, 'Album One');
      expect(albumRow.hasCurrentLibraryEntity, isTrue);
      expect(albumRow.isNew, isTrue);
      expect(albumRow.listeningDuration, const Duration(hours: 1));
    });

    test(
      'preserves missing library identities using playback snapshots',
      () async {
        final library = FakeLibraryQueryRepository(
          tracks: const {},
          artists: const {},
          albums: const {},
        );

        final service = MonthlyListeningInsightsEnrichmentService(
          library: library,
          playbackSessions: FakePlaybackSessionRepository(
            sessions: [
              playbackSession(
                id: 'session-history',
                songId: 'missing-song',
                artistId: 'missing-artist',
                albumId: 'missing-album',
                songTitle: 'Historical Song',
                artistName: 'Historical Artist',
                albumTitle: 'Historical Album',
                startedAt: DateTime.utc(2026, 10, 20, 12),
              ),
            ],
          ),
        );

        final source = insights(
          songs: const [
            MonthlyRankedEntity(
              entityId: 'missing-song',
              rank: 1,
              previousRank: null,
              streams: 10,
              previousStreams: 0,
              lifetimeStreams: 10,
            ),
          ],
          artists: const [
            MonthlyRankedEntity(
              entityId: 'missing-artist',
              rank: 1,
              previousRank: null,
              streams: 10,
              previousStreams: 0,
              lifetimeStreams: 10,
            ),
          ],
          albums: const [
            MonthlyRankedEntity(
              entityId: 'missing-album',
              rank: 1,
              previousRank: null,
              streams: 10,
              previousStreams: 0,
              lifetimeStreams: 10,
            ),
          ],
        );

        final result = await service.enrich(source);

        expect(result.tracks, hasLength(1));
        expect(result.artists, hasLength(1));
        expect(result.albums, hasLength(1));

        final trackRow = result.tracks.single;

        expect(trackRow.track, isNull);
        expect(trackRow.title, 'Historical Song');
        expect(trackRow.artistName, 'Historical Artist');
        expect(trackRow.albumTitle, 'Historical Album');
        expect(trackRow.hasCurrentLibraryEntity, isFalse);
        expect(trackRow.canPlay, isFalse);

        final artistRow = result.artists.single;

        expect(artistRow.artist, isNull);
        expect(artistRow.name, 'Historical Artist');
        expect(artistRow.hasCurrentLibraryEntity, isFalse);

        final albumRow = result.albums.single;

        expect(albumRow.album, isNull);
        expect(albumRow.title, 'Historical Album');
        expect(albumRow.artistName, 'Historical Artist');
        expect(albumRow.hasCurrentLibraryEntity, isFalse);
      },
    );

    test('preserves ranked rows when no metadata snapshot exists', () async {
      final service = MonthlyListeningInsightsEnrichmentService(
        library: FakeLibraryQueryRepository(
          tracks: const {},
          artists: const {},
          albums: const {},
        ),
        playbackSessions: FakePlaybackSessionRepository(),
      );

      final result = await service.enrich(
        insights(
          songs: const [
            MonthlyRankedEntity(
              entityId: 'unknown-song',
              rank: 1,
              previousRank: null,
              streams: 1,
              previousStreams: 0,
              lifetimeStreams: 1,
            ),
          ],
          artists: const [
            MonthlyRankedEntity(
              entityId: 'unknown-artist',
              rank: 1,
              previousRank: null,
              streams: 1,
              previousStreams: 0,
              lifetimeStreams: 1,
            ),
          ],
          albums: const [
            MonthlyRankedEntity(
              entityId: 'unknown-album',
              rank: 1,
              previousRank: null,
              streams: 1,
              previousStreams: 0,
              lifetimeStreams: 1,
            ),
          ],
        ),
      );

      expect(result.tracks.single.title, 'Unknown Track');
      expect(result.artists.single.name, 'Unknown Artist');
      expect(result.albums.single.title, 'Unknown Album');
    });
  });
}

MonthlyListeningInsights insights({
  List<MonthlyRankedEntity> songs = const [],
  List<MonthlyRankedEntity> artists = const [],
  List<MonthlyRankedEntity> albums = const [],
  MonthlyEntityListeningDurations durations =
      const MonthlyEntityListeningDurations(songs: {}, artists: {}, albums: {}),
}) {
  final selected = DateTime(2026, 10);
  final previous = DateTime(2026, 9);

  final currentWindow = AnalyticsTimeWindow(
    startUtc: selected.toUtc(),
    endUtc: DateTime(2026, 11).toUtc(),
  );

  final previousWindow = AnalyticsTimeWindow(
    startUtc: previous.toUtc(),
    endUtc: selected.toUtc(),
  );

  return MonthlyListeningInsights(
    selectedMonth: selected,
    previousMonth: previous,
    currentSummary: AnalyticsSummary(
      period: AnalyticsPeriod.month,
      window: currentWindow,
      qualifiedStreamCount: 20,
      qualifiedListeningDuration: const Duration(hours: 2),
      distinctSongCount: songs.length,
      distinctArtistCount: artists.length,
      distinctAlbumCount: albums.length,
      firstQualifiedAt: selected.toUtc(),
      lastQualifiedAt: selected.toUtc(),
    ),
    previousSummary: AnalyticsSummary(
      period: AnalyticsPeriod.month,
      window: previousWindow,
      qualifiedStreamCount: 10,
      qualifiedListeningDuration: const Duration(hours: 1),
      distinctSongCount: 1,
      distinctArtistCount: 1,
      distinctAlbumCount: 1,
      firstQualifiedAt: previous.toUtc(),
      lastQualifiedAt: previous.toUtc(),
    ),
    currentAudibleListeningDuration: const Duration(hours: 2),
    previousAudibleListeningDuration: const Duration(hours: 1),
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.month,
      window: currentWindow,
      sessionCount: 0,
      endedSessionCount: 0,
      completedSessionCount: 0,
      skippedSessionCount: 0,
      stoppedSessionCount: 0,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 0,
      averageQualifiedStreamsPerActiveDay: 0,
      averageQualifiedStreamsPerCalendarDay: 0,
      peakDay: null,
    ),
    distribution: const MonthlyListeningDistribution(days: [], hours: []),
    entityListeningDurations: durations,
    songs: songs,
    artists: artists,
    albums: albums,
  );
}

LibraryTrack track({
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
    albumEditionId: 'edition-$albumId',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 240,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    isAvailable: true,
  );
}

PlaybackSession playbackSession({
  required String id,
  required String songId,
  required String artistId,
  required String albumId,
  required String songTitle,
  required String artistName,
  required String albumTitle,
  required DateTime startedAt,
}) {
  return PlaybackSession(
    id: id,
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: 'edition-$albumId',
    songTitle: songTitle,
    artistName: artistName,
    albumTitle: albumTitle,
    albumEditionTitle: 'Standard',
    startedAt: startedAt,
    listenedDuration: const Duration(minutes: 3),
    trackDuration: const Duration(minutes: 4),
    finalPosition: const Duration(minutes: 3),
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}

class FakePlaybackSessionRepository implements PlaybackSessionRepository {
  FakePlaybackSessionRepository({this.sessions = const []});

  final List<PlaybackSession> sessions;

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return sessions
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
  Future<PlaybackSession?> getById(String id) async {
    for (final session in sessions) {
      if (session.id == id) {
        return session;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final requested = ids.toSet();

    return sessions
        .where((session) => requested.contains(session.id))
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getOpen() async => const [];

  @override
  Future<void> create(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    return const [];
  }
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  const FakeLibraryQueryRepository({
    required this.tracks,
    required this.artists,
    required this.albums,
  });

  final Map<String, LibraryTrack> tracks;
  final Map<String, LibraryArtist> artists;
  final Map<String, LibraryAlbum> albums;

  @override
  Future<LibraryTrack?> getTrackById(String songId) {
    throw StateError('Monthly enrichment must use getTracks().');
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) {
    throw StateError('Monthly enrichment must use getArtists().');
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) {
    throw StateError('Monthly enrichment must use getAlbums().');
  }

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks.values.toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return tracks.values.take(limit).toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks.values
        .where((track) => track.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks.values
        .where((track) => track.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums.values.toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return albums.values.take(limit).toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return albums.values
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return artists.values.toList(growable: false);
  }
}
