// SN-45 artist ownership acceptance (database level). Fictional folders,
// shaped like the cases seen on a real library, go through the real import
// pipeline into disposable databases. The rule under test: a release
// belongs to its owner; only artists that own a release are standalone;
// everyone else is a contributor shown inside their projects, with their
// credits intact and their plays counted once, for the project.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';

import '../../support/fixture_library.dart';

/// Victorious: one top-level soundtrack folder, 23 songs, many performers.
List<FixtureTrack> victorious() {
  final performers = [
    for (var i = 0; i < 13; i++) 'Victoria Justice',
    for (var i = 0; i < 3; i++) 'Leon Thomas III & Victoria Justice',
    'Victorious Cast',
    'Elizabeth Gillies & Ariana Grande',
    'Victoria Justice & Ariana Grande',
    'Miranda Cosgrove & Victoria Justice',
    'Victoria Justice [Ft. Leon Thomas III]',
    'Ariana Grande',
    'Ariana Grande',
  ];
  return [
    for (final (i, artist) in performers.indexed)
      FixtureTrack(
        'Victorious/${i + 1} Song ${i + 1}.mp3',
        title: 'Hollywood Arts Song ${i + 1}',
        artist: artist,
        album: 'Victorious',
        albumArtist: 'Victorious Cast',
        track: i + 1,
      ),
  ];
}

/// Descendants (under its own artist folder) with a soundtrack-only
/// contributor, Mitchell Hope; Dove Cameron also has a solo album.
List<FixtureTrack> descendants() => [
  for (final (i, artist) in [
    'Mitchell Hope',
    'Mitchell Hope',
    'Dove Cameron',
    'Dove Cameron',
    'Dove Cameron & Sofia Carson',
    'Descendants Cast',
    'Sofia Carson & Cameron Boyce & Booboo Stewart & Mitchell Hope',
  ].indexed)
    FixtureTrack(
      'Descendants/Descendants/${i + 1} Isle Song ${i + 1}.mp3',
      title: 'Isle Song ${i + 1}',
      artist: artist,
      album: 'Descendants',
      albumArtist: 'Descendants Cast',
      track: i + 1,
    ),
  for (final i in [1, 2])
    FixtureTrack(
      'Dove Cameron/Bloodshot/$i Solo $i.mp3',
      title: 'Solo $i',
      artist: 'Dove Cameron',
      album: 'Bloodshot',
      albumArtist: 'Dove Cameron',
      track: i,
    ),
];

/// Combined credits: explicit featuring forms, an "&" duet, and a real
/// group whose name contains an ampersand.
List<FixtureTrack> combined() => [
  const FixtureTrack(
    'Rags/1 Bracket.mp3',
    title: 'Bracket',
    artist: 'Keke Palmer [Ft. Max Schneider]',
    album: 'Rags',
    albumArtist: 'Rags Cast',
    track: 1,
  ),
  const FixtureTrack(
    'Rags/2 Direct.mp3',
    title: 'Direct',
    artist: 'Max Schneider feat. Keke Palmer',
    album: 'Rags',
    albumArtist: 'Rags Cast',
    track: 2,
  ),
  const FixtureTrack(
    'Rags/3 Duet.mp3',
    title: 'Duet',
    artist: 'Keke Palmer & Max Schneider',
    album: 'Rags',
    albumArtist: 'Rags Cast',
    track: 3,
  ),
  for (final i in [1, 2])
    FixtureTrack(
      'Echo & The Tides/First Light/$i Wave $i.mp3',
      title: 'Wave $i',
      artist: 'Echo & The Tides',
      album: 'First Light',
      albumArtist: 'Echo & The Tides',
      track: i,
    ),
];

