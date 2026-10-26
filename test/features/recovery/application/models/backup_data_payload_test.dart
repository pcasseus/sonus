import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

Map<String, List<Map<String, Object?>>> emptyTables() => {
  for (final entry in BackupCoverageContract.portableTables)
    entry.table: <Map<String, Object?>>[],
};

BackupManifest manifestFor(Map<String, List<Map<String, Object?>>> tables) {
  return BackupManifest(
    backupId: 'backup-001',
    createdAtUtc: DateTime.utc(2026, 10, 21),
    databaseVersion: AppDatabase.databaseVersion,
    rowCounts: {
      for (final entry in tables.entries) entry.key: entry.value.length,
    },
  );
}

void main() {
  test('complete empty payload matches the manifest', () {
    final tables = emptyTables();
    final payload = BackupDataPayload(tables: tables);

    payload.validateAgainst(manifestFor(tables));

    expect(payload.totalRows, 0);
    expect(payload.tables.length, 20);
  });

  test('preserves row values and validates record counts', () {
    final tables = emptyTables();
    tables[DatabaseTables.artists] = [
      {
        'id': 'artist-1',
        'name': 'Artist',
        'is_blacklisted': 0,
        'optional': null,
      },
    ];

    final payload = BackupDataPayload(tables: tables);

    payload.validateAgainst(manifestFor(tables));

    expect(payload.totalRows, 1);
    expect(payload.tables[DatabaseTables.artists]!.single['id'], 'artist-1');
  });

  test('rejects manifest and payload count mismatches', () {
    final tables = emptyTables();
    final manifest = manifestFor(tables);

    tables[DatabaseTables.artists] = [
      {'id': 'artist-1'},
    ];

    final payload = BackupDataPayload(tables: tables);

    expect(() => payload.validateAgainst(manifest), throwsFormatException);
  });

  test('rejects missing portable tables', () {
    final tables = emptyTables();
    tables.remove(DatabaseTables.artists);

    expect(() => BackupDataPayload(tables: tables), throwsFormatException);
  });

  test('rejects device-local tables inside portable payload', () {
    final tables = emptyTables();
    tables[DatabaseTables.mediaFileBindings] = [];

    expect(() => BackupDataPayload(tables: tables), throwsFormatException);
  });

  test('rejects binary values pending explicit encoding', () {
    final tables = emptyTables();
    tables[DatabaseTables.artists] = [
      {
        'image': Uint8List.fromList([1, 2, 3]),
      },
    ];

    expect(() => BackupDataPayload(tables: tables), throwsFormatException);
  });

  test('rejects unsupported and non-finite values', () {
    final tables = emptyTables();
    tables[DatabaseTables.artists] = [
      {'invalid': double.nan},
    ];

    expect(() => BackupDataPayload(tables: tables), throwsFormatException);
  });

  test('protects payload against external mutation', () {
    final tables = emptyTables();
    final row = <String, Object?>{'id': 'artist-1'};

    tables[DatabaseTables.artists] = [row];

    final payload = BackupDataPayload(tables: tables);

    row['id'] = 'changed';
    tables[DatabaseTables.artists]!.clear();

    expect(payload.tables[DatabaseTables.artists]!.single['id'], 'artist-1');

    expect(() => payload.tables.clear(), throwsUnsupportedError);
  });
}
