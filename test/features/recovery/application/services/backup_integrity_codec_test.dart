import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';

BackupDataPayload fixturePayload() {
  final tables = {
    for (final entry in BackupCoverageContract.portableTables)
      entry.table: <Map<String, Object?>>[],
  };

  tables[DatabaseTables.artists] = [
    {'id': 'artist-1', 'name': 'Original Artist'},
  ];

  return BackupDataPayload(tables: tables);
}

BackupManifest fixtureManifest() => BackupManifest(
  backupId: 'backup-integrity-test',
  createdAtUtc: DateTime.utc(2026, 10, 21),
  databaseVersion: AppDatabase.databaseVersion,
  rowCounts: {
    for (final entry in BackupCoverageContract.portableTables)
      entry.table: entry.table == DatabaseTables.artists ? 1 : 0,
  },
);

void main() {
  const codec = BackupIntegrityCodec();

  String validEnvelope() =>
      codec.encode(manifest: fixtureManifest(), payload: fixturePayload());

  test('valid integrity envelope round-trips', () {
    final result = codec.decode(validEnvelope());

    expect(result.manifest.backupId, 'backup-integrity-test');
    expect(
      result.payload.tables[DatabaseTables.artists]!.single['name'],
      'Original Artist',
    );
  });

  test('changing a row value without changing count fails', () {
    final envelope = jsonDecode(validEnvelope()) as Map<String, dynamic>;

    final document =
        jsonDecode(envelope['document'] as String) as Map<String, dynamic>;

    final payload = document['payload'] as Map<String, dynamic>;
    final artists = payload[DatabaseTables.artists] as List<dynamic>;
    final artist = artists.single as Map<String, dynamic>;

    artist['name'] = 'Modified Artist';
    envelope['document'] = jsonEncode(document);

    expect(() => codec.decode(jsonEncode(envelope)), throwsFormatException);
  });

  test('changing manifest contents fails', () {
    final envelope = jsonDecode(validEnvelope()) as Map<String, dynamic>;

    final document =
        jsonDecode(envelope['document'] as String) as Map<String, dynamic>;

    final manifest = document['manifest'] as Map<String, dynamic>;

    manifest['backupId'] = 'modified-backup';
    envelope['document'] = jsonEncode(document);

    expect(() => codec.decode(jsonEncode(envelope)), throwsFormatException);
  });

  test('incorrect digest fails', () {
    final envelope = jsonDecode(validEnvelope()) as Map<String, dynamic>;

    envelope['digest'] = '0' * 64;

    expect(() => codec.decode(jsonEncode(envelope)), throwsFormatException);
  });

  test('malformed envelope fails', () {
    expect(() => codec.decode('{"document":'), throwsFormatException);
  });

  test('unsupported integrity version fails', () {
    final envelope = jsonDecode(validEnvelope()) as Map<String, dynamic>;

    envelope['integrityVersion'] = 999;

    expect(() => codec.decode(jsonEncode(envelope)), throwsFormatException);
  });

  test('encoding the same backup yields identical output', () {
    expect(validEnvelope(), validEnvelope());
  });
}
