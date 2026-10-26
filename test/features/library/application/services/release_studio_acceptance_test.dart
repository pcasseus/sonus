// SN-45 Release Studio acceptance (database level), through the same
// services the studio calls: rename a release, mark it a Single, set its
// date, create a Deluxe from Standard, give Deluxe a bonus track. Songs
// are never duplicated, and Standard is never changed by Deluxe edits.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../support/fixture_library.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = fixtureDatabase();
    await importFixtureTracks(database, [
      for (final i in [1, 2, 3])
        FixtureTrack(
          'Madison Beer/Locket/$i Song $i.mp3',
          title: 'Song $i',
          artist: 'Madison Beer',
          album: 'Locket',
          albumArtist: 'Madison Beer',
          track: i,
        ),
    ]);
  });

  tearDown(() => database.close());

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?>? args,
  ]) async => (await database.database).rawQuery(sql, args);

  test('rename, Single, date, Deluxe with a bonus track', () async {
    final runner = SyncMutationTransactionRunner(appDatabase: database);
    final library = SqliteLibraryQueryRepository(
      LibraryQueryDao(await database.database),
    );
    final albumId = await fixtureAlbumId(database, 'Locket');
    final album = (await library.getAlbumById(albumId))!;
    final standardId = album.primaryEditionId!;
    final songsBefore = await rows('SELECT id FROM songs ORDER BY id');

    // 1 and 3. Rename the release and set its date.
    await AlbumProfileEditingService(mutationRunner: runner).updateProfile(
      userId: null,
      albumId: albumId,
      primaryEditionId: standardId,
      title: 'Locket (Reissue)',
      editionTitle: album.primaryEditionTitle ?? 'Locket',
      editionType: album.primaryEditionType ?? AlbumEditionType.standard,
      releaseDate: DateTime.utc(2024, 6, 21),
      genre: null,
    );

    // 2. Mark it a Single.
    final organization = LibraryOrganizationService(
      library: library,
      collaborators: library,
      organization: SqliteLibraryOrganizationRepository(database),
    );
    await organization.setReleaseFormat(
      albumId: albumId,
      format: ReleaseFormat.single,
    );

    // 5. A Deluxe that starts with every Standard song.
    final editions = AlbumEditionManagementService(mutationRunner: runner);
    final deluxe = await editions.createEdition(
      albumId: albumId,
      title: 'Deluxe',
      type: AlbumEditionType.deluxe,
      includeSongsFrom: standardId,
    );

    // 6. Song 3 becomes Deluxe's bonus track: listed on Deluxe only.
    final song3 =
        (await rows(
              "SELECT id FROM songs WHERE title = 'Song 3'",
            )).single['id']!
            as String;
    await editions.removeTrack(editionId: standardId, songId: song3);

    final saved = (await library.getAlbumById(albumId))!;
    expect(saved.title, 'Locket (Reissue)');
    expect(saved.releaseDate, DateTime.utc(2024, 6, 21));
    expect((await organization.load()).formatOf(albumId), ReleaseFormat.single);

    Future<List<String>> listing(String editionId) async => [
      for (final row in await rows(
        'SELECT s.title FROM ${DatabaseTables.albumEditionTracks} t '
        'JOIN songs s ON s.id = t.song_id WHERE t.album_edition_id = ? '
        'ORDER BY t.sort_position',
        [editionId],
      ))
        row['title']! as String,
    ];
    expect(await listing(standardId), ['Song 1', 'Song 2']);
    expect(await listing(deluxe.id), ['Song 1', 'Song 2', 'Song 3']);

    // No song was copied or lost; the release's identity is unchanged.
    expect(await rows('SELECT id FROM songs ORDER BY id'), songsBefore);
    expect((await rows('SELECT COUNT(*) AS n FROM albums')).single['n'], 1);
  });
}
