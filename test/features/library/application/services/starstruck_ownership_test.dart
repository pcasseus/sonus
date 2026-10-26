// SN-45 Starstruck ownership (database level). The phone's Starstruck
// folder is a top-level folder whose eight files all carry the album-artist
// tag "Sterling Knight", with Stubby and Anna Margaret among the performers.
// The importer honours an album artist the files agree on, so Sterling
// Knight owns it after import; giving the soundtrack its own project is a
// manual, reversible choice that changes no song, credit or play.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../support/fixture_library.dart';

const List<FixtureTrack> _starstruck = [
  FixtureTrack(
    'Starstruck/1 Starstruck.mp3',
    title: 'Starstruck',
    artist: 'Sterling Knight',
    album: 'Starstruck',
    albumArtist: 'Sterling Knight',
    track: 1,
  ),
  FixtureTrack(
    'Starstruck/2 Hero.mp3',
    title: 'Hero',
    artist: 'Sterling Knight [Ft. Stubby]',
    album: 'Starstruck',
    albumArtist: 'Sterling Knight',
    track: 2,
  ),
  FixtureTrack(
    'Starstruck/3 Party Up.mp3',
    title: 'Party Up',
    artist: 'Stubby',
    album: 'Starstruck',
    albumArtist: 'Sterling Knight',
    track: 3,
  ),
  FixtureTrack(
    'Starstruck/4 Something About the Sunshine.mp3',
    title: 'Something About the Sunshine',
    artist: 'Anna Margaret [Ft. Sterling Knight]',
    album: 'Starstruck',
    albumArtist: 'Sterling Knight',
    track: 4,
  ),
  FixtureTrack(
    'Starstruck/5 Shades.mp3',
    title: 'Shades',
    artist: 'Sterling Knight',
    album: 'Starstruck',
    albumArtist: 'Sterling Knight',
    track: 5,
  ),
];

void main() {
  late AppDatabase database;
  late SqliteLibraryQueryRepository library;
  late LibraryOrganizationService organization;

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
    await importFixtureTracks(database, _starstruck);
  });

  tearDown(() => database.close());

  Future<List<Map<String, Object?>>> songRows() async =>
      (await database.database).query(
        DatabaseTables.songs,
        columns: ['id', 'title', 'artist_id', 'album_id', 'featured_artists'],
        orderBy: 'id',
      );

  test('the album artist every file agrees on owns the folder', () async {
    final albums = await library.getAlbums();
    expect(albums, hasLength(1));
    expect(albums.single.title, 'Starstruck');
    expect(albums.single.artistName, 'Sterling Knight');

    // The performers keep their own credits, featuring split out.
    final performers = {
      for (final t in await library.getTracks()) t.title: t.artistName,
    };
    expect(performers['Party Up'], 'Stubby');
    expect(performers['Something About the Sunshine'], 'Anna Margaret');
    expect(performers['Hero'], 'Sterling Knight');
  });

  test(
    'a new Starstruck project can own it; songs, credits and ids stay',
    () async {
      final before = await songRows();
      final album = (await library.getAlbums()).single;
      final sterling = await fixtureArtistId(database, 'Sterling Knight');
      final runner = SyncMutationTransactionRunner(appDatabase: database);

      final project = await ArtistCreationService(
        mutationRunner: runner,
      ).createOrReuse(userId: null, name: 'Starstruck');
      await AlbumProfileEditingService(mutationRunner: runner).updateProfile(
        userId: null,
        albumId: album.albumId,
        primaryEditionId: album.primaryEditionId!,
        title: album.title,
        editionTitle: album.primaryEditionTitle ?? 'Standard',
        editionType: AlbumEditionType.standard,
        releaseDate: null,
        genre: null,
        artistId: project.id,
      );

      expect(await songRows(), before, reason: 'no song row changes');
      expect((await library.getAlbums()).single.artistId, project.id);

      final org = await organization.load();
      expect(org.isShownInLibrary(project.id), isTrue);
      // Sterling Knight owns nothing else here, so he becomes a contributor
      // grouped under the soundtrack, credits intact.
      expect(org.isShownInLibrary(sterling), isFalse);
      expect(org.groupedUnder(album.albumId), contains(sterling));

      // Reversible: choosing him again restores his ownership.
      await AlbumProfileEditingService(mutationRunner: runner).updateProfile(
        userId: null,
        albumId: album.albumId,
        primaryEditionId: album.primaryEditionId!,
        title: album.title,
        editionTitle: album.primaryEditionTitle ?? 'Standard',
        editionType: AlbumEditionType.standard,
        releaseDate: null,
        genre: null,
        artistId: sterling,
      );
      expect((await organization.load()).isShownInLibrary(sterling), isTrue);
      expect(await songRows(), before);
    },
  );

  test('naming an existing artist reuses it instead of duplicating', () async {
    final runner = SyncMutationTransactionRunner(appDatabase: database);
    final reused = await ArtistCreationService(
      mutationRunner: runner,
    ).createOrReuse(userId: null, name: 'sterling knight');
    expect(reused.id, await fixtureArtistId(database, 'Sterling Knight'));
  });
}
