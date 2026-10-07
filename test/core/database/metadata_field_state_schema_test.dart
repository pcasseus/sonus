import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await LibrarySchema.create(db);
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('creates metadata field states table and entity index', () async {
    final tableRows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = ?
      ''',
      [DatabaseTables.metadataFieldStates],
    );

    expect(tableRows, hasLength(1));

    final indexRows = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
        AND name = 'idx_metadata_field_states_entity'
      ''');

    expect(indexRows, hasLength(1));
  });

  test(
    'uses entity type, entity id, and field name as composite identity',
    () async {
      const timestamp = '2026-10-07T12:00:00.000Z';

      await database.insert(DatabaseTables.metadataFieldStates, {
        'entity_type': 'song',
        'entity_id': 'song_1',
        'field_name': 'title',
        'authority': 'imported',
        'source': 'embeddedTag',
        'updated_at': timestamp,
      });

      expect(
        () => database.insert(DatabaseTables.metadataFieldStates, {
          'entity_type': 'song',
          'entity_id': 'song_1',
          'field_name': 'title',
          'authority': 'manual',
          'source': 'user',
          'updated_at': timestamp,
        }),
        throwsA(anything),
      );

      await database.insert(DatabaseTables.metadataFieldStates, {
        'entity_type': 'song',
        'entity_id': 'song_1',
        'field_name': 'artistCredits',
        'authority': 'imported',
        'source': 'embeddedTag',
        'updated_at': timestamp,
      });

      final rows = await database.query(DatabaseTables.metadataFieldStates);

      expect(rows, hasLength(2));
    },
  );

  test(
    'rejects unsupported entity, authority, and provenance values',
    () async {
      const timestamp = '2026-10-07T12:00:00.000Z';

      Future<void> insert({
        required String entityType,
        required String authority,
        required String source,
      }) {
        return database.insert(DatabaseTables.metadataFieldStates, {
          'entity_type': entityType,
          'entity_id': 'song_1',
          'field_name': 'title',
          'authority': authority,
          'source': source,
          'updated_at': timestamp,
        });
      }

      expect(
        () =>
            insert(entityType: 'playlist', authority: 'manual', source: 'user'),
        throwsA(anything),
      );

      expect(
        () => insert(
          entityType: 'song',
          authority: 'superTrusted',
          source: 'user',
        ),
        throwsA(anything),
      );

      expect(
        () =>
            insert(entityType: 'song', authority: 'manual', source: 'internet'),
        throwsA(anything),
      );
    },
  );

  test('allows optional source reference', () async {
    const timestamp = '2026-10-07T12:00:00.000Z';

    await database.insert(DatabaseTables.metadataFieldStates, {
      'entity_type': 'song',
      'entity_id': 'song_1',
      'field_name': 'title',
      'authority': 'external',
      'source': 'musicBrainz',
      'source_reference': 'recording_mbid_123',
      'updated_at': timestamp,
    });

    final rows = await database.query(DatabaseTables.metadataFieldStates);

    expect(rows.single['source_reference'], 'recording_mbid_123');
  });
}
