import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/home/application/services/home_data_service.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  final referenceLocal = DateTime(2026, 9, 28, 12);

  test(
    'loads recently added library content and weekly analytics rankings',
    () async {
      final tracks = [
        _track(id: 'song_1', title: 'Song 1'),
        _track(id: 'song_2', title: 'Song 2'),
      ];

      final albums = [
        _album(id: 'album_1', title: 'Album 1'),
        _album(id: 'album_2', title: 'Album 2'),
      ];

      final artists = [
        _artist(id: 'artist_1', name: 'Artist 1'),
        _artist(id: 'artist_2', name: 'Artist 2'),
      ];

      final library = _FakeLibraryQueryRepository(
        tracks: tracks,
        albums: albums,
        artists: artists,
      );

      final qualifiedPlays = _FakeQualifiedPlayRepository([
        _play(
          id: 'play_1',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          qualifiedAt: DateTime(2026, 9, 27, 10),
        ),
        _play(
          id: 'play_2',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          qualifiedAt: DateTime(2026, 9, 27, 11),
        ),
        _play(
          id: 'play_3',
          songId: 'song_2',
          artistId: 'artist_2',
          albumId: 'album_2',
          qualifiedAt: DateTime(2026, 9, 27, 12),
        ),
      ]);

      final service = HomeDataService(
        library: library,
        analyticsRankings: AnalyticsEntityRankingService(
          qualifiedPlays: qualifiedPlays,
        ),
      );

      final snapshot = await service.load(referenceLocal: referenceLocal);

      expect(snapshot.recentlyAddedTracks.map((track) => track.songId), [
        'song_1',
        'song_2',
      ]);

      expect(snapshot.recentlyAddedAlbums.map((album) => album.albumId), [
        'album_1',
        'album_2',
      ]);

      expect(snapshot.weeklyPopularTracks.map((entry) => entry.track.songId), [
        'song_1',
        'song_2',
      ]);

      expect(snapshot.weeklyPopularTracks[0].rank, 1);
      expect(snapshot.weeklyPopularTracks[0].qualifiedStreamCount, 2);
      expect(snapshot.weeklyPopularTracks[1].rank, 2);
      expect(snapshot.weeklyPopularTracks[1].qualifiedStreamCount, 1);

      expect(snapshot.weeklyTopArtists.map((entry) => entry.artist.artistId), [
        'artist_1',
        'artist_2',
      ]);

      expect(snapshot.weeklyTopArtists[0].rank, 1);
      expect(snapshot.weeklyTopArtists[0].qualifiedStreamCount, 2);
    },
  );

  test(
    'skips blocked and missing tracks while keeping visible ranks dense',
    () async {
      final tracks = [
        _track(id: 'song_blocked', title: 'Blocked', blocked: true),
        _track(id: 'song_visible_1', title: 'Visible 1'),
        _track(id: 'song_visible_2', title: 'Visible 2'),
      ];

      final library = _FakeLibraryQueryRepository(
        tracks: tracks,
        artists: [_artist(id: 'artist_1', name: 'Artist 1')],
      );

      final qualifiedPlays = _FakeQualifiedPlayRepository([
        ..._plays(count: 5, songId: 'song_blocked', artistId: 'artist_1'),
        ..._plays(
          count: 4,
          songId: 'song_missing',
          artistId: 'artist_1',
          startingIndex: 10,
        ),
        ..._plays(
          count: 3,
          songId: 'song_visible_1',
          artistId: 'artist_1',
          startingIndex: 20,
        ),
        ..._plays(
          count: 2,
          songId: 'song_visible_2',
          artistId: 'artist_1',
          startingIndex: 30,
        ),
      ]);

      final service = HomeDataService(
        library: library,
        analyticsRankings: AnalyticsEntityRankingService(
          qualifiedPlays: qualifiedPlays,
        ),
      );

      final snapshot = await service.load(referenceLocal: referenceLocal);

      expect(snapshot.weeklyPopularTracks.map((entry) => entry.track.songId), [
        'song_visible_1',
        'song_visible_2',
      ]);

      expect(snapshot.weeklyPopularTracks.map((entry) => entry.rank), [1, 2]);

      expect(
        snapshot.weeklyPopularTracks.map((entry) => entry.qualifiedStreamCount),
        [3, 2],
      );
    },
  );

  test(
    'skips missing artists while keeping visible artist ranks dense',
    () async {
      final library = _FakeLibraryQueryRepository(
        tracks: [_track(id: 'song_1', title: 'Song 1')],
        artists: [_artist(id: 'artist_visible', name: 'Visible Artist')],
      );

      final qualifiedPlays = _FakeQualifiedPlayRepository([
        ..._plays(
          count: 4,
          songId: 'song_missing_artist',
          artistId: 'artist_missing',
        ),
        ..._plays(
          count: 3,
          songId: 'song_1',
          artistId: 'artist_visible',
          startingIndex: 10,
        ),
      ]);

      final service = HomeDataService(
        library: library,
        analyticsRankings: AnalyticsEntityRankingService(
          qualifiedPlays: qualifiedPlays,
        ),
      );

      final snapshot = await service.load(referenceLocal: referenceLocal);

      expect(snapshot.weeklyTopArtists, hasLength(1));
      expect(
        snapshot.weeklyTopArtists.single.artist.artistId,
        'artist_visible',
      );
      expect(snapshot.weeklyTopArtists.single.rank, 1);
      expect(snapshot.weeklyTopArtists.single.qualifiedStreamCount, 3);
    },
  );

  test('respects the configured section limit after filtering', () async {
    final tracks = List.generate(
      8,
      (index) =>
          _track(id: 'song_$index', title: 'Song $index', blocked: index == 0),
    );

    final artists = List.generate(
      8,
      (index) => _artist(id: 'artist_$index', name: 'Artist $index'),
    );

    final library = _FakeLibraryQueryRepository(
      tracks: tracks,
      albums: List.generate(
        8,
        (index) => _album(id: 'album_$index', title: 'Album $index'),
      ),
      artists: artists,
    );

    final qualifiedPlays = _FakeQualifiedPlayRepository(
      List.generate(
        8,
        (index) => _play(
          id: 'play_$index',
          songId: 'song_$index',
          artistId: 'artist_$index',
          albumId: 'album_$index',
          qualifiedAt: DateTime(2026, 9, 27, 8, index),
        ),
      ),
    );

    final service = HomeDataService(
      library: library,
      analyticsRankings: AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
      ),
      sectionLimit: 6,
    );

    final snapshot = await service.load(referenceLocal: referenceLocal);

    expect(snapshot.recentlyAddedTracks, hasLength(6));
    expect(snapshot.recentlyAddedAlbums, hasLength(6));
    expect(snapshot.weeklyPopularTracks, hasLength(6));
    expect(snapshot.weeklyTopArtists, hasLength(6));

    expect(
      snapshot.weeklyPopularTracks.any(
        (entry) => entry.track.songId == 'song_0',
      ),
      isFalse,
    );
  });

  test('rejects a non-positive section limit', () async {
    final service = HomeDataService(
      library: _FakeLibraryQueryRepository(),
      analyticsRankings: AnalyticsEntityRankingService(
        qualifiedPlays: _FakeQualifiedPlayRepository(),
      ),
      sectionLimit: 0,
    );

    await expectLater(
      service.load(referenceLocal: referenceLocal),
      throwsStateError,
    );
  });
}

