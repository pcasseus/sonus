import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_writer.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';

void main() {
  late Directory root;
  late Directory staging;
  late File destination;

  const verifier = BackupArchiveVerifier();
  const writer = BackupArchiveWriter();
  const codec = BackupIntegrityCodec();

  late BackupManifest manifest;
  late BackupDataPayload payload;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_verify_');
    staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    destination = File(path.join(root.path, 'test.sonusbackup'));

    payload = BackupDataPayload(
      tables: {
        for (final table in BackupCoverageContract.portableTables)
          table.table: <Map<String, Object?>>[],
      },
    );

    manifest = BackupManifest(
      backupId: 'archive-verification-test',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: AppDatabase.databaseVersion,
      rowCounts: {
        for (final table in BackupCoverageContract.portableTables)
          table.table: 0,
      },
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> prepare({
    Map<String, Object?>? externalManifest,
    String? library,
    List<Map<String, Object?>> artwork = const [],
  }) async {
    await File(path.join(staging.path, 'manifest.json')).writeAsString(
      jsonEncode(
        externalManifest ?? {'manifest': manifest.toJson(), 'artwork': artwork},
      ),
    );

    await File(path.join(staging.path, 'library.json')).writeAsString(
      library ?? codec.encode(manifest: manifest, payload: payload),
    );
  }

  Future<void> package() => writer
      .write(stagingDirectory: staging, destination: destination)
      .then((_) {});

  test('accepts valid archive with real Sonus contracts', () async {
    await prepare();
    await package();

    final result = await verifier.verify(destination);

    expect(result.manifest.backupId, manifest.backupId);
    expect(result.payload.totalRows, 0);
  });

  test('rejects corrupted library integrity envelope', () async {
    final validLibrary = codec.encode(manifest: manifest, payload: payload);

    final altered = jsonDecode(validLibrary) as Map<String, dynamic>;
    altered['digest'] = '0' * 64;

    await prepare(library: jsonEncode(altered));
    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });

  test('rejects disagreement between backup manifests', () async {
    final external = Map<String, Object>.from(manifest.toJson());
    external['backupId'] = 'different-backup';

    await prepare(
      externalManifest: {'manifest': external, 'artwork': <Object>[]},
    );
    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });

  test('rejects unexpected archive files', () async {
    await prepare();

    await File(
      path.join(staging.path, 'unexpected.txt'),
    ).writeAsString('unexpected');

    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });

  test('verifies actual artwork bytes', () async {
    payload = BackupDataPayload(
      tables: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: entry.table == DatabaseTables.artworkAssets
              ? <Map<String, Object?>>[
                  {
                    'id': 'test-cover',
                    'file_path': '/previous-device/cover.jpg',
                    'normalized_path': '/previous-device/cover.jpg',
                    'created_at': '2026-10-21T00:00:00.000Z',
                    'updated_at': '2026-10-21T00:00:00.000Z',
                  },
                ]
              : <Map<String, Object?>>[],
      },
    );

    manifest = BackupManifest(
      backupId: 'archive-verification-test',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: AppDatabase.databaseVersion,
      rowCounts: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: entry.table == DatabaseTables.artworkAssets ? 1 : 0,
      },
    );

    await prepare();

    const bytes = <int>[10, 20, 30, 40];
    final name = 'artwork/${'a' * 64}.jpg';

    final artworkDirectory = Directory(path.join(staging.path, 'artwork'));
    await artworkDirectory.create();

    await File(
      path.join(artworkDirectory.path, '${'a' * 64}.jpg'),
    ).writeAsBytes(bytes);

    await prepare(
      artwork: [
        {
          'artworkId': 'test-cover',
          'archivePath': name,
          'byteLength': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        },
      ],
    );

    await package();

    final result = await verifier.verify(destination);
    expect(result.manifest.backupId, manifest.backupId);
  });

  test('rejects artwork without a database record', () async {
    const bytes = <int>[1, 2, 3];
    final name = 'artwork/${'d' * 64}.jpg';

    final artworkDirectory = Directory(path.join(staging.path, 'artwork'));
    await artworkDirectory.create();

    await File(
      path.join(artworkDirectory.path, '${'d' * 64}.jpg'),
    ).writeAsBytes(bytes);

    await prepare(
      artwork: [
        {
          'artworkId': 'orphan-cover',
          'archivePath': name,
          'byteLength': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        },
      ],
    );

    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });

  test('rejects database artwork without an archive entry', () async {
    payload = BackupDataPayload(
      tables: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: entry.table == DatabaseTables.artworkAssets
              ? <Map<String, Object?>>[
                  {
                    'id': 'unpackaged-cover',
                    'file_path': '/old-device/cover.jpg',
                    'normalized_path': '/old-device/cover.jpg',
                    'created_at': '2026-10-21T00:00:00.000Z',
                    'updated_at': '2026-10-21T00:00:00.000Z',
                  },
                ]
              : <Map<String, Object?>>[],
      },
    );

    manifest = BackupManifest(
      backupId: 'archive-verification-test',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: AppDatabase.databaseVersion,
      rowCounts: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: entry.table == DatabaseTables.artworkAssets ? 1 : 0,
      },
    );

    await prepare();
    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });
  test('rejects altered artwork bytes', () async {
    const original = <int>[1, 2, 3];
    const modified = <int>[4, 5, 6];
    final name = 'artwork/${'b' * 64}.jpg';

    final artworkDirectory = Directory(path.join(staging.path, 'artwork'));
    await artworkDirectory.create();

    await File(
      path.join(artworkDirectory.path, '${'b' * 64}.jpg'),
    ).writeAsBytes(modified);

    await prepare(
      artwork: [
        {
          'artworkId': 'corrupt-cover',
          'archivePath': name,
          'byteLength': original.length,
          'sha256': sha256.convert(original).toString(),
        },
      ],
    );

    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });

  test('rejects missing artwork files', () async {
    await prepare(
      artwork: [
        {
          'artworkId': 'missing-cover',
          'archivePath': 'artwork/${'c' * 64}.jpg',
          'byteLength': 3,
          'sha256': sha256.convert([1, 2, 3]).toString(),
        },
      ],
    );

    await package();

    await expectLater(verifier.verify(destination), throwsFormatException);
  });
}
