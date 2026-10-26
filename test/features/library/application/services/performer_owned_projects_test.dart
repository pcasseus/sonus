// SN-45 Verify Library: a release owned by one of its performers while
// other artists lead songs on it is listed for review, never reassigned.
// Fictional folders go through the real import pipeline; the rule depends
// only on who leads each song, never on names.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/models/library_health_report.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/library_integrity_service.dart';
import 'package:sonus_next/features/library/data/daos/library_integrity_dao.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../support/fixture_library.dart';

FixtureTrack _track(
  String folder,
  int n,
  String artist, {
  required String album,
  String? albumArtist,
}) => FixtureTrack(
  '$folder/$n Song $n.mp3',
  title: '$album $n',
  artist: artist,
  album: album,
  albumArtist: albumArtist,
  track: n,
);

void main() {
  late AppDatabase database;

  setUp(() async {
    database = fixtureDatabase();
    await importFixtureTracks(database, [
      // A soundtrack whose files all name one performer as album artist.
      for (final (n, artist) in [
        (1, 'Nova Reyes'),
        (2, 'Nova Reyes'),
        (3, 'Nova Reyes [Ft. Kip Lane]'),
        (4, 'Kip Lane'),
        (5, 'Juno Park [Ft. Nova Reyes]'),
      ])
        _track(
          'Harbor Lights',
          n,
          artist,
          album: 'Harbor Lights',
          albumArtist: 'Nova Reyes',
        ),
      // An artist's own album with one guest-led song: not a project.
      for (final (n, artist) in [
        (1, 'Ola Brandt'),
        (2, 'Ola Brandt'),
        (3, 'Mira Dale & Ola Brandt'),
      ])
        _track(
          'Ola Brandt/Quiet Rooms',
          n,
          artist,
          album: 'Quiet Rooms',
          albumArtist: 'Ola Brandt',
        ),
      // A project owning itself, with one cast-credited song of its own:
      // it leads a minority of its songs, so it is not questioned.
      for (final (n, artist) in [
        (1, 'Summer Stage Cast'),
        (2, 'Ivy Cole'),
        (3, 'Ren Ito'),
        (4, 'Sol Vega'),
      ])
        _track(
          'Summer Stage',
          n,
          artist,
          album: 'Summer Stage',
          albumArtist: 'Summer Stage Cast',
        ),
      // A cast recording owned by its cast, not by a performer.
      for (final (n, artist) in [
        (1, 'Ivy Cole'),
        (2, 'Ren Ito'),
        (3, 'Sol Vega'),
      ])
        _track(
          'Night School',
          n,
          artist,
          album: 'Night School',
          albumArtist: 'Night School Cast',
        ),
    ]);
  });

  tearDown(() => database.close());

  Future<LibraryIntegrityService> integrity() async => LibraryIntegrityService(
    dao: LibraryIntegrityDao(await database.database),
    editions: AlbumEditionManagementService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    ),
    fileExists: (_) async => true,
  );

  HealthFinding finding(LibraryHealthReport report) => report.findings
      .firstWhere((f) => f.check == HealthCheck.performerOwnedProjects);

  Future<List<Map<String, Object?>>> owners() async => (await database.database)
      .rawQuery('SELECT id, artist_id FROM albums ORDER BY id');

  test('only the release led by several artists but owned by one of them '
      'is listed, as a warning', () async {
    final before = await owners();
    final result = finding(await (await integrity()).verify());

    expect(result.severity, HealthSeverity.warning);
    expect(
      [
        for (final r in result.performerOwnedProjects)
          (r.title, r.owner, r.otherLeads.join(', ')),
      ],
      [('Harbor Lights', 'Nova Reyes', 'Juno Park, Kip Lane')],
    );
    expect(await owners(), before, reason: 'nothing is reassigned');
  });

  test(
    'keeping the owner on purpose clears it, and changes nothing else',
    () async {
      final library = SqliteLibraryQueryRepository(
        LibraryQueryDao(await database.database),
      );
      final album = (await library.getAlbums()).firstWhere(
        (a) => a.title == 'Harbor Lights',
      );
      final before = await owners();
      await AlbumProfileEditingService(
        mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
      ).confirmOwner(albumId: album.albumId);

      expect(
        finding(await (await integrity()).verify()).severity,
        HealthSeverity.verified,
      );
      expect(await owners(), before);
    },
  );

  test('a new project as owner, or a confirmed owner, clears it', () async {
    final library = SqliteLibraryQueryRepository(
      LibraryQueryDao(await database.database),
    );
    final album = (await library.getAlbums()).firstWhere(
      (a) => a.title == 'Harbor Lights',
    );
    final runner = SyncMutationTransactionRunner(appDatabase: database);
    final editing = AlbumProfileEditingService(mutationRunner: runner);
    Future<void> own(String artistId) => editing.updateProfile(
      userId: null,
      albumId: album.albumId,
      primaryEditionId: album.primaryEditionId!,
      title: album.title,
      editionTitle: album.primaryEditionTitle ?? 'Standard',
      editionType: AlbumEditionType.standard,
      releaseDate: null,
      genre: null,
      artistId: artistId,
    );

    final project = await ArtistCreationService(
      mutationRunner: runner,
    ).createOrReuse(userId: null, name: 'Harbor Lights');
    await own(project.id);
    expect(
      finding(await (await integrity()).verify()).severity,
      HealthSeverity.verified,
    );

    // Choosing the performer again by hand is a confirmed choice: it is
    // not listed again.
    await own(album.artistId);
    expect(
      finding(await (await integrity()).verify()).severity,
      HealthSeverity.verified,
    );
  });
}
