import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_json_codec.dart';

BackupDataPayload payloadFixture() {
  final tables = {
    for (final entry in BackupCoverageContract.portableTables)
      entry.table: <Map<String, Object?>>[],
  };

  tables[DatabaseTables.artists] = [
    {
      'id': 'artist-1',
      'name': 'Example',
      'is_blacklisted': 0,
      'header_artwork_id': null,
    },
  ];

  return BackupDataPayload(tables: tables);
}

BackupManifest manifestFixture() {
  return BackupManifest(
    backupId: 'backup-1',
    createdAtUtc: DateTime.utc(2026, 10, 21),
    databaseVersion: AppDatabase.databaseVersion,
    rowCounts: {
      for (final entry in BackupCoverageContract.portableTables)
        entry.table: entry.table == DatabaseTables.artists ? 1 : 0,
    },
  );
}

void main() {
  const codec = BackupJsonCodec();

  test('round-trips manifest and payload without losing values', () {
    final encoded = codec.encode(
      manifest: manifestFixture(),
      payload: payloadFixture(),
    );

    final restored = codec.decode(encoded);

    expect(restored.manifest.backupId, 'backup-1');
    expect(restored.payload.totalRows, 1);
    expect(
      restored.payload.tables[DatabaseTables.artists]!.single['name'],
      'Example',
    );
    expect(
      restored
          .payload
          .tables[DatabaseTables.artists]!
          .single['header_artwork_id'],
      isNull,
    );
  });

  test('encoding the same data is deterministic', () {
    String encode() =>
        codec.encode(manifest: manifestFixture(), payload: payloadFixture());

    expect(encode(), encode());
  });

  test('rejects malformed JSON', () {
    expect(() => codec.decode('{"manifest":'), throwsFormatException);
  });

  test('rejects missing document sections', () {
    expect(() => codec.decode('{"manifest":{}}'), throwsFormatException);
  });

  test('rejects payload row-count tampering', () {
    final original = codec.encode(
      manifest: manifestFixture(),
      payload: payloadFixture(),
    );

    final document = jsonDecode(original) as Map<String, dynamic>;
    final payload = document['payload'] as Map<String, dynamic>;

    payload[DatabaseTables.artists] = [];

    expect(() => codec.decode(jsonEncode(document)), throwsFormatException);
  });

  test('rejects non-row payload data', () {
    final original = codec.encode(
      manifest: manifestFixture(),
      payload: payloadFixture(),
    );

    final document = jsonDecode(original) as Map<String, dynamic>;
    final payload = document['payload'] as Map<String, dynamic>;

    payload[DatabaseTables.artists] = ['invalid row'];

    expect(() => codec.decode(jsonEncode(document)), throwsFormatException);
  });
}
