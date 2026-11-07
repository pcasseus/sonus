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

  test(
    'SN-45: version 38 keeps every classification and adds formats',
    () async {
      final file = path.join(root.path, 'v37.db');
      await _v31Fixture.copy(file);

      final at37 = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 37,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, oldVersion, newVersion) => DatabaseMigrations.migrate(
            db,
            oldVersion: oldVersion,
            newVersion: newVersion,
          ),
        ),
      );
      final albumId =
          (await at37.query(DatabaseTables.albums)).first['id']! as String;
      final classification = {
        'album_id': albumId,
        'kind': 'soundtrack',
        'authority': 'manual',
        'source_reference': null,
        'created_at': at,
        'updated_at': at,
      };
      await at37.insert(
        DatabaseTables.albumReleaseClassifications,
        classification,
      );
      await at37.close();

      final upgraded = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: file,
      );
      try {
        final db = await upgraded.database;
        expect(await db.query(DatabaseTables.albumReleaseClassifications), [
          {
            ...classification,
            'format': null,
            'format_authority': null,
            'format_source_reference': null,
            'live': null,
            'live_authority': null,
            'live_source_reference': null,
            'leaked': null,
          },
        ]);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await upgraded.close();
      }
    },
  );

  test('SN-49: version 40 keeps every kind and format and adds Live', () async {
    final file = path.join(root.path, 'v39.db');
    await _v31Fixture.copy(file);

    final at39 = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 39,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: (db, oldVersion, newVersion) => DatabaseMigrations.migrate(
          db,
          oldVersion: oldVersion,
          newVersion: newVersion,
        ),
      ),
    );
    final albumIds = [
      for (final row in await at39.query(DatabaseTables.albums))
        row['id']! as String,
    ];
    final rows = [
      {
        'album_id': albumIds[0],
        'kind': 'soundtrack',
        'authority': 'manual',
        'source_reference': null,
        'format': 'ep',
        'format_authority': 'external',
        'format_source_reference': 'musicbrainz:release-group:abc',
        'created_at': at,
        'updated_at': at,
      },
      {
        'album_id': albumIds[1],
        'kind': null,
        'authority': null,
        'source_reference': null,
        'format': 'single',
        'format_authority': 'manual',
        'format_source_reference': null,
        'created_at': at,
        'updated_at': at,
      },
    ];
    for (final row in rows) {
      await at39.insert(DatabaseTables.albumReleaseClassifications, row);
    }
    await at39.close();

    final upgraded = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: file,
    );
    try {
      final db = await upgraded.database;
      expect(
        await db.query(
          DatabaseTables.albumReleaseClassifications,
          orderBy: 'album_id',
        ),
        [
          for (final row in [
            ...rows,
          ]..sort((a, b) => a['album_id']!.compareTo(b['album_id']!)))
            {
              ...row,
              'live': null,
              'live_authority': null,
              'live_source_reference': null,
              'leaked': null,
            },
        ],
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await upgraded.close();
    }
  });

  group('SN-50: version 41 adds Leaked', () {
    /// The table exactly as version 40 created it, so the upgrade is proven
    /// against the real old shape rather than today's.
    const v40Table = '''
      CREATE TABLE album_release_classifications (
        album_id TEXT PRIMARY KEY NOT NULL
          REFERENCES albums(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        kind TEXT
          CHECK (
            kind IS NULL OR
            kind IN ('soundtrack', 'castRecording', 'compilation')
          ),
        authority TEXT
          CHECK (authority IS NULL OR authority IN ('external', 'manual')),
        source_reference TEXT,
        format TEXT
          CHECK (format IS NULL OR format IN ('single', 'ep', 'album')),
        format_authority TEXT
          CHECK (
            format_authority IS NULL OR
            format_authority IN ('external', 'manual')
          ),
        format_source_reference TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        live INTEGER CHECK (live IS NULL OR live IN (0, 1)),
        live_authority TEXT
          CHECK (
            live_authority IS NULL OR
            live_authority IN ('external', 'manual')
          ),
        live_source_reference TEXT,
        CHECK ((kind IS NULL) = (authority IS NULL)),
        CHECK ((format IS NULL) = (format_authority IS NULL)),
        CHECK ((live IS NULL) = (live_authority IS NULL)),
        CHECK (kind IS NOT NULL OR format IS NOT NULL OR live IS NOT NULL)
      )
    ''';

    /// A version 40 database holding [rows], built from its album ids.
    Future<String> v40With(
      List<Map<String, Object?>> Function(List<String> albumIds) rows,
    ) async {
      final file = path.join(root.path, 'v40.db');
      await _v31Fixture.copy(file);
      final at40 = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 40,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, oldVersion, newVersion) => DatabaseMigrations.migrate(
            db,
            oldVersion: oldVersion,
            newVersion: newVersion,
          ),
        ),
      );
      try {
        await at40.execute(
          'DROP TABLE ${DatabaseTables.albumReleaseClassifications}',
        );
        await at40.execute(v40Table);
        final albumIds = [
          for (final row in await at40.query(DatabaseTables.albums))
            row['id']! as String,
        ];
        for (final row in rows(albumIds)) {
          await at40.insert(DatabaseTables.albumReleaseClassifications, row);
        }
      } finally {
        await at40.close();
      }
      return file;
    }

    List<Map<String, Object?>> v40Rows(List<String> ids) => [
      {
        'album_id': ids[0],
        'kind': 'soundtrack',
        'authority': 'manual',
        'source_reference': null,
        'format': 'ep',
        'format_authority': 'external',
        'format_source_reference': 'musicbrainz:release-group:abc',
        'created_at': at,
        'updated_at': at,
        'live': 1,
        'live_authority': 'external',
        'live_source_reference': 'musicbrainz:release-group:abc',
      },
      {
        'album_id': ids[1],
        'kind': null,
        'authority': null,
        'source_reference': null,
        'format': null,
        'format_authority': null,
        'format_source_reference': null,
        'created_at': at,
        'updated_at': at,
        'live': 0,
        'live_authority': 'manual',
        'live_source_reference': null,
      },
    ];

    test('every version 40 row and column is kept; none is leaked', () async {
      final upgraded = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: await v40With(v40Rows),
      );
      final fresh = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path.join(root.path, 'fresh.db'),
      );
      try {
        final db = await upgraded.database;
        final albumIds = [
          for (final row in await db.query(DatabaseTables.albums))
            row['id']! as String,
        ];
        expect(
          (await db.rawQuery('PRAGMA user_version')).single['user_version'],
          42,
        );
        expect(
          await db.query(
            DatabaseTables.albumReleaseClassifications,
            orderBy: 'album_id',
          ),
          [
            for (final row in v40Rows(
              albumIds,
            )..sort((a, b) => '${a['album_id']}'.compareTo('${b['album_id']}')))
              {...row, 'leaked': null},
          ],
        );
        const columns =
            'PRAGMA table_info(${DatabaseTables.albumReleaseClassifications})';
        expect(
          await db.rawQuery(columns),
          await (await fresh.database).rawQuery(columns),
          reason: 'an upgraded table has the same columns as a fresh one',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await upgraded.close();
        await fresh.close();
      }
    });

    test('an empty version 40 table is replaced by the new one', () async {
      final upgraded = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: await v40With((_) => const []),
      );
      try {
        final db = await upgraded.database;
        final columns = await db.rawQuery(
          'PRAGMA table_info(${DatabaseTables.albumReleaseClassifications})',
        );
        expect(columns.map((c) => c['name']), contains('leaked'));
        expect(
          await db.query(DatabaseTables.albumReleaseClassifications),
          isEmpty,
        );
      } finally {
        await upgraded.close();
      }
    });
  });

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

    test('SN-45: formats are single, ep or album, with an authority', () async {
      await expectLater(
        classify({
          'album_id': 'album-a',
          'format': 'mixtape',
          'format_authority': 'manual',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        classify({'album_id': 'album-a', 'format': 'ep'}),
        throwsA(isA<DatabaseException>()),
        reason: 'a format needs an authority',
      );
      await expectLater(
        classify({'album_id': 'album-a'}),
        throwsA(isA<DatabaseException>()),
        reason: 'an empty row is never kept',
      );
      await classify({
        'album_id': 'album-a',
        'format': 'single',
        'format_authority': 'manual',
      });
    });

    test(
      'SN-49: Live is yes or no, with an authority, beside a kind',
      () async {
        await expectLater(
          classify({
            'album_id': 'album-a',
            'live': 2,
            'live_authority': 'manual',
          }),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          classify({'album_id': 'album-a', 'live': 1}),
          throwsA(isA<DatabaseException>()),
          reason: 'Live needs an authority',
        );
        // A live soundtrack: neither fact replaces the other.
        await classify({
          'album_id': 'album-a',
          'kind': 'soundtrack',
          'authority': 'manual',
          'live': 1,
          'live_authority': 'manual',
        });
      },
    );

    test('SN-50: Leaked is only ever 1, and may stand alone', () async {
      for (final value in [0, 2]) {
        await expectLater(
          classify({'album_id': 'album-a', 'leaked': value}),
          throwsA(isA<DatabaseException>()),
        );
      }
      await classify({'album_id': 'album-a', 'leaked': 1});
    });

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