LibraryTrack _track({
  required String id,
  required String title,
  bool blocked = false,
}) {
  return LibraryTrack(
    songId: id,
    title: title,
    artistId: 'artist_${id.replaceFirst('song_', '')}',
    artistName: 'Artist',
    albumId: 'album_${id.replaceFirst('song_', '')}',
    albumTitle: 'Album',
    albumEditionId: 'edition_${id.replaceFirst('song_', '')}',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 27),
    isAvailable: true,
    isSongBlocked: blocked,
    filePath: 'C:/Music/$id.mp3',
  );
}

LibraryAlbum _album({required String id, required String title}) {
  return LibraryAlbum(
    albumId: id,
    title: title,
    artistId: 'artist_$id',
    artistName: 'Artist',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 27),
  );
}

LibraryArtist _artist({required String id, required String name}) {
  return LibraryArtist(
    artistId: id,
    name: name,
    albumCount: 1,
    songCount: 1,
    dateAdded: DateTime.utc(2026, 9, 27),
  );
}

QualifiedPlay _play({
  required String id,
  required String songId,
  required String artistId,
  String albumId = 'album_1',
  required DateTime qualifiedAt,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session_$id',
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: 'edition_$albumId',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

List<QualifiedPlay> _plays({
  required int count,
  required String songId,
  required String artistId,
  int startingIndex = 0,
}) {
  return List.generate(
    count,
    (index) => _play(
      id: 'play_${startingIndex + index}',
      songId: songId,
      artistId: artistId,
      qualifiedAt: DateTime(2026, 9, 27, 8, startingIndex + index),
    ),
  );
}

class _FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  _FakeQualifiedPlayRepository([Iterable<QualifiedPlay> plays = const []])
    : _plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> _plays;

  @override
  Future<void> create(QualifiedPlay play) async {
    _plays.add(play);
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    final index = _plays.indexWhere((value) => value.id == play.id);

    if (index < 0) {
      throw StateError('Qualified play not found: ${play.id}');
    }

    _plays[index] = play;
  }

  @override
  Future<QualifiedPlay?> getById(String id) async {
    for (final play in _plays) {
      if (play.id == id) {
        return play;
      }
    }

    return null;
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    for (final play in _plays) {
      if (play.playbackSessionId == playbackSessionId) {
        return play;
      }
    }

    return null;
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async {
    final ids = playbackSessionIds.toSet();

    return _plays
        .where((play) => ids.contains(play.playbackSessionId))
        .toList(growable: false);
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return _plays
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
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({
    Iterable<LibraryTrack> tracks = const [],
    Iterable<LibraryAlbum> albums = const [],
    Iterable<LibraryArtist> artists = const [],
  }) : _tracks = List<LibraryTrack>.from(tracks),
       _albums = List<LibraryAlbum>.from(albums),
       _artists = List<LibraryArtist>.from(artists);

  final List<LibraryTrack> _tracks;
  final List<LibraryAlbum> _albums;
  final List<LibraryArtist> _artists;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return List.unmodifiable(_tracks);
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return _tracks.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    for (final track in _tracks) {
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
    return _tracks
        .where((track) => track.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return _tracks
        .where((track) => track.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return List.unmodifiable(_albums);
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return _albums.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    for (final album in _albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return _albums
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return List.unmodifiable(_artists);
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    for (final artist in _artists) {
      if (artist.artistId == artistId) {
        return artist;
      }
    }

    return null;
  }
}
