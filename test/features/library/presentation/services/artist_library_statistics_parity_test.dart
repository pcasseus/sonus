// UI redesign D1: the batch artist statistics must say exactly what each
// Artist Profile says. Both run here on one real SQLite library with real
// listening history, and every value is compared artist by artist.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_listening_segment_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late SqliteLibraryQueryRepository library;
  late SqliteQualifiedPlayRepository plays;
  late SqlitePlaybackSessionRepository sessions;
  late SqlitePlaybackListeningSegmentRepository segments;
  late LibraryOrganizationService organization;
  final clock = DateTime.utc(2026, 11, 4, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    library = SqliteLibraryQueryRepository(LibraryQueryDao(db));
    plays = SqliteQualifiedPlayRepository(QualifiedPlayDao(db));
    sessions = SqlitePlaybackSessionRepository(PlaybackSessionDao(db));
    segments = SqlitePlaybackListeningSegmentRepository(
      PlaybackListeningSegmentDao(db),
    );
    organization = LibraryOrganizationService(
      library: library,
      collaborators: library,
      organization: SqliteLibraryOrganizationRepository(appDatabase),
    );
    await _seed(db, appDatabase, sessions, segments, plays);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  ArtistLibraryStatisticsService service() => ArtistLibraryStatisticsService(
    library: library,
    qualifiedPlays: plays,
    playbackSessions: sessions,
    listeningSegments: segments,
    organization: organization,
    clock: () => clock,
  );

  Future<ArtistProfileController> profile(String artistId) async {
    final controller = ArtistProfileController(
      repository: library,
      artistId: artistId,
      qualifiedPlays: plays,
      playbackSessions: sessions,
      listeningSegments: segments,
      organization: organization,
      clock: () => clock,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test('the scenario covers what it claims to', () async {
    final loaded = await organization.load();
    expect(
      loaded.isShownInLibrary('cast1'),
      isFalse,
      reason: 'a soundtrack performer is a grouped contributor',
    );
    expect(loaded.isShownInLibrary('ost'), isTrue);
    expect(
      loaded.isShownInLibrary('feat'),
      isFalse,
      reason: 'an artist with only a featured credit is a contributor',
    );
  });

  for (final artistId in const [
    'ada',
    'duo',
    'ben',
    'ost',
    'cast1',
    'cast2',
    'zed',
    'blk',
  ]) {
    test('$artistId: counts, rank, streams, listening and top track match '
        'the Artist Profile', () async {
      final snapshot = await service().load();
      final stats = snapshot[artistId]!;
      final page = await profile(artistId);

      expect(page.isNotFound, isFalse, reason: 'the profile can show it');
      expect(stats.albumCount, page.artist!.albumCount);
      expect(stats.songCount, page.artist!.songCount);

      final standing = page.standing;
      expect(stats.rank, standing?.rank);
      expect(stats.qualifiedStreams, standing?.streamCount ?? 0);
      expect(stats.isRanked, standing != null);
      if (standing != null) {
        // The profile has no listening time for an artist it never heard.
        expect(stats.listened, standing.listened ?? Duration.zero);
      }

      final top = page.topTracks.isEmpty ? null : page.topTracks.first;
      expect(stats.topTrack?.track.songId, top?.track.songId);
      expect(stats.topTrack?.streamCount, top?.streamCount);
      expect(stats.topTrack?.track.artworkPath, top?.track.artworkPath);
    });
  }

  test('the expected values, spelled out', () async {
    final snapshot = await service().load();
    ArtistLibraryStatistics of(String id) => snapshot[id]!;

    // Ranked by attributed qualified streams: blk 8 (blocked plays still
    // count), ada 8, ben 5, ost 3 (its two performers' plays), duo 1.
    expect(
      snapshot
          .sorted(ArtistStatisticsSort.qualifiedStreams)
          .map((s) => (s.artistId, s.rank, s.qualifiedStreams)),
      [
        ('blk', 1, 8),
        ('ada', 2, 8),
        ('ben', 3, 5),
        ('ost', 4, 3),
        ('duo', 5, 1),
        ('cast1', null, 0),
        ('cast2', null, 0),
        ('feat', null, 0),
        ('zed', null, 0),
      ],
    );

    expect(of('ada').topTrack!.track.songId, 'ada_2', reason: 'its own duet');
    expect(of('duo').topTrack!.track.songId, 'ada_2', reason: 'co-primary');
    expect(of('ben').topTrack!.track.songId, 'ben_2');
    expect(of('ost').topTrack!.track.songId, 'ost_1', reason: 'its cast');
    expect(of('cast1').topTrack!.track.songId, 'ost_1');
    expect(of('blk').topTrack!.track.songId, 'blk_2', reason: 'not blocked');
    // A feature-only artist owns nothing, so it is a contributor, whose
    // catalogue is its appearances, features included (as the profile's
    // appearances); the Library does not list it.
    expect(of('feat').topTrack!.track.songId, 'ben_1');

    // Listened without a qualified stream: time, but unranked.
    expect(of('zed').isRanked, isFalse);
    expect(of('zed').listened, const Duration(seconds: 20));
    expect(of('feat').listened, Duration.zero);
  });

  test('reads every source once, whatever the number of artists', () async {
    final first = await service().load();
    final again = await service().load();

    expect(first.length, again.length);
    for (final stats in first.all) {
      expect(again[stats.artistId]!.rank, stats.rank);
      expect(again[stats.artistId]!.listened, stats.listened);
    }
  });
}

final _timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

Future<void> _seed(
  Database db,
  AppDatabase appDatabase,
  SqlitePlaybackSessionRepository sessions,
  SqlitePlaybackListeningSegmentRepository segments,
  SqliteQualifiedPlayRepository plays,
) async {
  for (final (id, name) in const [
    ('ada', 'Ada'),
    ('duo', 'Duo'),
    ('ben', 'Ben'),
    ('feat', 'Feat'),
    ('ost', 'The Soundtrack'),
    ('cast1', 'Cast One'),
    ('cast2', 'Cast Two'),
    ('zed', 'Zed'),
    ('blk', 'Blk'),
  ]) {
    await db.insert(DatabaseTables.artists, {
      'id': id,
      'name': name,
      'canonical_name': name.toLowerCase(),
      'header_artwork_id': null,
      'top_artists_artwork_id': null,
      'is_blacklisted': 0,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }

  for (final (album, owner) in const [
    ('album_ada', 'ada'),
    ('album_duo', 'duo'),
    ('album_ben', 'ben'),
    ('album_ost', 'ost'),
    ('album_zed', 'zed'),
    ('album_blk', 'blk'),
  ]) {
    await db.insert(DatabaseTables.albums, {
      'id': album,
      'artist_id': owner,
      'title': '$album title',
      'canonical_title': '$album title',
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
    await db.insert(DatabaseTables.albumEditions, {
      'id': '${album}_ed',
      'album_id': album,
      'title': '$album title',
      'type': 'standard',
      'is_primary': 1,
      'release_date': null,
      'genre': null,
      'artwork_id': null,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }

  var position = 0;
  Future<void> song(
    String id,
    String artistId,
    String album, {
    List<(String, String)> credits = const [],
    bool blocked = false,
  }) async {
    await db.insert(DatabaseTables.songs, {
      'id': id,
      'artist_id': artistId,
      'album_id': album,
      'album_edition_id': '${album}_ed',
      'title': 'Song $id',
      'canonical_title': 'song $id',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'is_blocked': blocked ? 1 : 0,
      'featured_artists': '[]',
      'artwork_id': null,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
    await db.insert(DatabaseTables.albumEditionTracks, {
      'album_edition_id': '${album}_ed',
      'song_id': id,
      'disc_number': 1,
      'track_number': 1,
      'sort_position': 0,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
    for (final (index, (creditArtist, role)) in [
      (artistId, 'primary'),
      ...credits,
    ].indexed) {
      await db.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit_${position++}',
        'song_id': id,
        'artist_id': creditArtist,
        'credited_name': creditArtist,
        'canonical_credited_name': creditArtist,
        'role': role,
        'position': index,
        'created_at': _timestamp,
        'updated_at': _timestamp,
      });
    }
  }

  await song('ada_1', 'ada', 'album_ada');
  await song('ada_2', 'ada', 'album_ada', credits: [('duo', 'coPrimary')]);
  await song('duo_1', 'duo', 'album_duo');
  await song('ben_1', 'ben', 'album_ben', credits: [('feat', 'featured')]);
  await song('ben_2', 'ben', 'album_ben', credits: [('ada', 'featured')]);
  await song('ost_1', 'cast1', 'album_ost');
  await song('ost_2', 'cast2', 'album_ost');
  await song('zed_1', 'zed', 'album_zed');
  await song('blk_1', 'blk', 'album_blk', blocked: true);
  await song('blk_2', 'blk', 'album_blk');

  await SqliteLibraryOrganizationRepository(appDatabase).saveClassification(
    AlbumReleaseClassification(
      albumId: 'album_ost',
      kind: ReleaseKind.soundtrack,
      authority: ReleaseClassificationAuthority.manual,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    ),
  );

  var playNumber = 0;
  Future<void> listen(
    String songId,
    String artistId,
    String album, {
    int times = 1,
    bool qualified = true,
    Duration listened = const Duration(seconds: 40),
  }) async {
    for (var i = 0; i < times; i++) {
      final n = playNumber++;
      final started = DateTime.utc(2026, 10, 2).add(Duration(minutes: n * 5));
      final session = PlaybackSession(
        id: 'session_$n',
        songId: songId,
        artistId: artistId,
        albumId: album,
        albumEditionId: '${album}_ed',
        songTitle: 'Song $songId',
        artistName: artistId,
        albumTitle: '$album title',
        albumEditionTitle: '$album title',
        startedAt: started,
        endedAt: started.add(listened),
        listenedDuration: listened,
        trackDuration: const Duration(minutes: 3),
        finalPosition: listened,
        createdAt: started,
        updatedAt: started,
      );
      await sessions.create(session);
      await segments.create(
        PlaybackListeningSegment(
          id: 'segment_$n',
          playbackSessionId: session.id,
          startedAt: started,
          endedAt: started.add(listened),
          listenedDuration: listened,
          createdAt: started,
          updatedAt: started,
        ),
      );
      if (qualified) {
        await plays.create(
          QualifiedPlay(
            id: 'play_$n',
            playbackSessionId: session.id,
            songId: songId,
            artistId: artistId,
            albumId: album,
            albumEditionId: '${album}_ed',
            qualifiedAt: started.add(listened),
            listenedDuration: listened,
            trackDuration: const Duration(minutes: 3),
            createdAt: started,
          ),
        );
      }
    }
  }

  await listen('ada_1', 'ada', 'album_ada', times: 3);
  await listen('ada_2', 'ada', 'album_ada', times: 5);
  await listen('duo_1', 'duo', 'album_duo');
  await listen('ben_1', 'ben', 'album_ben');
  await listen('ben_2', 'ben', 'album_ben', times: 4);
  await listen('ost_1', 'cast1', 'album_ost', times: 2);
  await listen('ost_2', 'cast2', 'album_ost');
  await listen('blk_1', 'blk', 'album_blk', times: 6);
  await listen('blk_2', 'blk', 'album_blk', times: 2);
  // Heard, but never long enough to qualify.
  await listen(
    'zed_1',
    'zed',
    'album_zed',
    qualified: false,
    listened: const Duration(seconds: 20),
  );
}
