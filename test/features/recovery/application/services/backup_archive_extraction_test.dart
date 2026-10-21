import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_writer.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';

import '../../../../support/recovery_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;

  const verifier = BackupArchiveVerifier();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_extract_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('extracts integrity-checked artwork with exact bytes', () async {
    final coverA = File(path.join(root.path, 'a.jpg'));
    final coverB = File(path.join(root.path, 'b.png'));
    await coverA.writeAsBytes([1, 2, 3, 4]);
    await coverB.writeAsBytes([9, 8, 7]);

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'b', week: 1, artworkPath: coverB.path);
        await seedConnectedLibrary(db, key: 'a', artworkPath: coverA.path);
      },
    );

    expect(contents.artwork.map((a) => a.artworkId), ['artwork-a', 'artwork-b']);

    final a = contents.artwork.first;
    expect(await a.file.readAsBytes(), [1, 2, 3, 4]);
    expect(a.byteLength, 4);
    expect(a.sha256Digest, sha256.convert([1, 2, 3, 4]).toString());
    expect(path.isWithin(contents.directory.path, a.file.path), isTrue);
    expect(path.extension(a.file.path), '.jpg');

    expect(await contents.artwork.last.file.readAsBytes(), [9, 8, 7]);
    expect(contents.backup.payload.tables[DatabaseTables.songs], hasLength(2));
  });

  test('extraction matches plain verification of the same backup', () async {
    final source = fileAppDatabase(root, 'source.db');

    try {
      await seedConnectedLibrary(await source.database, key: 'x');
      final backup = await createFixtureBackup(source: source, directory: root);

      final verified = await verifier.verify(backup);
      final extracted = await verifier.verifyAndExtract(
        backupFile: backup,
        targetDirectory: Directory(path.join(root.path, 'extract')),
      );

      expect(extracted.backup.manifest.backupId, verified.manifest.backupId);
      expect(extracted.backup.payload.toJson(), verified.payload.toJson());
      expect(extracted.artwork, isEmpty);
    } finally {
      await source.close();
    }
  });

  test('refuses an existing extraction directory and leaves it intact', () async {
    final source = fileAppDatabase(root, 'source.db');

    try {
      final backup = await createFixtureBackup(source: source, directory: root);
      final target = Directory(path.join(root.path, 'occupied'));
      await target.create();
      final keep = File(path.join(target.path, 'keep.txt'));
      await keep.writeAsString('keep');

      await expectLater(
        verifier.verifyAndExtract(backupFile: backup, targetDirectory: target),
        throwsStateError,
      );

      expect(await keep.readAsString(), 'keep');
    } finally {
      await source.close();
    }
  });

  group('tampered archives leave no extraction behind', () {
    late Directory staging;
    late File backup;
    late Directory target;

    setUp(() async {
      staging = Directory(path.join(root.path, 'staging'));
      await Directory(path.join(staging.path, 'artwork')).create(recursive: true);
      backup = File(path.join(root.path, 'tampered.sonusbackup'));
      target = Directory(path.join(root.path, 'extract'));
    });

    Future<void> packageArtwork({
      required List<int> listedBytes,
      required List<int> storedBytes,
    }) async {
      const artworkId = 'artwork-1';
      final archivePath =
          'artwork/${sha256.convert(utf8.encode(artworkId))}.jpg';

      final payload = BackupDataPayload(
        tables: {
          for (final entry in BackupCoverageContract.portableTables)
            entry.table: entry.table == DatabaseTables.artworkAssets
                ? [
                    {
                      'id': artworkId,
                      'file_path': '/old/cover.jpg',
                      'normalized_path': '/old/cover.jpg',
                      'created_at': fixtureTimestamp,
                      'updated_at': fixtureTimestamp,
                    },
                  ]
                : <Map<String, Object?>>[],
        },
      );

      final manifest = BackupManifest(
        backupId: 'tampered',
        createdAtUtc: DateTime.utc(2026, 10, 21),
        databaseVersion: AppDatabase.databaseVersion,
        rowCounts: {
          for (final entry in payload.tables.entries)
            entry.key: entry.value.length,
        },
      );

      await File(path.join(staging.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'manifest': manifest.toJson(),
          'artwork': [
            {
              'artworkId': artworkId,
              'archivePath': archivePath,
              'byteLength': listedBytes.length,
              'sha256': sha256.convert(listedBytes).toString(),
            },
          ],
        }),
      );

      await File(path.join(staging.path, 'library.json')).writeAsString(
        const BackupIntegrityCodec().encode(manifest: manifest, payload: payload),
      );

      await File(
        path.joinAll([staging.path, ...archivePath.split('/')]),
      ).writeAsBytes(storedBytes);

      await const BackupArchiveWriter().write(
        stagingDirectory: staging,
        destination: backup,
      );
    }

    test('altered artwork bytes', () async {
      await packageArtwork(listedBytes: [1, 2, 3], storedBytes: [3, 2, 1]);

      await expectLater(
        verifier.verifyAndExtract(backupFile: backup, targetDirectory: target),
        throwsFormatException,
      );

      expect(await target.exists(), isFalse);
    });

    test('artwork larger than its inventory entry', () async {
      await packageArtwork(listedBytes: [1, 2, 3], storedBytes: [1, 2, 3, 4]);

      await expectLater(
        verifier.verifyAndExtract(backupFile: backup, targetDirectory: target),
        throwsFormatException,
      );

      expect(await target.exists(), isFalse);
    });
  });
}
