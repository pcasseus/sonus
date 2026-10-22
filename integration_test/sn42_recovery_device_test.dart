import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/services/file_system_import_candidate_discovery.dart';
import 'package:sonus_next/features/import/data/services/media_metadata_reader.dart';
import 'package:sonus_next/features/import/data/services/path_fallback_metadata_reader.dart';
import 'package:sonus_next/features/recovery/application/models/backup_failure.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/backup_publication.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_audio_service.dart';
import 'package:sonus_next/features/recovery/application/services/rename_no_replace_publication.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_fingerprint_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_assessment_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/restore_journal_store.dart';
import 'package:sonus_next/features/recovery/application/services/restored_artwork_installer.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_restore_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/storage_space_probe.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

import '../test/support/library_seed.dart';
import 'support/device_test_root.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory support;
  late Directory recovery;
  late Directory artwork;
  final opened = <AppDatabase>[];

  setUp(() async {
    root = await createDeviceTestRoot('device');
    support = Directory(path.join(root.path, 'support'));
    recovery = Directory(path.join(support.path, 'sonus', 'recovery'));
    artwork = Directory(path.join(support.path, 'sonus', 'artwork'));
    await recovery.create(recursive: true);
    await artwork.create(recursive: true);
  });

  tearDown(() async {
    for (final database in opened) {
      await database.close();
    }
    opened.clear();
    await deleteDeviceTestRoot(root);
  });

  // Real Android sqflite on a disposable file inside the test root.
  AppDatabase database(String name) {
    final db = AppDatabase(databasePath: path.join(root.path, name));
    opened.add(db);
    return db;
  }

  Future<File> backupOf(
    AppDatabase source,
    String id, {
    String? directory,
  }) async {
    final folder = Directory(directory ?? path.join(root.path, 'backups'));
    await folder.create(recursive: true);

    // Default publisher: production Android hard-link publication.
    return SonusBackupOrchestrator(
      exporter: SqliteBackupExporter(
        appDatabase: source,
        generateId: () => id,
      ),
    ).createBackup(destination: File(path.join(folder.path, '$id.sonusbackup')));
  }

  SonusRestoreOrchestrator restorer(
    AppDatabase target,
    RecoverySyncGate gate,
  ) => SonusRestoreOrchestrator(
    appDatabase: target,
    gate: gate,
    recoveryDirectory: () async => recovery,
    artworkDirectory: () async => artwork,
    // Production StatFs probe over the platform channel.
    storageProbe: const PlatformStorageSpaceProbe(),
    installer: RestoredArtworkInstaller(
      storageFactory: (fileId) => FileSystemArtworkManagedStorage(
        applicationSupportDirectoryProvider: () async => support,
        fileIdGenerator: fileId,
      ),
    ),
    safetyBackupWriter: (destination) => SonusBackupOrchestrator(
      exporter: SqliteBackupExporter(appDatabase: target),
    ).createBackup(destination: destination),
  );

  RecoverySyncGate newGate({bool requiresStartupCheck = false}) =>
      RecoverySyncGate(
        holdStore: RecoverySyncHoldStore(directory: () async => recovery),
        requiresStartupCheck: requiresStartupCheck,
      );

  Future<bool> syncAllowed(RecoverySyncGate gate) async {
    try {
      await gate.guard(() async {});
      return true;
    } on SyncHeldForRecovery {
      return false;
    }
  }

  testWidgets('atomic renameat2 publication never replaces a file', (_) async {
    expect(RenameNoReplacePublication.isSupported, isTrue);

    final first = File(path.join(root.path, 'first.bin'));
    final second = File(path.join(root.path, 'second.bin'));
    final destination = File(path.join(root.path, 'published.sonusbackup'));
    await first.writeAsBytes([1, 2, 3]);
    await second.writeAsBytes([9, 9, 9, 9]);

    const publication = PlatformBackupPublication();

    await publication.publishNoReplace(source: first, destination: destination);
    expect(await destination.readAsBytes(), [1, 2, 3]);
    expect(await first.exists(), isFalse, reason: 'renamed in one step');

    await expectLater(
      publication.publishNoReplace(source: second, destination: destination),
      throwsA(isA<BackupDestinationExistsError>()),
    );
    expect(await destination.readAsBytes(), [1, 2, 3]);
    expect(await second.readAsBytes(), [9, 9, 9, 9], reason: 'left in place');
  });

  testWidgets('hard links are denied to apps (why renameat2 is used)', (
    _,
  ) async {
    final source = File(path.join(root.path, 'link-source.bin'));
    await source.writeAsBytes([1]);
    final destination = File(path.join(root.path, 'link-target.bin'));

    await expectLater(
      const HardLinkChannelPublication().publishNoReplace(
        source: source,
        destination: destination,
      ),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains(': 13'),
        ),
      ),
    );
    expect(await destination.exists(), isFalse);
  });

  testWidgets('StatFs reports plausible free space', (_) async {
    final bytes = await const PlatformStorageSpaceProbe().availableBytes(
      root.path,
    );

    expect(bytes, isNotNull);
    expect(bytes!, greaterThan(0));
    expect(bytes, lessThan(64 * 1024 * 1024 * 1024 * 1024));
  });

  testWidgets('document channel streams a file and verifies it natively', (
    _,
  ) async {
    final source = File(path.join(root.path, 'export-source.bin'));
    await source.writeAsBytes(List.generate(300 * 1024, (i) => i % 253));
    final target = File(path.join(root.path, 'export-target.bin'));
    await target.create();

    const platform = MethodChannelBackupDocumentPlatform();
    final uri = Uri.file(target.path).toString();

    final written = await platform.writeDocument(source: source, uri: uri);
    expect(written, await source.length());

    final readBack = await platform.readBackDocument(uri);
    expect(readBack, isNotNull);
    expect(readBack!.length, await source.length());
    expect(
      readBack.sha256,
      (await sha256.bind(source.openRead()).first).toString(),
      reason: 'native SHA-256 must match the Dart digest',
    );
  });

  testWidgets('backup and restore round-trip on Android', (_) async {
    final source = database('old-device.db');
    final cover = File(path.join(root.path, 'old-device', 'cover.jpg'));
    await cover.create(recursive: true);
    await cover.writeAsBytes([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);

    final sourceDb = await source.database;
    await seedConnectedLibrary(sourceDb, key: 'a', artworkPath: cover.path);
    await seedConnectedLibrary(sourceDb, key: 'b', week: 1);
    await seedMediaBinding(sourceDb, key: 'a');

    final backup = await backupOf(source, 'round-trip');
    final verified = await const BackupArchiveVerifier().verify(backup);
    expect(verified.manifest.backupId, 'round-trip');

    final target = database('new-device.db');
    final gate = newGate();
    final result = await restorer(target, gate).restore(backup);
    final db = await target.database;

    expect(result.safetyBackup, isNull);
    expect(result.artworkInstalled, 1);
    expect(result.syncHeld, isFalse);

    for (final coverage in BackupCoverageContract.portableTables) {
      if (coverage.table == DatabaseTables.artworkAssets) continue;

      expect(
        await db.query(coverage.table),
        unorderedEquals(await sourceDb.query(coverage.table)),
        reason: coverage.table,
      );
    }

    // Artwork is reinstalled into device storage and remapped.
    final restoredArtwork = (await db.query(DatabaseTables.artworkAssets)).single;
    final installed = restoredArtwork['file_path'] as String;
    expect(path.isWithin(artwork.path, installed), isTrue);
    expect(await File(installed).readAsBytes(), await cover.readAsBytes());
    expect(installed, isNot(cover.path));

    // History and charts keep their identities and links.
    final play = (await db.query(
      DatabaseTables.qualifiedPlays,
      where: 'id = ?',
      whereArgs: ['play-a'],
    )).single;
    expect(play['playback_session_id'], 'session-a');
    expect(
      (await db.query(DatabaseTables.chartEntries)).map((r) => r['entity_id']),
      containsAll(['song-a', 'song-b']),
    );

    // Old-device audio bindings never arrive.
    expect(await db.query(DatabaseTables.mediaFileBindings), isEmpty);
    expect(await syncAllowed(gate), isTrue);
  });

  testWidgets('restoring over a library keeps a verified safety backup', (
    _,
  ) async {
    final source = database('source.db');
    await seedConnectedLibrary(await source.database, key: 'b');
    final backup = await backupOf(source, 'replacement');

    final target = database('target.db');
    await seedConnectedLibrary(
      await target.database,
      key: 'a',
      songTitle: 'Existing',
    );

    final result = await restorer(target, newGate()).restore(backup);

    final safety = result.safetyBackup!;
    final preserved = await const BackupArchiveVerifier().verify(safety);
    expect(
      preserved.payload.tables[DatabaseTables.songs]!.single['title'],
      'Existing',
    );
    expect(
      (await (await target.database).query(DatabaseTables.songs)).single['id'],
      'song-b',
    );
  });

  testWidgets('relinks restored songs to audio files on the device', (_) async {
    final target = database('relink.db');
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a');
    await seedConnectedLibrary(db, key: 'b', week: 1);

    final music = Directory(path.join(root.path, 'Music'));
    final file = File(path.join(music.path, 'Artist a', 'Album a', '01 Song.mp3'));
    await file.create(recursive: true);
    await file.writeAsBytes(List.filled(2048, 0));

    final result = await RecoveryAudioRelinkService(
      appDatabase: target,
      candidateDiscovery: const FileSystemImportCandidateDiscovery(),
      metadataResolver: MetadataResolver(
        primaryReader: MediaMetadataReader(),
        fallbackReader: const PathFallbackMetadataReader(),
      ),
    ).relinkFolder(music.path);

    expect(result.relinked, 1);
    expect(result.missingBefore, 2);
    expect(result.missingAfter, 1);
    expect(await db.query(DatabaseTables.songs), hasLength(2));

    final binding = (await db.query(DatabaseTables.mediaFileBindings)).single;
    expect(binding['song_id'], 'song-a');
  });

  testWidgets('an interrupted restore is recovered before sync starts', (
    _,
  ) async {
    final target = database('interrupted.db');
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a');

    await RecoverySyncHoldStore(directory: () async => recovery).write(
      RecoverySyncHold(
        holdId: 'killed',
        backupId: 'killed',
        createdAtUtc: DateTime.utc(2026, 10, 21),
        phase: RecoverySyncHoldPhase.restoring,
        backupAccountIds: const {},
        preRestore: await const RecoveryFingerprintService().capture(db),
      ),
    );
    final orphan = File(path.join(artwork.path, 'artwork_restorekilledn0.jpg'));
    await orphan.writeAsBytes([1]);
    await RestoreJournalStore(directory: () async => recovery).write(
      RestoreJournal(
        sessionId: 'killed',
        extractionDirectory: path.join(recovery.path, '.sonus_restore_killed'),
        reservedTokens: const ['restorekilledn0'],
        createdFiles: [orphan.path],
      ),
    );

    final gate = newGate(requiresStartupCheck: true);
    expect(await syncAllowed(gate), isFalse);

    await gate.runStartupCheck(() => restorer(target, gate).reassessSyncHold());

    expect(await orphan.exists(), isFalse);
    expect(await syncAllowed(gate), isTrue);
  });

  testWidgets('a cloud-linked restore keeps sync paused', (_) async {
    final source = database('cloud-source.db');
    await seedConnectedLibrary(await source.database, key: 'a', userId: 'user-1');
    await seedConnectedLibrary(
      await source.database,
      key: 'b',
      week: 1,
      userId: 'user-1',
    );
    final backup = await backupOf(source, 'cloud');

    final target = database('cloud-target.db');
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a', userId: 'user-1', songTitle: 'Old');
    await db.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': 'user-1',
      'bound_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    await db.insert(SyncSchema.cloudRevisionBaselinesTable, {
      'user_id': 'user-1',
      'entity_type': 'artist',
      'entity_id': 'artist-a',
      'server_revision': 1,
    });
    final syncBefore = {
      for (final t in RecoveryFingerprintService.syncStateTables)
        t: await db.query(t),
    };

    final gate = newGate();
    final result = await restorer(target, gate).restore(backup);

    expect(result.syncHeld, isTrue);
    expect(
      result.syncAssessment.findings,
      contains(RecoverySyncFinding.cloudLibraryDiverged),
    );
    for (final entry in syncBefore.entries) {
      expect(await db.query(entry.key), entry.value, reason: entry.key);
    }

    // A guarded sync run performs no work at all.
    final calls = <String>[];
    final service = SyncService.forTesting(
      bindToUser: (_) async => calls.add('bind'),
      claimUnowned: (_) async => 0,
      getPending: (_) async => const [],
      pushPending: (_) async => calls.add('push'),
      pullAll: (_) async {
        calls.add('pull');
        return 0;
      },
      runGuard: gate,
    );

    await expectLater(
      service.synchronize('user-1'),
      throwsA(isA<SyncHeldForRecovery>()),
    );
    expect(calls, isEmpty);
    expect(await syncAllowed(newGate()), isFalse, reason: 'survives restart');
  });
}