class _Plays implements QualifiedPlayRepository {
  _Plays(this.plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => plays;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase database;
  late LibraryOrganizationService organization;
  late SqliteLibraryQueryRepository library;

  setUp(() async {
    database = fixtureDatabase();
    library = SqliteLibraryQueryRepository(
      LibraryQueryDao(await database.database),
    );
    organization = LibraryOrganizationService(
      library: library,
      collaborators: library,
      organization: SqliteLibraryOrganizationRepository(database),
    );
    await importFixtureTracks(database, [
      ...victorious(),
      ...descendants(),
      ...combined(),
    ]);
  });

  tearDown(() => database.close());

  Future<String> artist(String name) => fixtureArtistId(database, name);
  Future<String> album(String title) => fixtureAlbumId(database, title);

  /// Artists the Library lists: those with songs, filtered by identity.
  Future<List<String>> libraryArtists() async {
    final org = await organization.load();
    final tracks = await library.getTracks();
    final albums = {
      for (final a in await library.getAlbums()) a.albumId: a.artistId,
    };
    return [
      for (final a in await library.getArtists())
        if (tracks.any(
              (t) =>
                  t.artistId == a.artistId || albums[t.albumId] == a.artistId,
            ) &&
            org.isShownInLibrary(a.artistId))
          a.name,
    ]..sort();
  }

  test('the Library lists only artists that own releases', () async {
    expect(await libraryArtists(), [
      'Descendants',
      'Dove Cameron',
      'Echo & The Tides',
      'Rags Cast',
      'Victorious Cast',
    ]);
  });

  group('Scenario A: Victorious', () {
    test('one album holds all 23 songs, owned by the project', () async {
      final db = await database.database;
      final victoriousId = await album('Victorious');
      final rows = await db.query(
        DatabaseTables.songs,
        where: 'album_id = ?',
        whereArgs: [victoriousId],
      );
      expect(rows, hasLength(23));
      expect(
        (await db.query(
          DatabaseTables.albums,
          where: 'id = ?',
          whereArgs: [victoriousId],
        )).single['artist_id'],
        await artist('Victorious Cast'),
      );
      expect(
        await db.query(
          DatabaseTables.albums,
          where: 'title = ?',
          whereArgs: ['Victorious'],
        ),
        hasLength(1),
      );
    });

    test('performers keep accurate credits but get no catalog', () async {
      final org = await organization.load();
      final victoriousId = await album('Victorious');

      for (final name in [
        'Victoria Justice',
        'Ariana Grande',
        'Leon Thomas III & Victoria Justice',
      ]) {
        final id = await artist(name);
        expect(org.isShownInLibrary(id), isFalse, reason: name);
        expect(org.placementOf(id).projectAlbumId, victoriousId);
        expect(await library.getAlbumsByArtistId(id), isEmpty, reason: name);
      }

      final db = await database.database;
      final credited = {
        for (final row in await db.query(DatabaseTables.songArtistCredits))
          row['credited_name'],
      };
      // The duet credit is kept exactly as tagged; the explicit featuring
      // credit is split into a performer and a featured artist.
      expect(credited, contains('Leon Thomas III & Victoria Justice'));
      expect(credited, contains('Leon Thomas III'));
      expect(
        credited.where((name) => '$name'.contains('[Ft.')),
        isEmpty,
        reason: 'no "[Ft. …]" string becomes an artist or a credit',
      );
    });

    test('the contributor view lists Victoria Justice\'s songs there, '
        'and only there', () async {
      final victoriaId = await artist('Victoria Justice');
      final dao = LibraryQueryDao(await database.database);
      final appearances = ArtistProfileSections.appearances(
        tracks: [
          ...await dao.findMainTracksByArtistId(victoriaId),
          ...await dao.findCollaborationTracksByArtistId(victoriaId),
        ],
        albumsById: {for (final a in await library.getAlbums()) a.albumId: a},
      );

      expect(appearances, hasLength(1));
      expect(appearances.single.ownerName, 'Victorious Cast');
      expect(appearances.single.albums.single.title, 'Victorious');
      expect(appearances.single.tracks, hasLength(14));
    });
  });

  group('Scenario B: Descendants and Mitchell Hope', () {
    test('Mitchell Hope is not a Library artist and owns nothing', () async {
      final mitchell = await artist('Mitchell Hope');
      final org = await organization.load();

      expect(org.isShownInLibrary(mitchell), isFalse);
      expect(await library.getAlbumsByArtistId(mitchell), isEmpty);
      expect(org.groupedUnder(await album('Descendants')), contains(mitchell));
    });

    test(
      'opened from Descendants, his view lists his Descendants songs',
      () async {
        final mitchell = await artist('Mitchell Hope');
        final descendantsOwner = await artist('Descendants');
        final dao = LibraryQueryDao(await database.database);

        final appearances = ArtistProfileSections.appearances(
          tracks: await dao.findMainTracksByArtistId(mitchell),
          albumsById: {for (final a in await library.getAlbums()) a.albumId: a},
          projectArtistId: descendantsOwner,
        );

        expect(appearances.single.ownerArtistId, descendantsOwner);
        expect(
          [for (final t in appearances.single.tracks) t.title],
          ['Isle Song 1', 'Isle Song 2'],
        );
      },
    );

    test('Descendants lists him among its collaborators', () async {
      final credits = await organization.collaboratorsOf(
        await album('Descendants'),
      );
      expect(
        credits.map((c) => c.artistName),
        containsAll(['Mitchell Hope', 'Dove Cameron', 'Descendants Cast']),
      );
    });
  });

  group('Scenario C: an independent artist on a soundtrack', () {
    test(
      'Dove Cameron has a full profile; Descendants stays the project\'s',
      () async {
        final dove = await artist('Dove Cameron');
        final org = await organization.load();
        expect(org.isShownInLibrary(dove), isTrue);

        final owned = await library.getAlbumsByArtistId(dove);
        expect([for (final a in owned) a.title], ['Bloodshot']);

        final dao = LibraryQueryDao(await database.database);
        final collaborations = ArtistProfileSections.collaborations(
          mainTracks: await dao.findMainTracksByArtistId(dove),
          featuredTracks: await dao.findCollaborationTracksByArtistId(dove),
          ownedAlbumIds: {for (final a in owned) a.albumId},
          albumsById: {for (final a in await library.getAlbums()) a.albumId: a},
        );
        expect(
          {for (final t in collaborations) t.albumTitle},
          {'Descendants'},
          reason: 'soundtrack songs appear as collaborations, not her album',
        );
      },
    );

    test('no song or album is duplicated', () async {
      final db = await database.database;
      Future<int> count(String sql) async =>
          (await db.rawQuery(sql)).single.values.single! as int;

      expect(await count('SELECT COUNT(*) FROM songs'), 23 + 9 + 5);
      expect(
        await count(
          'SELECT COUNT(*) FROM (SELECT title FROM albums '
          'GROUP BY title HAVING COUNT(*) > 1)',
        ),
        0,
      );
    });
  });

  group('Scenario D: combined credits', () {
    test(
      'featuring forms split; "&" credits and group names stay whole',
      () async {
        final names = (await fixtureIds(
          database,
          DatabaseTables.artists,
          'name',
        )).keys.toSet();

        expect(names, containsAll(['Keke Palmer', 'Max Schneider']));
        expect(names.where((n) => n.contains('[Ft.')), isEmpty);
        expect(names.where((n) => n.contains(' feat. ')), isEmpty);
        expect(names, contains('Keke Palmer & Max Schneider'));
        expect(names, contains('Echo & The Tides'));

        final org = await organization.load();
        expect(org.isShownInLibrary(await artist('Echo & The Tides')), isTrue);
        expect(
          org.isShownInLibrary(await artist('Keke Palmer & Max Schneider')),
          isFalse,
          reason: 'a duet credit never becomes a catalog of its own',
        );
      },
    );
  });

  group('streams and charts', () {
    QualifiedPlay play(String id, LibraryTrack track) => QualifiedPlay(
      id: id,
      playbackSessionId: 'session-$id',
      songId: track.songId,
      artistId: track.artistId,
      albumId: track.albumId,
      albumEditionId: track.albumEditionId,
      qualifiedAt: DateTime.utc(2026, 10, 20, 12, int.parse(id)),
      listenedDuration: const Duration(seconds: 120),
      trackDuration: const Duration(seconds: 200),
      createdAt: DateTime.utc(2026, 10, 20),
    );

    test('every play counts once: contributors count for the project, '
        'standalone artists for themselves', () async {
      final tracks = await library.getTracks();
      LibraryTrack byTitle(String title) =>
          tracks.firstWhere((t) => t.title == title);

      final plays = [
        play('1', byTitle('Isle Song 1')), // Mitchell Hope
        play('2', byTitle('Isle Song 2')), // Mitchell Hope
        play('3', byTitle('Isle Song 3')), // Dove Cameron, on Descendants
        play('4', byTitle('Solo 1')), // Dove Cameron, her own album
        play('5', byTitle('Hollywood Arts Song 1')), // Victoria Justice
      ];

      final rankings = await AnalyticsEntityRankingService(
        qualifiedPlays: _Plays(plays),
        artistAttribution: OrganizationArtistAttribution(organization),
      ).load(period: AnalyticsPeriod.lifetime, referenceLocal: DateTime(2026));

      final byArtist = {
        for (final r in rankings.artists) r.entityId: r.qualifiedStreamCount,
      };
      expect(byArtist, {
        await artist('Descendants'): 2,
        await artist('Dove Cameron'): 2,
        await artist('Victorious Cast'): 1,
      });
      expect(
        byArtist.values.fold(0, (a, b) => a + b),
        plays.length,
        reason: 'no stream is counted twice',
      );
      // Songs and albums are untouched.
      expect(rankings.songs, hasLength(5));
      expect(
        {for (final r in rankings.albums) r.entityId: r.qualifiedStreamCount},
        {
          await album('Descendants'): 3,
          await album('Bloodshot'): 1,
          await album('Victorious'): 1,
        },
      );
    });
  });

  group('rescans and existing records', () {
    test(
      'importing the same folders again creates no new artist or album',
      () async {
        final db = await database.database;
        Future<List<Map<String, Object?>>> snapshot() =>
            db.rawQuery('SELECT id, name FROM artists ORDER BY id');
        final artistsBefore = await snapshot();
        final albumsBefore = await db.rawQuery('SELECT id FROM albums');
        final organizationBefore = (await organization.load()).placements.keys
            .toSet();

        await importFixtureTracks(database, [
          ...victorious(),
          ...descendants(),
          ...combined(),
        ], batchId: 'rescan');

        expect(await snapshot(), artistsBefore);
        expect(await db.rawQuery('SELECT id FROM albums'), albumsBefore);
        expect(
          (await organization.load()).placements.keys.toSet(),
          organizationBefore,
        );
      },
    );

    test('an artist row made by an earlier version stays, hidden, and its '
        'plays count for the project', () async {
      // Before SN-45, a bracketed credit on a project became its own
      // artist. Recreate such a row the way it was stored.
      final db = await database.database;
      final song = (await library.getTracks()).firstWhere(
        (t) => t.title == 'Bracket',
      );
      await db.insert(DatabaseTables.artists, {
        'id': 'legacy-artist',
        'name': 'Keke Palmer [Ft. Max Schneider]',
        'canonical_name': 'keke palmer [ft. max schneider]',
        'created_at': '2026-10-25T00:00:00.000Z',
        'updated_at': '2026-10-25T00:00:00.000Z',
      });
      await db.update(
        DatabaseTables.songs,
        {'artist_id': 'legacy-artist'},
        where: 'id = ?',
        whereArgs: [song.songId],
      );
      await db.update(
        DatabaseTables.songArtistCredits,
        {'artist_id': 'legacy-artist'},
        where: 'song_id = ? AND position = 0',
        whereArgs: [song.songId],
      );

      final org = await organization.load();
      expect(org.isShownInLibrary('legacy-artist'), isFalse);
      expect(
        org.attributedArtistId(
          artistId: 'legacy-artist',
          albumId: song.albumId,
        ),
        await artist('Rags Cast'),
      );
      expect(
        await db.query(
          DatabaseTables.artists,
          where: 'id = ?',
          whereArgs: ['legacy-artist'],
        ),
        hasLength(1),
        reason: 'nothing is deleted',
      );
    });
  });
}
