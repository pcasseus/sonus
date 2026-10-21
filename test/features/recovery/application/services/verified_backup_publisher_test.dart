import 'dart:io';
import 'dart:convert';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';

import '../../../../support/test_only_backup_publication.dart';

void main() {
  late Directory root;
  late Directory staging;

  // Host tests cannot use the Android hard-link publication.
  const publisher = VerifiedBackupPublisher(
    publication: TestOnlyBackupPublication(),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_publish_');
    staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    await File(
      path.join(staging.path, 'manifest.json'),
    ).writeAsString('{"invalid":true}');

    await File(
      path.join(staging.path, 'library.json'),
    ).writeAsString('{"invalid":true}');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('publishes and independently verifies a valid Sonus backup', () async {
    final payload = BackupDataPayload(
      tables: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: <Map<String, Object?>>[],
      },
    );

    final manifest = BackupManifest(
      backupId: 'valid-publication-test',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: AppDatabase.databaseVersion,
      rowCounts: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: 0,
      },
    );

    await File(path.join(staging.path, 'manifest.json')).writeAsString(
      jsonEncode({'manifest': manifest.toJson(), 'artwork': <Object>[]}),
    );

    await File(path.join(staging.path, 'library.json')).writeAsString(
      const BackupIntegrityCodec().encode(manifest: manifest, payload: payload),
    );

    final destination = File(path.join(root.path, 'valid.sonusbackup'));

    final published = await publisher.publish(
      stagingDirectory: staging,
      destination: destination,
    );

    expect(published.path, destination.path);
    expect(await destination.exists(), isTrue);
    expect(await destination.length(), greaterThan(0));

    final decoded = await const BackupArchiveVerifier().verify(destination);

    expect(decoded.manifest.backupId, manifest.backupId);
    expect(decoded.payload.totalRows, 0);

    final leftovers = await root.list().toList();
    expect(
      leftovers.where(
        (entity) => path.basename(entity.path).startsWith('.sonus_verified_'),
      ),
      isEmpty,
    );
  });
  test('does not publish a backup that fails verification', () async {
    final destination = File(path.join(root.path, 'rejected.sonusbackup'));

    await expectLater(
      publisher.publish(stagingDirectory: staging, destination: destination),
      throwsFormatException,
    );

    expect(await destination.exists(), isFalse);

    final leftovers = await root.list().toList();
    expect(
      leftovers.where(
        (entity) => path.basename(entity.path).startsWith('.sonus_verified_'),
      ),
      isEmpty,
    );
  });

  test('preserves an existing destination unchanged', () async {
    final destination = File(path.join(root.path, 'existing.sonusbackup'));

    await destination.writeAsBytes([1, 2, 3]);

    await expectLater(
      publisher.publish(stagingDirectory: staging, destination: destination),
      throwsStateError,
    );

    expect(await destination.readAsBytes(), [1, 2, 3]);
  });
}
