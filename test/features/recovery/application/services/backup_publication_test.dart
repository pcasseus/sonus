import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_failure.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';
import 'package:sonus_next/features/recovery/application/services/backup_publication.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';

bool _android() => true;
bool _notAndroid() => false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformBackupPublication.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory root;
  late List<MethodCall> calls;

  // Mirrors MainActivity: a hard link either creates the name or fails
  // with EEXIST, never replacing an existing file.
  Future<Object?> linkLikeHandler(MethodCall call) async {
    calls.add(call);
    final arguments = Map<String, Object?>.from(call.arguments as Map);
    final source = arguments['source'] as String;
    final destination = arguments['destination'] as String;

    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw PlatformException(code: 'DESTINATION_EXISTS');
    }

    await File(source).copy(destination);
    return null;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_publication_');
    calls = [];
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<Directory> validStaging() async {
    final staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    final manifest = BackupManifest(
      backupId: 'publication-channel-test',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: AppDatabase.databaseVersion,
      rowCounts: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: 0,
      },
    );

    final payload = BackupDataPayload(
      tables: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: <Map<String, Object?>>[],
      },
    );

    await File(path.join(staging.path, 'manifest.json')).writeAsString(
      jsonEncode({'manifest': manifest.toJson(), 'artwork': <Object>[]}),
    );

    await File(path.join(staging.path, 'library.json')).writeAsString(
      const BackupIntegrityCodec().encode(manifest: manifest, payload: payload),
    );

    return staging;
  }

  Future<void> expectNoCandidates() async {
    final leftovers = await root.list().toList();

    expect(
      leftovers.where(
        (entity) => path.basename(entity.path).startsWith('.sonus_'),
      ),
      isEmpty,
    );
  }

  test('sends source and destination paths over the channel', () async {
    messenger.setMockMethodCallHandler(channel, linkLikeHandler);

    final source = File(path.join(root.path, 'source.sonusbackup'));
    await source.writeAsBytes([1, 2, 3]);
    final destination = File(path.join(root.path, 'final.sonusbackup'));

    await const PlatformBackupPublication(
      isAndroid: _android,
    ).publishNoReplace(source: source, destination: destination);

    expect(calls.single.method, 'publishNoReplace');
    expect(calls.single.arguments, {
      'source': source.path,
      'destination': destination.path,
    });
    expect(await destination.readAsBytes(), [1, 2, 3]);
  });

  test('maps DESTINATION_EXISTS to a destination-exists error', () async {
    messenger.setMockMethodCallHandler(channel, linkLikeHandler);

    final source = File(path.join(root.path, 'source.sonusbackup'));
    await source.writeAsBytes([1, 2, 3]);
    final destination = File(path.join(root.path, 'final.sonusbackup'));
    await destination.writeAsBytes([9]);

    await expectLater(
      const PlatformBackupPublication(
        isAndroid: _android,
      ).publishNoReplace(source: source, destination: destination),
      throwsA(isA<BackupDestinationExistsError>()),
    );

    expect(await destination.readAsBytes(), [9]);
  });

  test('maps other native failures to a publication failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'PUBLICATION_FAILED');
    });

    await expectLater(
      const PlatformBackupPublication(isAndroid: _android).publishNoReplace(
        source: File(path.join(root.path, 'a.sonusbackup')),
        destination: File(path.join(root.path, 'b.sonusbackup')),
      ),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupFailureCode.publicationFailed,
        ),
      ),
    );
  });

  test('fails closed when the native channel is missing', () async {
    await expectLater(
      const PlatformBackupPublication(isAndroid: _android).publishNoReplace(
        source: File(path.join(root.path, 'a.sonusbackup')),
        destination: File(path.join(root.path, 'b.sonusbackup')),
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test('fails closed on platforms without atomic no-replace', () async {
    messenger.setMockMethodCallHandler(channel, linkLikeHandler);

    await expectLater(
      const PlatformBackupPublication(isAndroid: _notAndroid).publishNoReplace(
        source: File(path.join(root.path, 'a.sonusbackup')),
        destination: File(path.join(root.path, 'b.sonusbackup')),
      ),
      throwsUnsupportedError,
    );

    expect(calls, isEmpty);
  });

  test('publisher uses the channel and removes the candidate link', () async {
    messenger.setMockMethodCallHandler(channel, linkLikeHandler);

    final destination = File(path.join(root.path, 'channel.sonusbackup'));

    await const VerifiedBackupPublisher(
      publication: PlatformBackupPublication(isAndroid: _android),
    ).publish(stagingDirectory: await validStaging(), destination: destination);

    final decoded = await const BackupArchiveVerifier().verify(destination);
    expect(decoded.manifest.backupId, 'publication-channel-test');
    await expectNoCandidates();
  });

  test('publisher preserves a destination created during publication', () async {
    final destination = File(path.join(root.path, 'raced.sonusbackup'));

    messenger.setMockMethodCallHandler(channel, (call) async {
      // Another writer claims the name after verification completes.
      await destination.writeAsBytes([7, 7, 7]);
      return linkLikeHandler(call);
    });

    await expectLater(
      const VerifiedBackupPublisher(
        publication: PlatformBackupPublication(isAndroid: _android),
      ).publish(
        stagingDirectory: await validStaging(),
        destination: destination,
      ),
      throwsA(isA<BackupDestinationExistsError>()),
    );

    expect(await destination.readAsBytes(), [7, 7, 7]);
    await expectNoCandidates();
  });

  test('default publisher fails closed on the host platform', () async {
    final destination = File(path.join(root.path, 'host.sonusbackup'));

    await expectLater(
      const VerifiedBackupPublisher().publish(
        stagingDirectory: await validStaging(),
        destination: destination,
      ),
      Platform.isAndroid ? completes : throwsUnsupportedError,
    );

    if (!Platform.isAndroid) {
      expect(await destination.exists(), isFalse);
      await expectNoCandidates();
    }
  });
}
