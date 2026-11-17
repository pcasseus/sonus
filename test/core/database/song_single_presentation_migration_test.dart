// App Update 1.3, REF-1.3-04: version 47 adds one table of Singles' own
// release dates and covers; nothing else, and no existing row changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_single_presentation_repository.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';
import 'package:sonus_next/features/recovery/application/models/backup_compatibility.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

import '../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  final opened = <AppDatabase>[];
  setUp(() async => dir = await Directory.systemTemp.createTemp('sonus_v47_'));
  tearDown(() async {
    for (final database in opened) {
      await database.close();
    }
    opened.clear();
    await dir.delete(recursive: true);
  });

  const table = DatabaseTables.songSinglePresentations;
  final at = DateTime.utc(2026, 11, 15);

  Future<AppDatabase> fresh(String name) async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(dir.path, name),
    );
    await database.database;
    opened.add(database);
    return database;
  }

  /// A version 46 database: today's schema without the new table, holding
  /// a real library.
  Future<Database> version46(String name) async {
    final database = await fresh(name);
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a', artworkPath: '/art/a.png');
    await seedConnectedLibrary(db, key: 'b', week: 1);
    await db.execute('DROP TABLE $table');
    await db.execute('PRAGMA user_version = 46');
    await database.close();
    return databaseFactoryFfi.openDatabase(
      path.join(dir.path, name),
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  }

  Map<String, Object?> row({
    String song = 'song-a',
    String? date,
    String? precision,
    String? artwork,
    int charts = 0,
  }) => {
    'song_id': song,
    'release_date': date,
    'release_date_precision': precision,
    'artwork_id': artwork,
    'use_artwork_in_charts': charts,
    'created_at': at.toIso8601String(),
    'updated_at': at.toIso8601String(),
  };

  test('a fresh database has the table, empty, at version 47', () async {
    final db = await (await fresh('fresh.db')).database;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      48,
    );
    expect(await db.query(table), isEmpty);
    expect(
      [
        for (final c in await db.rawQuery('PRAGMA table_info($table)'))
          c['name'],
      ],
      [
        'song_id',
        'release_date',
        'release_date_precision',
        'artwork_id',
        'use_artwork_in_charts',
        'created_at',
        'updated_at',
      ],
    );
  });

  test('46 to 47 adds only the table and keeps every row', () async {
    final db = await version46('upgrade.db');
    final before = await snapshotDatabase(db);
    expect(before.containsKey(table), isFalse);

    await DatabaseMigrations.migrate(db, oldVersion: 46, newVersion: 47);
    // Running it again changes nothing.
    await DatabaseMigrations.migrate(db, oldVersion: 46, newVersion: 47);

    final after = await snapshotDatabase(db);
    expect(after[table], isEmpty);
    expect(after..remove(table), before);
    await db.close();
  });

  test('an upgraded version 47 has the same table as a fresh one', () async {
    final upgraded = await version46('upgraded.db');
    await DatabaseMigrations.migrate(upgraded, oldVersion: 46, newVersion: 47);
    final reference = await (await fresh('reference.db')).database;

    Future<Object?> sqlOf(Database db) async => (await db.rawQuery(
      'SELECT sql FROM sqlite_master WHERE name = ?',
      [table],
    )).single['sql'];

    expect(await sqlOf(upgraded), await sqlOf(reference));
    await upgraded.close();
  });

  test('a release date must match its precision', () async {
    final db = await (await fresh('dates.db')).database;
    await seedConnectedLibrary(db, key: 'a');

    for (final (date, precision) in [
      ('2026', 'year'),
      ('2026-04', 'month'),
      ('2026-04-17', 'day'),
    ]) {
      await db.insert(table, row(date: date, precision: precision));
      await db.delete(table);
    }
    for (final (date, precision) in [
      ('2026-04', 'year'),
      ('2026', 'month'),
      ('2026-4', 'month'),
      ('2026-04', 'day'),
      ('26-04-17', 'day'),
      ('April 2026', 'month'),
      ('2026', 'decade'),
      ('2026', null),
      (null, 'year'),
    ]) {
      await expectLater(
        db.insert(table, row(date: date, precision: precision)),
        throwsA(anything),
        reason: '$date / $precision',
      );
    }
    expect(await db.query(table), isEmpty);
  });

  test('one row per song; never for a missing song; a missing cover is '
      'refused', () async {
    final db = await (await fresh('keys.db')).database;
    await seedConnectedLibrary(db, key: 'a');
    await db.insert(table, row());
    await expectLater(db.insert(table, row()), throwsA(anything));
    await expectLater(
      db.insert(table, row(song: 'no-such-song')),
      throwsA(anything),
    );
    await expectLater(
      db.insert(table, row(song: 'song-a', artwork: 'no-such-art')),
      throwsA(anything),
    );
    await expectLater(db.insert(table, row(charts: 2)), throwsA(anything));
  });

  test('a song stopping being a Single keeps its presentation; deleting '
      'the song removes it; deleting its cover only unlinks it', () async {
    final db = await (await fresh('cascade.db')).database;
    await seedConnectedLibrary(db, key: 'a', artworkPath: '/art/a.png');
    await seedConnectedLibrary(db, key: 'b', week: 1);
    await db.insert(table, row(song: 'song-a', artwork: 'artwork-a'));
    await db.insert(
      table,
      row(song: 'song-b', date: '2026', precision: 'year'),
    );

    await db.update(DatabaseTables.songs, {'is_single': 1});
    await db.update(DatabaseTables.songs, {'is_single': 0});
    expect(await db.query(table), hasLength(2));

    await db.update(
      DatabaseTables.songs,
      {'artwork_id': null},
      where: 'id = ?',
      whereArgs: ['song-a'],
    );
    await db.delete(
      DatabaseTables.artworkAssets,
      where: 'id = ?',
      whereArgs: ['artwork-a'],
    );
    final unlinked = (await db.query(
      table,
      where: 'song_id = ?',
      whereArgs: ['song-a'],
    )).single;
    expect(unlinked['artwork_id'], isNull);

    await db.delete(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song-b'],
    );
    expect([for (final r in await db.query(table)) r['song_id']], ['song-a']);
  });

  group('the repository', () {
    test('saves, reads with the cover file, and clears', () async {
      final database = await fresh('repo.db');
      final db = await database.database;
      await seedConnectedLibrary(db, key: 'a', artworkPath: '/art/a.png');
      final repository = SqliteSongSinglePresentationRepository(
        db,
        appDatabase: database,
      );

      await repository.save(
        SongSinglePresentation(
          songId: 'song-a',
          releaseDate: ReleaseDate.of(2026, 4, 17),
          artworkId: 'artwork-a',
          useArtworkInCharts: true,
          createdAt: at,
          updatedAt: at,
        ),
      );
      final read = (await repository.getBySongId('song-a'))!;
      expect(read.releaseDate, ReleaseDate.of(2026, 4, 17));
      expect(read.releaseDate!.precision, ReleaseDatePrecision.day);
      expect(read.artworkPath, '/art/a.png');
      expect(read.coverPath, '/art/a.png');
      expect(read.useArtworkInCharts, isTrue);
      expect((await repository.getAll()).keys, ['song-a']);

      // An empty presentation is no row at all.
      await repository.save(
        SongSinglePresentation(songId: 'song-a', createdAt: at, updatedAt: at),
      );
      expect(await repository.getBySongId('song-a'), isNull);
    });

    test('a date at each precision round-trips exactly', () async {
      final database = await fresh('precision.db');
      final db = await database.database;
      await seedConnectedLibrary(db, key: 'a');
      final repository = SqliteSongSinglePresentationRepository(db);
      for (final date in [
        ReleaseDate.of(2026)!,
        ReleaseDate.of(2026, 4)!,
        ReleaseDate.of(2026, 4, 17)!,
      ]) {
        await repository.save(
          SongSinglePresentation(
            songId: 'song-a',
            releaseDate: date,
            createdAt: at,
            updatedAt: at,
          ),
        );
        final read = (await repository.getBySongId('song-a'))!.releaseDate!;
        expect(read, date);
        expect(read.precision, date.precision);
      }
    });
  });

  test('stored dates are read only when they match their precision', () {
    expect(SongSinglePresentation.decodeDate('2026-04', 'month'), isNotNull);
    expect(SongSinglePresentation.decodeDate('2026-02-30', 'day'), isNull);
    expect(SongSinglePresentation.decodeDate('2026-04', 'day'), isNull);
    expect(SongSinglePresentation.decodeDate('2026-4', 'month'), isNull);
    expect(SongSinglePresentation.decodeDate('2026', null), isNull);
    expect(SongSinglePresentation.encodeDate(ReleaseDate.of(2026, 4)), (
      '2026-04',
      'month',
    ));
  });

  test('portable in backups; older backups without it still restore', () {
    final coverage = BackupCoverageContract.tables.singleWhere(
      (entry) => entry.table == table,
    );
    expect(coverage.isPortable, isTrue);
    expect(coverage.requiredInEveryBackup, isFalse);
    expect(BackupCompatibility.restorableDatabaseVersions, contains(46));
    expect(BackupCompatibility.restorableDatabaseVersions, contains(47));
    expect(AppDatabase.databaseVersion, 48);
  });
}
