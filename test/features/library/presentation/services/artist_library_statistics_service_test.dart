import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/song_artist_credit_link.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';

void main() {
  final clock = DateTime.utc(2026, 11, 4, 12);

  LibraryArtist artist(String id, {String? name, DateTime? added}) =>
      LibraryArtist(
        artistId: id,
        name: name ?? id,
        albumCount: 1,
        songCount: 1,
        dateAdded: added ?? DateTime.utc(2026, 1, 1),
      );

  group('sorting (D4)', () {
    ArtistLibraryStatistics stats(
      String id, {
      int? rank,
      Duration? listened,
      DateTime? added,
    }) => ArtistLibraryStatistics(
      artist: artist(id, added: added),
      rank: rank,
      qualifiedStreams: rank == null ? 0 : 100 - rank,
      listened: listened,
    );

    final snapshot = ArtistLibraryStatisticsSnapshot([
      stats('delta', rank: 2, listened: const Duration(minutes: 5)),
      stats('Alpha', listened: const Duration(minutes: 50)),
      stats('charlie', rank: 1, added: DateTime.utc(2026, 6, 1)),
      stats('bravo', listened: Duration.zero, added: DateTime.utc(2026, 9, 1)),
      stats('echo', rank: 3, listened: const Duration(minutes: 5)),
    ]);

    List<String> ids(ArtistStatisticsSort sort) => [
      for (final s in snapshot.sorted(sort)) s.artistId,
    ];

    test('by name, ignoring case', () {
      expect(ids(ArtistStatisticsSort.name), [
        'Alpha',
        'bravo',
        'charlie',
        'delta',
        'echo',
      ]);
    });

    test('by streams: ranked by rank, then unranked by name', () {
      expect(ids(ArtistStatisticsSort.qualifiedStreams), [
        'charlie',
        'delta',
        'echo',
        'Alpha',
        'bravo',
      ]);
    });

    test('by listening time: most first; none or unknown by name', () {
      expect(ids(ArtistStatisticsSort.listeningTime), [
        'Alpha',
        'delta',
        'echo',
        'bravo',
        'charlie',
      ]);
    });

    test('by recently added: newest first, then name', () {
      expect(ids(ArtistStatisticsSort.recentlyAdded), [
        'bravo',
        'charlie',
        'Alpha',
        'delta',
        'echo',
      ]);
    });

    test('a subset keeps the same order and skips unknown ids', () {
      expect(
        snapshot
            .sorted(
              ArtistStatisticsSort.qualifiedStreams,
              artistIds: ['bravo', 'missing', 'echo'],
            )
            .map((s) => s.artistId),
        ['echo', 'bravo'],
      );
    });

    test('unranked is reported as such', () {
      expect(snapshot['Alpha']!.isRanked, isFalse);
      expect(snapshot['Alpha']!.qualifiedStreams, 0);
      expect(snapshot['charlie']!.isRanked, isTrue);
    });
  });

  group('when sources are missing or failing', () {
    final library = _Library.generate(artists: 3, songsPerArtist: 2);

    test('without listening history: counts only, everyone unranked', () async {
      final snapshot = await ArtistLibraryStatisticsService(
        library: library,
        clock: () => clock,
      ).load();

      expect(snapshot.length, 3);
      for (final stats in snapshot.all) {
        expect(stats.isRanked, isFalse);
        expect(stats.topTrack, isNull);
        expect(stats.listened, isNull, reason: 'unknown, not zero');
        expect(stats.albumCount, 1);
      }
    });

    test('a failing ranking leaves the counts and listening time', () async {
      final history = _History.generate(library, playsPerSong: 1);
      final snapshot = await ArtistLibraryStatisticsService(
        library: library,
        qualifiedPlays: _FailingPlays(),
        playbackSessions: history.sessions,
        listeningSegments: history.segments,
        clock: () => clock,
      ).load();

      for (final stats in snapshot.all) {
        expect(stats.isRanked, isFalse);
        expect(stats.listened, greaterThan(Duration.zero));
      }
    });

    test('without the credit query: ranks, but no top tracks', () async {
      final plain = _PlainLibrary(library);
      final history = _History.generate(library, playsPerSong: 1);
      final snapshot = await ArtistLibraryStatisticsService(
        library: plain,
        qualifiedPlays: history.plays,
        clock: () => clock,
      ).load();

      for (final stats in snapshot.all) {
        expect(stats.isRanked, isTrue);
        expect(stats.topTrack, isNull);
      }
    });

    test('an empty library loads an empty snapshot', () async {
      final snapshot = await ArtistLibraryStatisticsService(
        library: _Library.generate(artists: 0, songsPerArtist: 0),
        clock: () => clock,
      ).load();

      expect(snapshot.length, 0);
    });
  });

  test(
    'a large library is read once per source, not once per artist',
    () async {
      // 1,000 artists, 5,000 songs, 20,000 qualified plays. The fakes throw on
      // any per-artist query, so reaching the end proves there were none.
      final library = _Library.generate(artists: 1000, songsPerArtist: 5);
      final history = _History.generate(library, playsPerSong: 4);
      final stopwatch = Stopwatch()..start();

      final snapshot = await ArtistLibraryStatisticsService(
        library: library,
        qualifiedPlays: history.plays,
        playbackSessions: history.sessions,
        listeningSegments: history.segments,
        clock: () => clock,
      ).load();
      stopwatch.stop();

      expect(snapshot.length, 1000);
      expect(library.calls, {
        'getArtists': 1,
        'getTracks': 1,
        'getAlbums': 1,
        'getSongArtistCreditLinks': 1,
      });
      expect(history.plays.calls, 1);
      expect(history.sessions.getAllCalls, 1);
      expect(history.sessions.getByIdCalls, 0, reason: 'no per-session lookup');
      expect(history.segments.calls, 1);

      // Every artist streamed 20 times (5 songs x 4), so all are ranked, in a
      // single sequence from 1, each with its own top track.
      final ranks = [for (final s in snapshot.all) s.rank!]..sort();
      expect(ranks, [for (var i = 1; i <= 1000; i++) i]);
      for (final stats in snapshot.all) {
        expect(stats.qualifiedStreams, 20);
        expect(stats.topTrack!.track.artistId, stats.artistId);
        expect(stats.listened, const Duration(minutes: 10));
      }

      // Generous: the pass is in memory; this guards against accidental
      // quadratic work, not machine speed.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    },
  );
}

class _Library
    implements LibraryQueryRepository, SongArtistCreditLinkQueryRepository {
  _Library(this.artists, this.albums, this.tracks, this.links);

  factory _Library.generate({
    required int artists,
    required int songsPerArtist,
  }) {
    final added = DateTime.utc(2026, 1, 1);
    final artistList = <LibraryArtist>[];
    final albums = <LibraryAlbum>[];
    final tracks = <LibraryTrack>[];
    final links = <SongArtistCreditLink>[];
    for (var a = 0; a < artists; a++) {
      final id = 'artist_$a';
      artistList.add(
        LibraryArtist(
          artistId: id,
          name: 'Artist $a',
          albumCount: 1,
          songCount: songsPerArtist,
          dateAdded: added.add(Duration(minutes: a)),
        ),
      );
      albums.add(
        LibraryAlbum(
          albumId: 'album_$a',
          title: 'Album $a',
          artistId: id,
          artistName: 'Artist $a',
          trackCount: songsPerArtist,
          dateAdded: added,
        ),
      );
      for (var s = 0; s < songsPerArtist; s++) {
        final songId = 'song_${a}_$s';
        tracks.add(
          LibraryTrack(
            songId: songId,
            title: 'Song $a $s',
            artistId: id,
            artistName: 'Artist $a',
            albumId: 'album_$a',
            albumTitle: 'Album $a',
            albumEditionId: 'edition_$a',
            albumEditionTitle: 'Album $a',
            albumEditionType: AlbumEditionType.standard,
            trackNumber: s + 1,
            durationSeconds: 180,
            isSingle: false,
            featuredArtists: const [],
            dateAdded: added,
            isAvailable: true,
          ),
        );
        links.add(
          SongArtistCreditLink(
            songId: songId,
            artistId: id,
            role: SongArtistCreditRole.primary,
          ),
        );
      }
    }
    return _Library(artistList, albums, tracks, links);
  }

  final List<LibraryArtist> artists;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;
  final List<SongArtistCreditLink> links;
  final calls = <String, int>{};

  void _count(String name) =>
      calls.update(name, (n) => n + 1, ifAbsent: () => 1);

  @override
  Future<List<LibraryArtist>> getArtists() async {
    _count('getArtists');
    return artists;
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    _count('getAlbums');
    return albums;
  }

  @override
  Future<List<LibraryTrack>> getTracks({Object? order}) async {
    _count('getTracks');
    return tracks;
  }

  @override
  Future<List<SongArtistCreditLink>> getSongArtistCreditLinks() async {
    _count('getSongArtistCreditLinks');
    return links;
  }

  // Any other (per-artist) query fails the test.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}

/// The same library without the batch credit query.
class _PlainLibrary implements LibraryQueryRepository {
  _PlainLibrary(this._inner);

  final _Library _inner;

  @override
  Future<List<LibraryArtist>> getArtists() => _inner.getArtists();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}

class _History {
  _History(this.plays, this.sessions, this.segments);

  factory _History.generate(_Library library, {required int playsPerSong}) {
    final plays = <QualifiedPlay>[];
    final sessions = <PlaybackSession>[];
    final segments = <PlaybackListeningSegment>[];
    var n = 0;
    for (final track in library.tracks) {
      for (var p = 0; p < playsPerSong; p++) {
        final started = DateTime.utc(2026, 3, 1).add(Duration(seconds: n * 10));
        const listened = Duration(seconds: 30);
        sessions.add(
          PlaybackSession(
            id: 'session_$n',
            songId: track.songId,
            artistId: track.artistId,
            albumId: track.albumId,
            albumEditionId: track.albumEditionId,
            songTitle: track.title,
            artistName: track.artistName,
            albumTitle: track.albumTitle,
            albumEditionTitle: track.albumEditionTitle,
            startedAt: started,
            endedAt: started.add(listened),
            listenedDuration: listened,
            trackDuration: const Duration(minutes: 3),
            finalPosition: listened,
            createdAt: started,
            updatedAt: started,
          ),
        );
        segments.add(
          PlaybackListeningSegment(
            id: 'segment_$n',
            playbackSessionId: 'session_$n',
            startedAt: started,
            endedAt: started.add(listened),
            listenedDuration: listened,
            createdAt: started,
            updatedAt: started,
          ),
        );
        plays.add(
          QualifiedPlay(
            id: 'play_$n',
            playbackSessionId: 'session_$n',
            songId: track.songId,
            artistId: track.artistId,
            albumId: track.albumId,
            albumEditionId: track.albumEditionId,
            qualifiedAt: started.add(listened),
            listenedDuration: listened,
            trackDuration: const Duration(minutes: 3),
            createdAt: started,
          ),
        );
        n++;
      }
    }
    return _History(_Plays(plays), _Sessions(sessions), _Segments(segments));
  }

  final _Plays plays;
  final _Sessions sessions;
  final _Segments segments;
}

class _Plays implements QualifiedPlayRepository {
  _Plays(this._plays);

  final List<QualifiedPlay> _plays;
  int calls = 0;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    calls++;
    return _plays;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}

class _FailingPlays implements QualifiedPlayRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('history unreadable');
}

class _Sessions implements PlaybackSessionRepository {
  _Sessions(List<PlaybackSession> sessions)
    : _byId = {for (final s in sessions) s.id: s};

  final Map<String, PlaybackSession> _byId;
  int getAllCalls = 0;
  int getByIdCalls = 0;

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    getAllCalls++;
    return [
      for (final s in _byId.values)
        if (startedBefore == null || s.startedAt.isBefore(startedBefore)) s,
    ];
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    getByIdCalls++;
    return _byId[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}

class _Segments implements PlaybackListeningSegmentRepository {
  _Segments(this._segments);

  final List<PlaybackListeningSegment> _segments;
  int calls = 0;

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    calls++;
    return _segments;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}
