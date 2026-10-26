// Artist Library & Soundtrack Collaborator Organization: acceptance
// fixtures. The library examples (Starstruck, The Cheetah Girls,
// Descendants) are controlled fixtures modelled on the reported cases, not
// the user's actual library metadata.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late LibraryOrganizationService service;
  late SqliteLibraryOrganizationRepository organization;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final query = SqliteLibraryQueryRepository(
      LibraryQueryDao(await appDatabase.database),
    );
    organization = SqliteLibraryOrganizationRepository(appDatabase);
    service = LibraryOrganizationService(
      library: query,
      collaborators: query,
      organization: organization,
      now: () => now,
    );
  });

  tearDown(() => appDatabase.close());

  var fileNumber = 0;

  Future<String> track({
    required String album,
    required String albumArtist,
    required String artist,
    required String title,
    List<String> featuring = const [],
    int seconds = 180,
  }) async {
    final path = 'Music/${fileNumber++}.mp3';
    final result = await AtomicLibraryImporter(appDatabase: appDatabase).import(
      candidate: ImportCandidate(
        filePath: path,
        normalizedPath: path.toLowerCase(),
        discoveredAt: now,
      ),
      metadata: AudioMetadata(
        title: title,
        artistName: artist,
        albumTitle: album,
        albumArtistName: albumArtist,
        durationSeconds: seconds,
        trackNumber: fileNumber,
        discNumber: 1,
        isSingle: false,
        featuredArtists: featuring,
      ),
      now: now,
    );
    return result.songId!;
  }

  Future<Map<String, String>> ids(String table, String column) async {
    final db = await appDatabase.database;
    return {
      for (final row in await db.query(table))
        row[column]! as String: row['id']! as String,
    };
  }

  Future<String> artistId(String name) async =>
      (await ids(DatabaseTables.artists, 'name'))[name]!;

  Future<String> albumId(String title) async =>
      (await ids(DatabaseTables.albums, 'title'))[title]!;

  Future<void> classify(String album, ReleaseKind kind) async {
    await organization.saveClassification(
      AlbumReleaseClassification(
        albumId: await albumId(album),
        kind: kind,
        authority: ReleaseClassificationAuthority.external,
        sourceReference: 'musicbrainz:release-group:test',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Starstruck: a soundtrack owned by "Starstruck Cast". Anna Margaret
  /// sings only on it; Sterling Knight also has an album of his own.
  Future<void> starstruck() async {
    for (final (artist, title) in [
      ('Sterling Knight', 'Hero'),
      ('Anna Margaret', 'New Boo'),
      ('Chelsea Staub', 'Something About The Sunshine'),
    ]) {
      await track(
        album: 'Starstruck',
        albumArtist: 'Starstruck Cast',
        artist: artist,
        title: title,
      );
    }
    await track(
      album: 'Solo',
      albumArtist: 'Sterling Knight',
      artist: 'Sterling Knight',
      title: 'Own Song',
    );
  }

  group('automatic grouping', () {
    test('a soundtrack-only performer is shown under the soundtrack', () async {
      await starstruck();
      await classify('Starstruck', ReleaseKind.soundtrack);

      final organizationNow = await service.load();
      final anna = await artistId('Anna Margaret');

      expect(organizationNow.isShownInLibrary(anna), isFalse);
      expect(
        organizationNow.placementOf(anna).projectAlbumId,
        await albumId('Starstruck'),
      );
      expect(
        organizationNow.placementOf(anna).reason,
        ArtistPlacementReason.automatic,
      );
    });

    test('an artist with an album of their own is never hidden', () async {
      await starstruck();
      await classify('Starstruck', ReleaseKind.soundtrack);

      final organizationNow = await service.load();

      expect(
        organizationNow.isShownInLibrary(await artistId('Sterling Knight')),
        isTrue,
      );
    });

    test('the project owner stays in the Library', () async {
      await starstruck();
      await classify('Starstruck', ReleaseKind.soundtrack);

      expect(
        (await service.load()).isShownInLibrary(
          await artistId('Starstruck Cast'),
        ),
        isTrue,
      );
    });

    test('an unclassified soundtrack groups its performers too: owning no '
        'release is what decides (SN-45)', () async {
      await starstruck();

      final organizationNow = await service.load();

      for (final name in ['Anna Margaret', 'Chelsea Staub']) {
        final id = await artistId(name);
        expect(organizationNow.isShownInLibrary(id), isFalse, reason: name);
        expect(
          organizationNow.placementOf(id).projectAlbumId,
          await albumId('Starstruck'),
        );
      }
      for (final name in ['Sterling Knight', 'Starstruck Cast']) {
        expect(
          organizationNow.isShownInLibrary(await artistId(name)),
          isTrue,
          reason: name,
        );
      }
    });

    test('a compilation performer without a release of its own is a '
        'contributor as well', () async {
      await starstruck();
      await classify('Starstruck', ReleaseKind.compilation);

      expect(
        (await service.load()).isShownInLibrary(
          await artistId('Anna Margaret'),
        ),
        isFalse,
      );
    });

    test('a contributor on two projects is listed under both, the one with '
        'more songs first', () async {
      for (final (album, count) in [('Descendants', 1), ('Descendants 2', 2)]) {
        for (var i = 0; i < count; i++) {
          await track(
            album: album,
            albumArtist: 'Descendants Cast',
            artist: 'Cameron Boyce',
            title: 'Song $i from $album',
          );
        }
      }

      final placement = (await service.load()).placementOf(
        await artistId('Cameron Boyce'),
      );
      expect(placement.isShown, isFalse);
      expect(placement.projectAlbumIds, [
        await albumId('Descendants 2'),
        await albumId('Descendants'),
      ]);
    });

    test('a cast recording groups its performers too', () async {
      await track(
        album: 'Descendants',
        albumArtist: 'Descendants Cast',
        artist: 'Sofia Carson',
        title: 'Evil Like Me',
      );
      await classify('Descendants', ReleaseKind.castRecording);

      expect(
        (await service.load()).isShownInLibrary(await artistId('Sofia Carson')),
        isFalse,
      );
    });
  });

  group('reversible manual choices', () {
    test('Assign to Project previews, applies and can be undone', () async {
      await track(
        album: 'The Cheetah Girls 2',
        albumArtist: 'The Cheetah Girls',
        artist: 'The Cheetah Girls',
        title: 'Strut',
      );
      await track(
        album: 'The Cheetah Girls 2',
        albumArtist: 'The Cheetah Girls',
        artist: 'Adrienne Bailon',
        title: 'Step Up',
      );
      final adrienne = await artistId('Adrienne Bailon');
      final project = await albumId('The Cheetah Girls 2');

      final preview = await service.previewAssignment(
        artistId: adrienne,
        albumId: project,
      );
      expect(preview.allowed, isTrue);
      expect(preview.songsOnProject, 1);
      expect(preview.songsElsewhere, 0);
      final automatic = await service.load();
      expect(automatic.isShownInLibrary(adrienne), isFalse);
      expect(
        automatic.placementOf(adrienne).reason,
        ArtistPlacementReason.automatic,
      );

      // Promoted on purpose, then placed under the project on purpose.
      await service.showAsOwnArtist(adrienne);
      expect((await service.load()).isShownInLibrary(adrienne), isTrue);

      await service.assignToProject(artistId: adrienne, albumId: project);
      final grouped = await service.load();
      expect(grouped.isShownInLibrary(adrienne), isFalse);
      expect(
        grouped.placementOf(adrienne).reason,
        ArtistPlacementReason.manual,
      );
      expect(grouped.groupedUnder(project), [adrienne]);

      await service.clearAssignment(adrienne);
      expect(
        (await service.load()).placementOf(adrienne).reason,
        ArtistPlacementReason.automatic,
      );
    });

    test('"Show as its own artist" overrides automatic grouping', () async {
      await starstruck();
      await classify('Starstruck', ReleaseKind.soundtrack);
      final anna = await artistId('Anna Margaret');

      await service.showAsOwnArtist(anna);

      final organizationNow = await service.load();
      expect(organizationNow.isShownInLibrary(anna), isTrue);
      expect(
        organizationNow.placementOf(anna).reason,
        ArtistPlacementReason.manual,
      );
    });

    test(
      'refuses to hide an independent catalog or an uncredited artist',
      () async {
        await starstruck();
        final project = await albumId('Starstruck');

        expect(
          (await service.assignToProject(
            artistId: await artistId('Sterling Knight'),
            albumId: project,
          )).refusal,
          ProjectAssignmentRefusal.ownsAlbums,
        );
        expect(
          (await service.assignToProject(
            artistId: await artistId('Starstruck Cast'),
            albumId: project,
          )).refusal,
          ProjectAssignmentRefusal.ownProject,
        );
        expect(
          (await service.assignToProject(
            artistId: await artistId('Anna Margaret'),
            albumId: await albumId('Solo'),
          )).refusal,
          ProjectAssignmentRefusal.notCredited,
        );
        expect(await organization.getAssignments(), isEmpty);
      },
    );

    test('credits are never changed by organization', () async {
      await starstruck();
      final db = await appDatabase.database;
      final before = await db.query(DatabaseTables.songArtistCredits);

      await service.assignToProject(
        artistId: await artistId('Anna Margaret'),
        albumId: await albumId('Starstruck'),
      );
      await classify('Starstruck', ReleaseKind.soundtrack);

      expect(await db.query(DatabaseTables.songArtistCredits), before);
    });
  });

  group('project collaborators', () {
    test('lists every credited role once per song across editions', () async {
      await track(
        album: 'Descendants',
        albumArtist: 'Descendants Cast',
        artist: 'Sofia Carson',
        title: 'Evil Like Me',
      );
      final shared = await track(
        album: 'Descendants',
        albumArtist: 'Descendants Cast',
        artist: 'Dove Cameron',
        title: 'If Only',
        featuring: const ['Sofia Carson'],
      );
      // The Deluxe shares the same recording (J8), so it adds no new song.
      final again = await track(
        album: 'Descendants (Deluxe)',
        albumArtist: 'Descendants Cast',
        artist: 'Dove Cameron',
        title: 'If Only',
        featuring: const ['Sofia Carson'],
      );
      expect(again, shared);

      final list = await service.collaboratorsOf(await albumId('Descendants'));

      // Sofia leads one song and features on another; the shared Deluxe
      // listing of "If Only" is not counted twice.
      final byName = {for (final c in list) c.artistName: c};
      expect(byName.keys, unorderedEquals(['Dove Cameron', 'Sofia Carson']));
      expect(byName['Dove Cameron']!.roles, {SongArtistCreditRole.primary});
      expect(byName['Dove Cameron']!.songCount, 1);
      expect(byName['Sofia Carson']!.roles, {
        SongArtistCreditRole.primary,
        SongArtistCreditRole.featured,
      });
      expect(byName['Sofia Carson']!.songCount, 2);
      // Lead role first, then more songs.
      expect(list.first.artistName, 'Sofia Carson');
    });

    test('a grouped artist stays searchable and keeps a profile', () async {
      await starstruck();
      await classify('Starstruck', ReleaseKind.soundtrack);
      final db = await appDatabase.database;
      final dao = LibraryQueryDao(db);

      final results = await dao.search('Anna');
      expect(results.artists.map((a) => a.name), contains('Anna Margaret'));
      expect(
        await dao.findProfileEligibleArtistById(
          await artistId('Anna Margaret'),
        ),
        isNotNull,
      );
    });

    test(
      'an album owner without main credits now has a profile (Artist-3)',
      () async {
        await starstruck();
        final db = await appDatabase.database;

        expect(
          await LibraryQueryDao(
            db,
          ).findProfileEligibleArtistById(await artistId('Starstruck Cast')),
          isNotNull,
        );
      },
    );
  });

  test('removing a manual choice returns the artist to the automatic '
      'rule', () async {
    await starstruck();
    final anna = await artistId('Anna Margaret');
    await service.showAsOwnArtist(anna);
    expect((await service.load()).isShownInLibrary(anna), isTrue);

    final db = await appDatabase.database;
    await db.delete(
      DatabaseTables.artistProjectAssignments,
      where: 'artist_id = ?',
      whereArgs: [anna],
    );

    expect((await service.load()).isShownInLibrary(anna), isFalse);
  });
}
