import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';
import 'package:sonus_next/features/library/data/daos/song_artist_credit_dao.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';

void main() {
  late Database db;
  late SongArtistCreditDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    await LibrarySchema.create(db);

    dao = SongArtistCreditDao(db);

    final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_primary',
      'name': 'Madison Beer',
      'canonical_name': 'madison beer',
      'header_artwork_id': null,
      'top_artists_artwork_id': null,
      'is_blacklisted': 0,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_1',
      'artist_id': 'artist_primary',
      'title': 'Test Album',
      'canonical_title': 'test album',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_1',
      'album_id': 'album_1',
      'title': 'Test Album',
      'type': 'standard',
      'is_primary': 1,
      'release_date': null,
      'genre': null,
      'artwork_id': null,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.songs, {
      'id': 'song_1',
      'artist_id': 'artist_primary',
      'album_id': 'album_1',
      'album_edition_id': 'edition_1',
      'title': 'Test Song',
      'canonical_title': 'test song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'is_blocked': 0,
      'featured_artists': '[]',
      'artwork_id': null,
      'created_at': timestamp,
      'updated_at': timestamp,
    });
  });

  tearDown(() async {
    await db.close();
  });

  test('stores ordered linked and unlinked song credits', () async {
    final timestamp = DateTime.utc(2026, 10, 1);

    final primary = SongArtistCredit(
      id: 'credit_primary',
      songId: 'song_1',
      artistId: 'artist_primary',
      creditedName: 'Madison Beer',
      canonicalCreditedName: 'madison beer',
      role: SongArtistCreditRole.primary,
      position: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final feature = SongArtistCredit(
      id: 'credit_feature',
      songId: 'song_1',
      creditedName: 'Tate McRae',
      canonicalCreditedName: 'tate mcrae',
      role: SongArtistCreditRole.featured,
      position: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await dao.insert(primary);
    await dao.insert(feature);

    final credits = await dao.findBySongId('song_1');

    expect(credits, hasLength(2));
    expect(credits[0].role, SongArtistCreditRole.primary);
    expect(credits[0].artistId, 'artist_primary');
    expect(credits[1].role, SongArtistCreditRole.featured);
    expect(credits[1].artistId, isNull);
    expect(credits[1].creditedName, 'Tate McRae');
  });

  test('finds unlinked credits by canonical name', () async {
    final timestamp = DateTime.utc(2026, 10, 1);

    await dao.insert(
      SongArtistCredit(
        id: 'credit_feature',
        songId: 'song_1',
        creditedName: 'Tate McRae',
        canonicalCreditedName: 'tate mcrae',
        role: SongArtistCreditRole.featured,
        position: 1,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    final matches = await dao.findUnlinkedByCanonicalName('tate mcrae');

    expect(matches, hasLength(1));
    expect(matches.single.artistId, isNull);
  });
}
