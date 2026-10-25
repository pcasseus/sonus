import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';

import '../../support/library_seed.dart';

/// A real database written by the SN-42 release (database version 31).
final _v31Fixture = File(
  path.join('test', 'fixtures', 'recovery', 'sonus_v31.db'),
);

void main() {
  sqfliteFfiInit();

  late Directory root;
  final at = DateTime.utc(2026, 10, 25).toIso8601String();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_organization_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<Map<String, String>> tableSql(DatabaseExecutor db) async => {
    for (final row in await db.rawQuery(
      'SELECT name, sql FROM sqlite_master '
      "WHERE name IN (?, ?, 'idx_artist_project_assignments_album_id')",
      [
        DatabaseTables.albumReleaseClassifications,
        DatabaseTables.artistProjectAssignments,
      ],
    ))
      row['name']! as String: (row['sql']! as String).replaceAll(
        RegExp(r'\s+'),
        ' ',
      ),
  };

  test(
    'upgrading from 33 creates the same tables as a fresh install',
    () async {
      final upgradedFile = path.join(root.path, 'upgraded.db');
      await _v31Fixture.copy(upgradedFile);

      // Bring the real v31 database to 33 first, then let the app open it.
      final at33 = await databaseFactoryFfi.openDatabase(
        upgradedFile,
        options: OpenDatabaseOptions(
          version: 33,
          onUpgrade: (db, oldVersion, newVersion) => DatabaseMigrations.migrate(
            db,
            oldVersion: oldVersion,
            newVersion: newVersion,
          ),
        ),
      );
      expect(await tableSql(at33), isEmpty);
      await at33.close();

      final upgraded = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: upgradedFile,
      );
      final fresh = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path.join(root.path, 'fresh.db'),
      );

      try {
        final freshSql = await tableSql(await fresh.database);
        expect(freshSql, hasLength(3));
        expect(await tableSql(await upgraded.database), freshSql);
      } finally {
        await upgraded.close();
        await fresh.close();
      }
    },
  );

  group('constraints', () {
    late AppDatabase app;
    late Database db;

    setUp(() async {
      app = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      db = await app.database;
      await seedConnectedLibrary(db, key: 'a');
    });

    tearDown(() => app.close());

    Future<void> assign(Map<String, Object?> values) => db.insert(
      DatabaseTables.artistProjectAssignments,
      {'created_at': at, 'updated_at': at, ...values},
    );

    Future<void> classify(Map<String, Object?> values) => db.insert(
      DatabaseTables.albumReleaseClassifications,
      {'created_at': at, 'updated_at': at, ...values},
    );

    test('a grouped artist needs a project', () async {
      await expectLater(
        assign({'artist_id': 'artist-a', 'mode': 'grouped'}),
        throwsA(isA<DatabaseException>()),
      );
      await assign({'artist_id': 'artist-a', 'mode': 'standalone'});
    });

    test('only known release kinds and authorities', () async {
      await expectLater(
        classify({
          'album_id': 'album-a',
          'kind': 'group',
          'authority': 'manual',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        classify({
          'album_id': 'album-a',
          'kind': 'soundtrack',
          'authority': 'guess',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'rows go with their album or artist, never block deleting them',
      () async {
        await classify({
          'album_id': 'album-a',
          'kind': 'soundtrack',
          'authority': 'external',
          'source_reference': 'musicbrainz:release-group:abc',
        });
        await assign({
          'artist_id': 'artist-a',
          'album_id': 'album-a',
          'mode': 'grouped',
        });

        // Child rows of the album first, as a real removal would.
        for (final table in [
          DatabaseTables.qualifiedPlays,
          DatabaseTables.chartEntries,
          DatabaseTables.playlistItems,
          DatabaseTables.playbackListeningSegments,
          DatabaseTables.playbackSessions,
          DatabaseTables.songArtistCredits,
          DatabaseTables.albumEditionTracks,
          DatabaseTables.trackLyrics,
          DatabaseTables.songs,
          DatabaseTables.albumEditions,
        ]) {
          await db.delete(table);
        }
        await db.delete(DatabaseTables.albums, where: "id = 'album-a'");

        expect(
          await db.query(DatabaseTables.albumReleaseClassifications),
          isEmpty,
        );
        expect(
          await db.query(DatabaseTables.artistProjectAssignments),
          isEmpty,
        );
      },
    );
  });
}
