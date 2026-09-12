import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates artwork assets table', () async {
    final db = await appDatabase.database;

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
    ''');

    final names = tables.map((row) => row['name']).whereType<String>().toSet();

    expect(names, contains(DatabaseTables.artworkAssets));
  });

  test('artwork asset normalized path is unique', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 11).toIso8601String();

    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'artwork_1',
      'file_path': r'C:\Images\cover.jpg',
      'normalized_path': 'c:/images/cover.jpg',
      'created_at': now,
      'updated_at': now,
    });

    expect(
      () => db.insert(DatabaseTables.artworkAssets, {
        'id': 'artwork_2',
        'file_path': r'C:\Images\cover-copy.jpg',
        'normalized_path': 'c:/images/cover.jpg',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('artist artwork references are optional', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 11).toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_without_artwork',
      'name': 'Artist',
      'canonical_name': 'artist',
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query(
      DatabaseTables.artists,
      where: 'id = ?',
      whereArgs: ['artist_without_artwork'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['header_artwork_id'], isNull);
    expect(rows.single['top_artists_artwork_id'], isNull);
  });

  test('rejects unknown artwork reference', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 11).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.artists, {
        'id': 'artist_invalid_artwork',
        'name': 'Artist',
        'canonical_name': 'artist',
        'header_artwork_id': 'artwork_missing',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('deleting artwork clears artist artwork reference', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 11).toIso8601String();

    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'artwork_artist',
      'file_path': r'C:\Images\artist.jpg',
      'normalized_path': 'c:/images/artist.jpg',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_with_artwork',
      'name': 'Artist',
      'canonical_name': 'artist',
      'header_artwork_id': 'artwork_artist',
      'created_at': now,
      'updated_at': now,
    });

    await db.delete(
      DatabaseTables.artworkAssets,
      where: 'id = ?',
      whereArgs: ['artwork_artist'],
    );

    final rows = await db.query(
      DatabaseTables.artists,
      where: 'id = ?',
      whereArgs: ['artist_with_artwork'],
    );

    expect(rows.single['header_artwork_id'], isNull);
  });

  test('album edition and song expose artwork references', () async {
    final db = await appDatabase.database;

    final editionColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.albumEditions})',
    );

    final songColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.songs})',
    );

    final editionNames = editionColumns
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    final songNames = songColumns
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    expect(editionNames, contains('artwork_id'));
    expect(songNames, contains('artwork_id'));
  });
}
