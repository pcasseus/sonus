import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_metadata_field_state_repository.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteMetadataFieldStateRepository repository;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;

    repository = SqliteMetadataFieldStateRepository(MetadataFieldStateDao(db));
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('saves and restores metadata field state', () async {
    final updatedAt = DateTime.utc(2026, 10, 7, 12);

    final state = MetadataFieldState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.external,
      source: MetadataProvenanceSource.musicBrainz,
      sourceReference: 'recording_mbid_123',
      updatedAt: updatedAt,
    );

    await repository.save(state);

    final restored = await repository.get(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
    );

    expect(restored, isNotNull);
    expect(restored!.entityType, MetadataEntityType.song);
    expect(restored.entityId, 'song_1');
    expect(restored.fieldName, 'title');
    expect(restored.authority, MetadataAuthority.external);
    expect(restored.source, MetadataProvenanceSource.musicBrainz);
    expect(restored.sourceReference, 'recording_mbid_123');
    expect(restored.updatedAt, updatedAt);
  });

  test('saving the same field replaces its provenance state', () async {
    final first = MetadataFieldState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.imported,
      source: MetadataProvenanceSource.embeddedTag,
      updatedAt: DateTime.utc(2026, 10, 7, 12),
    );

    final second = MetadataFieldState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.manual,
      source: MetadataProvenanceSource.user,
      updatedAt: DateTime.utc(2026, 10, 7, 13),
    );

    await repository.save(first);
    await repository.save(second);

    final restored = await repository.get(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
    );

    expect(restored!.authority, MetadataAuthority.manual);
    expect(restored.source, MetadataProvenanceSource.user);
    expect(restored.sourceReference, isNull);
    expect(restored.updatedAt, second.updatedAt);
  });

  test('loads all states for one entity in field-name order', () async {
    final now = DateTime.utc(2026, 10, 7, 12);

    await repository.save(
      MetadataFieldState(
        entityType: MetadataEntityType.song,
        entityId: 'song_1',
        fieldName: 'versionLabel',
        authority: MetadataAuthority.imported,
        source: MetadataProvenanceSource.embeddedTag,
        updatedAt: now,
      ),
    );

    await repository.save(
      MetadataFieldState(
        entityType: MetadataEntityType.song,
        entityId: 'song_1',
        fieldName: 'artistCredits',
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: now,
      ),
    );

    await repository.save(
      MetadataFieldState(
        entityType: MetadataEntityType.album,
        entityId: 'album_1',
        fieldName: 'title',
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: now,
      ),
    );

    final songStates = await repository.getByEntity(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
    );

    expect(songStates, hasLength(2));
    expect(songStates.map((state) => state.fieldName), [
      'artistCredits',
      'versionLabel',
    ]);
  });

  test('deletes one field without deleting other entity fields', () async {
    final now = DateTime.utc(2026, 10, 7, 12);

    for (final fieldName in const ['title', 'artistCredits']) {
      await repository.save(
        MetadataFieldState(
          entityType: MetadataEntityType.song,
          entityId: 'song_1',
          fieldName: fieldName,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: now,
        ),
      );
    }

    await repository.delete(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
    );

    expect(
      await repository.get(
        entityType: MetadataEntityType.song,
        entityId: 'song_1',
        fieldName: 'title',
      ),
      isNull,
    );

    expect(
      await repository.get(
        entityType: MetadataEntityType.song,
        entityId: 'song_1',
        fieldName: 'artistCredits',
      ),
      isNotNull,
    );
  });

  test('deletes all provenance belonging to one entity', () async {
    final now = DateTime.utc(2026, 10, 7, 12);

    for (final fieldName in const ['title', 'artistCredits']) {
      await repository.save(
        MetadataFieldState(
          entityType: MetadataEntityType.song,
          entityId: 'song_1',
          fieldName: fieldName,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: now,
        ),
      );
    }

    await repository.save(
      MetadataFieldState(
        entityType: MetadataEntityType.song,
        entityId: 'song_2',
        fieldName: 'title',
        authority: MetadataAuthority.imported,
        source: MetadataProvenanceSource.embeddedTag,
        updatedAt: now,
      ),
    );

    await repository.deleteByEntity(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
    );

    expect(
      await repository.getByEntity(
        entityType: MetadataEntityType.song,
        entityId: 'song_1',
      ),
      isEmpty,
    );

    expect(
      await repository.getByEntity(
        entityType: MetadataEntityType.song,
        entityId: 'song_2',
      ),
      hasLength(1),
    );
  });
}
