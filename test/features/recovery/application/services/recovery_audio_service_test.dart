import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/services/import_candidate_discovery.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_audio_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_status_store.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/restored_artwork_installer.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_restore_orchestrator.dart';

import '../../../../support/recovery_fixtures.dart';

/// Metadata keyed by file name, standing in for embedded tags.
class _TagReader implements AudioMetadataReader {
  _TagReader(this.tags);

  final Map<String, AudioMetadata> tags;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    final metadata = tags[path.basename(candidate.filePath)];
    if (metadata == null) throw StateError('No tags.');
    return metadata;
  }
}

class _FolderDiscovery implements ImportCandidateDiscovery {
  _FolderDiscovery(this.files);

  final List<String> files;

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) async => _candidate(filePath, discoveredAt);

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async => [for (final file in files) _candidate(file, discoveredAt)];

  ImportCandidate _candidate(String filePath, DateTime? at) => ImportCandidate(
    filePath: filePath,
    normalizedPath: filePath.replaceAll('\\', '/').toLowerCase(),
    discoveredAt: at ?? DateTime.utc(2026, 10, 21),
    // A sidecar that must not overwrite restored lyrics.
    lyricsPath: '$filePath.lrc',
    structure: ImportCandidateStructure.artistAlbum,
  );
}

AudioMetadata _tags(String artist, String album, String title) => AudioMetadata(
  title: title,
  artistName: artist,
  albumTitle: album,
  durationSeconds: 200,
  trackNumber: 1,
  discNumber: 1,
  isSingle: false,
  featuredArtists: const [],
);

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_audio_');
    target = fileAppDatabase(root, 'target.db');
  });

  tearDown(() async {
    await target.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<Map<String, int>> libraryCounts() async {
    final db = await target.database;
    return {
      for (final table in [
        ...BackupCoverageContract.portableTables.map((c) => c.table),
        DatabaseTables.songImportReviews,
        DatabaseTables.syncOutbox,
      ])
        table: (await db.query(table)).length,
    };
  }

  RecoveryAudioRelinkService relinker(
    List<String> files,
    Map<String, AudioMetadata> tags, {
    SongsBecameUnavailableCallback? onSongsBecameUnavailable,
  }) => RecoveryAudioRelinkService(
    appDatabase: target,
    candidateDiscovery: _FolderDiscovery(files),
    metadataResolver: MetadataResolver(
      primaryReader: _TagReader(tags),
      fallbackReader: _TagReader(tags),
    ),
    onSongsBecameUnavailable: onSongsBecameUnavailable,
  );

  test('counts songs without available audio', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a');
    await seedConnectedLibrary(db, key: 'b', week: 1);
    await seedConnectedLibrary(db, key: 'c', week: 2);
    await seedMediaBinding(db, key: 'a');
    await seedMediaBinding(db, key: 'b', available: false);

    final status = await RecoveryAudioStatusService(
      appDatabase: target,
    ).status();

    expect(status.totalSongs, 3);
    expect(status.songsWithoutAudio, 2);
    expect(status.songsWithAudio, 1);
    expect(status.sample.map((s) => s.songId), ['song-b', 'song-c']);
    expect(status.sample.first.artistName, 'Artist b');
  });

  test('relink-only binds matching files and creates nothing else', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a');
    await seedConnectedLibrary(db, key: 'b', week: 1);
    final countsBefore = await libraryCounts();
    final lyricsBefore = await db.query(DatabaseTables.trackLyrics);

    final matching = path.join(root.path, 'Artist a', 'Album a', '01 Song.mp3');
    final unmatched = path.join(root.path, 'Someone', 'Else', '01 New.mp3');

    final result = await relinker(
      [matching, unmatched],
      {
        '01 Song.mp3': _tags('Artist a', 'Album a', 'Song'),
        '01 New.mp3': _tags('Someone', 'Else', 'New'),
      },
    ).relinkFolder(root.path);

    expect(result.filesScanned, 2);
    expect(result.relinked, 1);
    expect(result.unmatchedOrAlreadyLinked, 1);
    expect(result.failed, 0);
    expect(result.missingBefore, 2);
    expect(result.missingAfter, 1);

    final binding = (await db.query(DatabaseTables.mediaFileBindings)).single;
    expect(binding['song_id'], 'song-a');
    expect(binding['file_path'], matching);
    expect(binding['is_available'], 1);

    // No library, history, metadata, review, or sync record was created.
    expect(await libraryCounts(), countsBefore);
    expect(await db.query(DatabaseTables.trackLyrics), lyricsBefore);
  });

  test('relink-only importer skips unmatched files without writes', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a');
    final before = await snapshotDatabase(db);

    final result =
        await AtomicLibraryImporter(
          appDatabase: target,
          userId: 'user-1',
          relinkOnly: true,
        ).import(
          candidate: ImportCandidate(
            filePath: '/music/new.mp3',
            normalizedPath: '/music/new.mp3',
            discoveredAt: DateTime.utc(2026, 10, 21),
          ),
          metadata: _tags('Brand New', 'Debut', 'First'),
        );

    expect(result.status, ImportResultStatus.skipped);
    expect(result.songId, isNull);
    expect(await snapshotDatabase(db), before);
  });

  test('the default importer still creates new library entries', () async {
    final result = await AtomicLibraryImporter(appDatabase: target).import(
      candidate: ImportCandidate(
        filePath: '/music/new.mp3',
        normalizedPath: '/music/new.mp3',
        discoveredAt: DateTime.utc(2026, 10, 21),
      ),
      metadata: _tags('Brand New', 'Debut', 'First'),
    );

    expect(result.status, ImportResultStatus.imported);
    expect(
      await (await target.database).query(DatabaseTables.songs),
      hasLength(1),
    );
  });

  test('status history round-trips and tolerates a damaged file', () async {
    final store = RecoveryStatusStore(directory: () async => root);

    expect((await store.read()).lastRestore, isNull);

    await store.recordBackup(
      RecoveryBackupRecord(
        backupId: 'b1',
        createdAtUtc: DateTime.utc(2026, 10, 20),
        exportVerified: true,
      ),
    );
    await store.recordRestore(
      RecoveryRestoreRecord(
        backupId: 'b0',
        restoredAtUtc: DateTime.utc(2026, 10, 21),
        restoredRows: 12,
        songsWithoutAudio: 3,
        artworkInstalled: 1,
        artworkReused: 0,
        syncHeld: true,
        safetyBackupPath: '/safety/pre.sonusbackup',
      ),
    );

    final status = await store.read();
    expect(status.lastBackup!.backupId, 'b1');
    expect(status.lastBackup!.exportVerified, isTrue);
    expect(status.lastRestore!.songsWithoutAudio, 3);
    expect(status.lastRestore!.syncHeld, isTrue);

    await File(
      path.join(root.path, RecoveryStatusStore.fileName),
    ).writeAsString('{broken');
    expect((await store.read()).lastBackup, isNull);
  });

  test(
    'new device: restore, report missing audio, relink, keep history',
    () async {
      final support = Directory(path.join(root.path, 'support'));
      final recovery = Directory(path.join(support.path, 'sonus', 'recovery'));
      final artwork = Directory(path.join(support.path, 'sonus', 'artwork'));
      final oldDevice = Directory(path.join(root.path, 'old-device'));
      await oldDevice.create(recursive: true);

      final cover = File(path.join(oldDevice.path, 'cover.jpg'));
      await cover.writeAsBytes([8, 8, 8]);

      final source = fileAppDatabase(oldDevice, 'old.db');
      late File backup;

      try {
        final db = await source.database;
        await seedConnectedLibrary(db, key: 'a', artworkPath: cover.path);
        await seedConnectedLibrary(db, key: 'b', week: 1);
        await seedMediaBinding(db, key: 'a');
        await seedMediaBinding(db, key: 'b');
        backup = await createFixtureBackup(
          source: source,
          directory: oldDevice,
        );
      } finally {
        await source.close();
      }

      final statusStore = RecoveryStatusStore(directory: () async => recovery);

      final result = await SonusRestoreOrchestrator(
        appDatabase: target,
        gate: RecoverySyncGate(
          holdStore: RecoverySyncHoldStore(directory: () async => recovery),
        ),
        recoveryDirectory: () async => recovery,
        artworkDirectory: () async => artwork,
        storageProbe: null,
        statusStore: statusStore,
        installer: RestoredArtworkInstaller(
          storageFactory: (fileId) => FileSystemArtworkManagedStorage(
            applicationSupportDirectoryProvider: () async => support,
            fileIdGenerator: fileId,
          ),
        ),
      ).restore(backup);

      final db = await target.database;

      // Old-device audio bindings are never restored.
      expect(await db.query(DatabaseTables.mediaFileBindings), isEmpty);
      expect(
        (await snapshotDatabase(db)).toString(),
        isNot(contains(oldDevice.path)),
      );

      final restoredStatus = await statusStore.read();
      expect(restoredStatus.lastRestore!.backupId, result.backupId);
      expect(restoredStatus.lastRestore!.songsWithoutAudio, 2);

      final audio = RecoveryAudioStatusService(appDatabase: target);
      expect((await audio.status()).songsWithoutAudio, 2);

      final newFile = path.join(root.path, 'Music', 'Artist a', '01 Song.mp3');
      final relinked = await relinker(
        [newFile],
        {'01 Song.mp3': _tags('Artist a', 'Album a', 'Song')},
      ).relinkFolder(path.join(root.path, 'Music'));

      expect(relinked.relinked, 1);
      expect((await audio.status()).songsWithoutAudio, 1);

      // Listening history keeps its identities and links.
      final play = (await db.query(
        DatabaseTables.qualifiedPlays,
        where: 'id = ?',
        whereArgs: ['play-a'],
      )).single;
      expect(play['playback_session_id'], 'session-a');
      expect(play['song_id'], 'song-a');

      final entry = (await db.query(
        DatabaseTables.chartEntries,
        where: 'id = ?',
        whereArgs: ['entry-a'],
      )).single;
      expect(entry['entity_id'], 'song-a');

      final binding = (await db.query(DatabaseTables.mediaFileBindings)).single;
      expect(binding['song_id'], 'song-a');
      expect(binding['file_path'], newFile);
    },
  );

  group('relink coordination', () {
    late String music;
    late String fileA;
    late String fileB;

    setUp(() async {
      final db = await target.database;
      await seedConnectedLibrary(db, key: 'a');
      await seedConnectedLibrary(db, key: 'b', week: 1);

      music = path.join(root.path, 'Music');
      fileA = path.join(music, 'Artist a', 'Album a', '01 Song.mp3');
      fileB = path.join(music, 'Artist b', 'Album b', '01 Song.mp3');
    });

    // Tags keyed by full path, since both files share a name.
    RecoveryAudioRelinkService relinkerFor(
      List<String> files, {
      SongsBecameUnavailableCallback? onSongsBecameUnavailable,
    }) => RecoveryAudioRelinkService(
      appDatabase: target,
      candidateDiscovery: _FolderDiscovery(files),
      metadataResolver: MetadataResolver(
        primaryReader: _PathTagReader({
          fileA: _tags('Artist a', 'Album a', 'Song'),
          fileB: _tags('Artist b', 'Album b', 'Song'),
        }),
        fallbackReader: _PathTagReader(const {}),
      ),
      onSongsBecameUnavailable: onSongsBecameUnavailable,
    );

    Future<Map<String, int>> availability() async {
      final rows = await (await target.database).query(
        DatabaseTables.mediaFileBindings,
      );
      return {
        for (final row in rows)
          row['song_id'] as String: row['is_available'] as int,
      };
    }

    Future<Object?> lastScannedAt() async {
      final rows = await (await target.database).query(
        DatabaseTables.importSources,
      );
      return rows.single['last_scanned_at'];
    }

    test('a rescan reconciles the source through the shared service', () async {
      await relinkerFor([fileA, fileB]).relinkFolder(music);
      expect(await availability(), {'song-a': 1, 'song-b': 1});
      final firstScan = await lastScannedAt();

      Set<String>? reported;
      int? activeDuringCallback;

      final result = await relinkerFor(
        [fileA],
        onSongsBecameUnavailable: (ids) async {
          reported = ids;
          activeDuringCallback = target.mutationCoordinator.activeMutations;
        },
      ).relinkFolder(music);

      expect(result.relinked, 0);
      expect(result.unmatchedOrAlreadyLinked, 1);
      expect(await availability(), {'song-a': 1, 'song-b': 0});
      expect(reported, {'song-b'});
      // Playback hears about it only after the transaction committed.
      expect(activeDuringCallback, 0);
      expect(await lastScannedAt(), isNot(firstScan));
    });

    test('a failed reconciliation rolls back and notifies nothing', () async {
      await relinkerFor([fileA, fileB]).relinkFolder(music);
      final firstScan = await lastScannedAt();

      await (await target.database).execute('''
        CREATE TRIGGER reject_source_scan
        BEFORE UPDATE ON ${DatabaseTables.importSources}
        BEGIN
          SELECT RAISE(ABORT, 'test rejection');
        END
      ''');

      var notified = false;

      await expectLater(
        relinkerFor(
          [fileA],
          onSongsBecameUnavailable: (_) async => notified = true,
        ).relinkFolder(music),
        throwsA(isA<Exception>()),
      );

      expect(await availability(), {'song-a': 1, 'song-b': 1});
      expect(await lastScannedAt(), firstScan);
      expect(notified, isFalse);
    });

    test('a restore requested mid-relink rejects the binding write', () async {
      final db = await target.database;
      await db.insert(DatabaseTables.mediaFileBindings, {
        'id': 'binding-a',
        'song_id': 'song-a',
        'file_path': fileA,
        'normalized_path': fileA.replaceAll('\\', '/').toLowerCase(),
        'is_available': 0,
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
      });
      final before = await db.query(DatabaseTables.mediaFileBindings);

      final release = Completer<void>();
      Future<void>? restore;

      try {
        // The batch is recorded and discovery is done; then a restore
        // begins before the first item reactivates the existing binding.
        await expectLater(
          relinkerFor([fileA]).relinkFolder(
            music,
            onProgress: (_) => restore ??= target.mutationCoordinator
                .runExclusiveRestore(() => release.future),
          ),
          throwsA(isA<LibraryMutationUnavailable>()),
        );

        expect(await db.query(DatabaseTables.mediaFileBindings), before);
        expect(await lastScannedAt(), isNull);
      } finally {
        release.complete();
        await restore;
      }

      // After the restore the same relink proceeds normally.
      final result = await relinkerFor([fileA]).relinkFolder(music);
      expect(result.relinked, 1);
      expect(await availability(), {'song-a': 1});
    });
  });
}

/// Metadata keyed by full file path.
class _PathTagReader implements AudioMetadataReader {
  _PathTagReader(this.tags);

  final Map<String, AudioMetadata> tags;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    final metadata = tags[candidate.filePath];
    if (metadata == null) throw StateError('No tags.');
    return metadata;
  }
}
