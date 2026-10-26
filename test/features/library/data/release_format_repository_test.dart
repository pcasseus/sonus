// SN-45: a release's format and its classification share one row but are
// independent facts: setting or clearing one never touches the other.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_payload_schema_validator.dart';

import '../../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase app;
  late SqliteLibraryOrganizationRepository repository;
  final at = DateTime.utc(2026, 10, 26);

  setUp(() async {
    app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await seedConnectedLibrary(await app.database, key: 'a');
    repository = SqliteLibraryOrganizationRepository(app);
  });

  tearDown(() => app.close());

  AlbumReleaseFormat single() => AlbumReleaseFormat(
    albumId: 'album-a',
    format: ReleaseFormat.single,
    authority: ReleaseClassificationAuthority.manual,
    createdAt: at,
    updatedAt: at,
  );

  AlbumReleaseClassification soundtrack() => AlbumReleaseClassification(
    albumId: 'album-a',
    kind: ReleaseKind.soundtrack,
    authority: ReleaseClassificationAuthority.external,
    createdAt: at,
    updatedAt: at,
  );

  test('format and classification are kept side by side', () async {
    await repository.saveClassification(soundtrack());
    await repository.saveFormat(single());

    expect(
      (await repository.getClassifications()).single.kind,
      ReleaseKind.soundtrack,
    );
    expect((await repository.getFormats()).single.format, ReleaseFormat.single);

    await repository.deleteFormat('album-a');
    expect(await repository.getFormats(), isEmpty);
    expect(await repository.getClassifications(), hasLength(1));

    await repository.saveFormat(single());
    await repository.deleteClassification('album-a');
    expect(await repository.getClassifications(), isEmpty);
    expect(await repository.getFormats(), hasLength(1));

    await repository.deleteFormat('album-a');
    expect(
      await (await app.database).query(
        DatabaseTables.albumReleaseClassifications,
      ),
      isEmpty,
      reason: 'the row goes once neither fact is left',
    );
  });

  test('a format-only row is not a classification', () async {
    await repository.saveFormat(single());
    expect(await repository.getClassifications(), isEmpty);
  });

  test(
    'a classification row from a version 37 backup still validates',
    () async {
      final db = await app.database;
      Future<void> validate(Map<String, Object?> row) =>
          const BackupPayloadSchemaValidator().validate(
            database: db,
            payload: BackupDataPayload(
              tables: {
                for (final coverage in BackupCoverageContract.portableTables)
                  coverage.table: const [],
                DatabaseTables.albumReleaseClassifications: [row],
              },
            ),
          );

      final v37Row = {
        'album_id': 'album-a',
        'kind': 'soundtrack',
        'authority': 'manual',
        'source_reference': null,
        'created_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      };
      await validate(v37Row);
      await validate({
        ...v37Row,
        'format': 'single',
        'format_authority': 'manual',
        'format_source_reference': null,
      });
      await expectLater(
        validate({...v37Row, 'unknown_column': 1}),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        validate({...v37Row}..remove('kind')),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
