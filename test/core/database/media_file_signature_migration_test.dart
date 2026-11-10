// App Update 1.2, BUG-09: version 43 adds three nullable audio identity
// columns to the device-local file bindings and the device-local table of
// deleted audio; nothing else, and no existing row changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/data/mappers/media_file_binding_row_mapper.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';

import '../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('sonus_v43_'));
  tearDown(() => dir.delete(recursive: true));

  Future<List<Map<String, Object?>>> columnsOf(Database db, String table) =>
      db.rawQuery('PRAGMA table_info($table)');

  Future<Set<String>> objectsOf(Database db) async => {
    for (final row in await db.rawQuery(
      "SELECT type || ':' || name AS o FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%'",
    ))
      row['o']! as String,
  };

  /// A version 42 database: today's fresh schema without what 43 added.
  Future<Database> version42(String file) async {
    final fresh = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(dir.path, 'reference.db'),
    );
    final freshDb = await fresh.database;
    final statements = [
      for (final row in await freshDb.rawQuery(
        "SELECT name, type, sql FROM sqlite_master WHERE sql IS NOT NULL "
        "AND name NOT LIKE 'sqlite_%' ORDER BY type DESC, name",
      ))
        (row['name']! as String, row['sql']! as String),
    ];
    await fresh.close();

    final db = await databaseFactoryFfi.openDatabase(file);
    for (final (name, sql) in statements) {
      if (name == DatabaseTables.deletedAudioSignatures ||
          name == 'idx_media_file_bindings_audio_signature') {
        continue;
      }
      if (name == DatabaseTables.mediaFileBindings) {
        await db.execute(
          sql
              .replaceFirst(RegExp(r'audio_signature TEXT,\s*'), '')
              .replaceFirst(RegExp(r'audio_full_hash TEXT,\s*'), '')
              .replaceFirst(
                RegExp(
                  r'signature_version INTEGER CHECK \(signature_version IS NULL '
                  r'OR signature_version >= 1\),\s*',
                ),
                '',
              ),
        );
        continue;
      }
      await db.execute(sql);
    }
    await db.execute('PRAGMA user_version = 42');
    return db;
  }

  /// A whole connected library (songs, plays, charts, playlists...) and
  /// one unavailable file binding.
  Future<void> seedBinding(Database db) async {
    await seedConnectedLibrary(db, key: 'one');
    await seedMediaBinding(db, key: 'one', available: false);
  }

  test('an upgraded version 43 equals a fresh one', () async {
    final fresh = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(dir.path, 'fresh.db'),
    );
    final freshDb = await fresh.database;
    final upgraded = await version42(path.join(dir.path, 'v42.db'));
    final before = await objectsOf(upgraded);

    await DatabaseMigrations.migrate(upgraded, oldVersion: 42, newVersion: 43);
    // An interrupted upgrade that runs again is harmless.
    await DatabaseMigrations.migrate(upgraded, oldVersion: 42, newVersion: 43);

    expect(await objectsOf(upgraded), await objectsOf(freshDb));
    expect((await objectsOf(upgraded)).difference(before), {
      'table:${DatabaseTables.deletedAudioSignatures}',
      'index:idx_media_file_bindings_audio_signature',
    });

    Map<String, Object?> shape(Map<String, Object?> c) => {
      'name': c['name'],
      'type': c['type'],
      'notnull': c['notnull'],
      'pk': c['pk'],
    };
    final upgradedColumns = {
      for (final c in await columnsOf(
        upgraded,
        DatabaseTables.mediaFileBindings,
      ))
        c['name']: shape(c),
    };
    final freshColumns = {
      for (final c in await columnsOf(
        freshDb,
        DatabaseTables.mediaFileBindings,
      ))
        c['name']: shape(c),
    };
    expect(upgradedColumns, freshColumns);
    expect(
      upgradedColumns.keys,
      containsAll(['audio_signature', 'audio_full_hash', 'signature_version']),
    );

    await upgraded.close();
    await fresh.close();
  });

  test('every existing row is kept; the new columns start empty', () async {
    final db = await version42(path.join(dir.path, 'rows.db'));
    await seedBinding(db);
    final everythingBefore = await snapshotDatabase(db);
    final before = await db.query(DatabaseTables.mediaFileBindings);

    await DatabaseMigrations.migrate(db, oldVersion: 42, newVersion: 43);

    final after = await db.query(DatabaseTables.mediaFileBindings);
    expect(after, hasLength(1));
    expect(after.single['audio_signature'], isNull);
    expect(after.single['audio_full_hash'], isNull);
    expect(after.single['signature_version'], isNull);
    expect(
      {...after.single}
        ..remove('audio_signature')
        ..remove('audio_full_hash')
        ..remove('signature_version'),
      before.single,
    );
    expect(await db.query(DatabaseTables.deletedAudioSignatures), isEmpty);
    final everythingAfter = await snapshotDatabase(db)
      ..remove(DatabaseTables.deletedAudioSignatures)
      ..remove(DatabaseTables.mediaFileBindings);
    expect(
      everythingAfter,
      {...everythingBefore}..remove(DatabaseTables.mediaFileBindings),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('opening a version 42 database upgrades it in place', () async {
    final file = path.join(dir.path, 'app.db');
    final db = await version42(file);
    await seedBinding(db);
    await db.close();

    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: file,
    );
    final opened = await app.database;
    addTearDown(app.close);
    expect(
      (await opened.rawQuery('PRAGMA user_version')).single['user_version'],
      43,
    );
    expect(await opened.query(DatabaseTables.songs), hasLength(1));
    expect(await opened.query(DatabaseTables.mediaFileBindings), hasLength(1));
  });

  test('a binding keeps its audio identity through the mapper', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await app.database;
    await seedBinding(db);
    final stored = MediaFileBindingRowMapper.fromRow(
      (await db.query(DatabaseTables.mediaFileBindings)).single,
    );
    expect(stored.audioSignature, isNull);

    final signed = stored.copyWith(
      audioSignature: 'v1:166800:abc',
      audioFullHash: 'def',
      signatureVersion: 1,
    );
    await db.update(
      DatabaseTables.mediaFileBindings,
      MediaFileBindingRowMapper.toRow(signed),
      where: 'id = ?',
      whereArgs: [signed.id],
    );
    final MediaFileBinding read = MediaFileBindingRowMapper.fromRow(
      (await db.query(DatabaseTables.mediaFileBindings)).single,
    );
    expect(read.audioSignature, 'v1:166800:abc');
    expect(read.audioFullHash, 'def');
    expect(read.signatureVersion, 1);

    await expectLater(
      db.update(DatabaseTables.mediaFileBindings, {'signature_version': 0}),
      throwsA(anything),
    );
    await app.close();
  });

  test('deleted audio needs a signature and a song, once each', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await app.database;
    Future<void> insert(String signature, String songId) =>
        db.insert(DatabaseTables.deletedAudioSignatures, {
          'audio_signature': signature,
          'song_id': songId,
          'operation_id': 'op',
          'recorded_at': '2026-11-09T00:00:00Z',
        });

    await insert('v1:1:a', 'song-1');
    await expectLater(insert('v1:1:a', 'song-2'), throwsA(anything));
    await expectLater(insert('', 'song-1'), throwsA(anything));
    await expectLater(insert('v1:1:b', ''), throwsA(anything));
    await app.close();
  });
}
