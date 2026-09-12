import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ArtworkAssetDao dao;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    dao = ArtworkAssetDao(await appDatabase.database);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  ArtworkAsset createArtwork({
    required String id,
    required String filePath,
    required String normalizedPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final timestamp = DateTime.utc(2026, 9, 11, 20);

    return ArtworkAsset(
      id: id,
      filePath: filePath,
      normalizedPath: normalizedPath,
      createdAt: createdAt ?? timestamp,
      updatedAt: updatedAt ?? timestamp,
    );
  }

  test('inserts and finds artwork asset by id', () async {
    final artwork = createArtwork(
      id: 'artwork_test',
      filePath: r'C:\Images\album.jpg',
      normalizedPath: 'c:/images/album.jpg',
    );

    await dao.insert(artwork);

    final result = await dao.findById(artwork.id);

    expect(result, artwork);
    expect(result?.filePath, r'C:\Images\album.jpg');
    expect(result?.normalizedPath, 'c:/images/album.jpg');
  });

  test('returns null for unknown artwork id', () async {
    final result = await dao.findById('artwork_missing');

    expect(result, isNull);
  });

  test('finds artwork asset by normalized path', () async {
    final artwork = createArtwork(
      id: 'artwork_path',
      filePath: r'C:\Images\Artist Header.jpg',
      normalizedPath: 'c:/images/artist header.jpg',
    );

    await dao.insert(artwork);

    final result = await dao.findByNormalizedPath(
      'c:/images/artist header.jpg',
    );

    expect(result, artwork);
  });

  test('returns null for unknown normalized path', () async {
    final result = await dao.findByNormalizedPath('c:/images/missing.jpg');

    expect(result, isNull);
  });

  test('rejects duplicate normalized paths', () async {
    await dao.insert(
      createArtwork(
        id: 'artwork_first',
        filePath: r'C:\Images\first.jpg',
        normalizedPath: 'c:/images/shared.jpg',
      ),
    );

    expect(
      () => dao.insert(
        createArtwork(
          id: 'artwork_second',
          filePath: r'C:\Images\second.jpg',
          normalizedPath: 'c:/images/shared.jpg',
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('updates existing artwork asset', () async {
    final original = createArtwork(
      id: 'artwork_update',
      filePath: r'C:\Images\old.jpg',
      normalizedPath: 'c:/images/old.jpg',
    );

    await dao.insert(original);

    final updated = original.copyWith(
      filePath: r'C:\Images\new.jpg',
      normalizedPath: 'c:/images/new.jpg',
      updatedAt: DateTime.utc(2026, 9, 11, 21),
    );

    await dao.update(updated);

    final result = await dao.findById(original.id);

    expect(result?.filePath, r'C:\Images\new.jpg');
    expect(result?.normalizedPath, 'c:/images/new.jpg');
    expect(result?.updatedAt, DateTime.utc(2026, 9, 11, 21));
  });

  test('updating unknown artwork throws', () async {
    final artwork = createArtwork(
      id: 'artwork_missing',
      filePath: r'C:\Images\missing.jpg',
      normalizedPath: 'c:/images/missing.jpg',
    );

    expect(() => dao.update(artwork), throwsA(isA<StateError>()));
  });

  test('findAll returns newest artwork first', () async {
    await dao.insert(
      createArtwork(
        id: 'artwork_old',
        filePath: r'C:\Images\old.jpg',
        normalizedPath: 'c:/images/old.jpg',
        createdAt: DateTime.utc(2026, 9, 10),
      ),
    );

    await dao.insert(
      createArtwork(
        id: 'artwork_new',
        filePath: r'C:\Images\new.jpg',
        normalizedPath: 'c:/images/new.jpg',
        createdAt: DateTime.utc(2026, 9, 11),
      ),
    );

    final results = await dao.findAll();

    expect(results.map((artwork) => artwork.id).toList(), [
      'artwork_new',
      'artwork_old',
    ]);
  });
}
