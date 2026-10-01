import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    db = await appDatabase.database;
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('fresh import writes primary and featured structured credits', () async {
    final importer = AtomicLibraryImporter(appDatabase: appDatabase);

    final result = await importer.import(
      candidate: _candidate('C:/music/test-song.mp3'),
      metadata: _metadata(featuredArtists: const ['Featured Artist']),
      now: DateTime.utc(2026, 10, 1, 12),
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final credits = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'song_id = ?',
      whereArgs: [result.songId],
      orderBy: 'position ASC',
    );

    expect(credits, hasLength(2));

    expect(credits[0]['role'], 'primary');
    expect(credits[0]['artist_id'], isNotNull);
    expect(credits[0]['credited_name'], 'Primary Artist');

    expect(credits[1]['role'], 'featured');
    expect(credits[1]['artist_id'], isNull);
    expect(credits[1]['credited_name'], 'Featured Artist');

    final song = await _songRow(db, result.songId!);

    expect(jsonDecode(song['featured_artists'] as String), ['Featured Artist']);
  });

  test(
    'fresh import canonical-deduplicates feature credits and legacy field',
    () async {
      final importer = AtomicLibraryImporter(appDatabase: appDatabase);

      final result = await importer.import(
        candidate: _candidate('C:/music/dedupe-song.mp3'),
        metadata: _metadata(
          featuredArtists: const [
            'Featured Artist',
            '  FEATURED ARTIST  ',
            'Primary Artist',
          ],
        ),
      );

      expect(result.status, ImportResultStatus.imported);

      final credits = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ?',
        whereArgs: [result.songId],
        orderBy: 'position ASC',
      );

      expect(credits, hasLength(2));
      expect(credits[0]['credited_name'], 'Primary Artist');
      expect(credits[1]['credited_name'], 'Featured Artist');

      final song = await _songRow(db, result.songId!);

      expect(jsonDecode(song['featured_artists'] as String), [
        'Featured Artist',
      ]);
    },
  );

  test(
    'fresh import links feature credit to unique existing Artist identity',
    () async {
      final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'existing_feature_artist',
        'name': 'Featured Artist',
        'canonical_name': TextNormalizer.canonicalize('Featured Artist'),
        'header_artwork_id': null,
        'top_artists_artwork_id': null,
        'is_blacklisted': 0,
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      final importer = AtomicLibraryImporter(appDatabase: appDatabase);

      final result = await importer.import(
        candidate: _candidate('C:/music/linked-feature.mp3'),
        metadata: _metadata(featuredArtists: const ['Featured Artist']),
      );

      expect(result.status, ImportResultStatus.imported);

      final credits = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ?',
        whereArgs: [result.songId],
        orderBy: 'position ASC',
      );

      expect(credits, hasLength(2));
      expect(credits[1]['artist_id'], 'existing_feature_artist');
      expect(credits[1]['role'], 'featured');
    },
  );

  test('structured credit failure rolls back entire fresh import', () async {
    await db.execute('''
        CREATE TRIGGER fail_import_credit_insert
        BEFORE INSERT ON ${DatabaseTables.songArtistCredits}
        BEGIN
          SELECT RAISE(ABORT, 'forced import credit failure');
        END
      ''');

    final importer = AtomicLibraryImporter(appDatabase: appDatabase);

    final result = await importer.import(
      candidate: _candidate('C:/music/failing-song.mp3'),
      metadata: _metadata(featuredArtists: const ['Featured Artist']),
    );

    expect(result.status, ImportResultStatus.failed);

    final songs = await db.query(DatabaseTables.songs);
    final bindings = await db.query(DatabaseTables.mediaFileBindings);
    final credits = await db.query(DatabaseTables.songArtistCredits);

    expect(songs, isEmpty);
    expect(bindings, isEmpty);
    expect(credits, isEmpty);
  });
}

ImportCandidate _candidate(String path) {
  return ImportCandidate(
    filePath: path,
    normalizedPath: TextNormalizer.normalizePath(path),
    discoveredAt: DateTime.utc(2026, 10, 1),
  );
}

AudioMetadata _metadata({List<String> featuredArtists = const []}) {
  return AudioMetadata(
    title: 'Test Song',
    artistName: 'Primary Artist',
    albumTitle: 'Test Album',
    durationSeconds: 180,
    trackNumber: 1,
    discNumber: 1,
    isSingle: false,
    featuredArtists: featuredArtists,
  );
}

Future<Map<String, Object?>> _songRow(Database db, String songId) async {
  final rows = await db.query(
    DatabaseTables.songs,
    where: 'id = ?',
    whereArgs: [songId],
  );

  return rows.single;
}
