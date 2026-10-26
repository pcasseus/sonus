// Release readiness: rehearses a clean reinstall with disposable data only.
// Device A builds a representative library through the real services,
// backs up through the real Backup & Restore controller, and a fresh
// device B restores it. Every portable record is compared.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/all_time_moment_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/recovery/application/controllers/backup_restore_controller.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../support/recovery_fixtures.dart';
import '../../support/test_only_backup_publication.dart';

class _Tags implements AudioMetadataReader {
  _Tags(this.tags);

  final Map<String, AudioMetadata> tags;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async =>
      tags[candidate.filePath]!;
}

class _Downloads implements BackupDocumentPlatform {
  _Downloads(this.root);

  final Directory root;

  File file(String uri) => File(path.join(root.path, uri.split('/').last));

  @override
  Future<String?> createDocument(String suggestedName) async {
    await File(path.join(root.path, suggestedName)).create(exclusive: true);
    return 'content://downloads/$suggestedName';
  }

  @override
  Future<int> writeDocument({required File source, required String uri}) async {
    await source.copy(file(uri).path);
    return file(uri).length();
  }

  @override
  Future<({String sha256, int length})?> readBackDocument(String uri) async {
    final bytes = await file(uri).readAsBytes();
    return (sha256: sha256.convert(bytes).toString(), length: bytes.length);
  }

  @override
  Future<bool> deleteDocument(String uri) async {
    await file(uri).delete();
    return true;
  }
}

class _Picker implements RecoveryFilePicker {
  File? backup;

  @override
  Future<File?> pickBackupFile() async => backup;

  @override
  Future<String?> pickMusicFolder() async => null;
}

/// One disposable installation: its own database, app storage and
/// "Downloads" folder.
class _Device {
  _Device(Directory parent, String name)
    : root = Directory(path.join(parent.path, name)) {
    support = Directory(path.join(root.path, 'support'));
    recovery = Directory(path.join(support.path, 'sonus', 'recovery'));
    downloads = Directory(path.join(root.path, 'Downloads'));
  }

  final Directory root;
  late final Directory support;
  late final Directory recovery;
  late final Directory downloads;
  late final AppDatabase database;
  final picker = _Picker();

  Future<void> install() async {
    await recovery.create(recursive: true);
    await downloads.create(recursive: true);
    database = fileAppDatabase(root, 'sonus_next.db');
    await database.database;
  }

  Future<BackupRestoreController> backupRestore() async {
    final gate = RecoverySyncGate(
      holdStore: RecoverySyncHoldStore(directory: () async => recovery),
      requiresStartupCheck: true,
    );
    final controller = BackupRestoreController(
      service: DefaultRecoveryService(
        appDatabase: database,
        gate: gate,
        recoveryDirectory: () async => recovery,
        artworkDirectory: () async =>
            Directory(path.join(support.path, 'sonus', 'artwork')),
        supportDirectory: () async => support,
        picker: picker,
        stopPlayback: () async {},
        relink: (_) async => throw UnimplementedError(),
        exporter: BackupDocumentExporter(platform: _Downloads(downloads)),
        publisher: const VerifiedBackupPublisher(
          publication: TestOnlyBackupPublication(),
        ),
        storageProbe: null,
      ),
      onSyncMayResume: () {},
    );
    await controller.initialize();
    return controller;
  }
}

final _now = DateTime.utc(2026, 10, 25, 12);

AudioMetadata _song(
  String title,
  String artist,
  String album,
  int track, {
  String? albumArtist,
}) => AudioMetadata(
  title: title,
  artistName: artist,
  albumTitle: album,
  albumArtistName: albumArtist,
  durationSeconds: 200,
  trackNumber: track,
  discNumber: 1,
  isSingle: false,
  featuredArtists: const [],
);

void main() {
  sqfliteFfiInit();

  late Directory root;
  late _Device phoneA;
  late _Device phoneB;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_fresh_start_');
    phoneA = _Device(root, 'phone_a');
    phoneB = _Device(root, 'phone_b');
    await phoneA.install();
    await phoneB.install();
  });

  tearDown(() async {
    await phoneA.database.close();
    await phoneB.database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Steps 1–7 on phone A, through the real import, edition and chart
  /// services. Returns ids worth checking by name.
  Future<Map<String, String>> buildLibrary(_Device device) async {
    final db = await device.database.database;
    final files = {
      // A mixed-artist soundtrack folder: four performers, one album.
      for (final (n, artist) in [
        (1, 'Artist One'),
        (2, 'Artist Two'),
        (3, 'Artist Three'),
        (4, 'Artist Four'),
      ])
        '/music/Starstruck OST/0$n.mp3': _song(
          'Scene $n',
          artist,
          'Starstruck',
          n,
        ),
      // Standard and Deluxe folders of one album.
      for (final (n, title) in [(1, 'Home'), (2, 'Ribbon'), (3, 'Locket')])
        '/music/locket/0$n.mp3': _song(title, 'Madison Beer', 'locket', n),
      for (final (n, title) in [
        (1, 'Home'),
        (2, 'Ribbon'),
        (3, 'Locket'),
        (4, 'Bonus'),
      ])
        '/music/locket (Deluxe)/0$n.mp3': _song(
          title,
          'Madison Beer',
          'locket (Deluxe)',
          n,
        ),
    };

    final reader = _Tags(files);
    await ImportBatchExecutor(
      libraryImportService: LibraryImportService(
        metadataResolver: MetadataResolver(
          primaryReader: reader,
          fallbackReader: reader,
        ),
        atomicImporter: AtomicLibraryImporter(appDatabase: device.database),
        mediaFileBindingRepository: SqliteMediaFileBindingRepository(
          MediaFileBindingDao(db),
        ),
      ),
      batchRepository: SqliteImportBatchRepository(ImportBatchDao(db)),
    ).execute(
      ImportBatch(
        id: 'fresh-start-import',
        createdAt: _now,
        items: [
          for (final file in files.keys)
            ImportBatchItem(
              candidate: ImportCandidate(
                filePath: file,
                normalizedPath: file.toLowerCase(),
                discoveredAt: _now,
              ),
            ),
        ],
      ),
      startedAt: _now,
      completedAt: _now,
    );

    Future<String> id(String sql, [List<Object?> args = const []]) async =>
        (await db.rawQuery(sql, args)).single.values.single! as String;

    final soundtrack = await id(
      "SELECT id FROM ${DatabaseTables.albums} WHERE title = 'Starstruck'",
    );
    final locket = await id(
      "SELECT id FROM ${DatabaseTables.albums} WHERE title = 'locket'",
    );
    final madison = await id(
      "SELECT id FROM ${DatabaseTables.artists} WHERE name = 'Madison Beer'",
    );
    final deluxe = await id(
      "SELECT id FROM ${DatabaseTables.albumEditions} "
      "WHERE album_id = ? AND type = 'deluxe'",
      [locket],
    );
    final standard = await id(
      "SELECT id FROM ${DatabaseTables.albumEditions} "
      'WHERE album_id = ? AND is_primary = 1',
      [locket],
    );
    final home = await id(
      "SELECT id FROM ${DatabaseTables.songs} WHERE title = 'Home'",
    );

    // Step 3: a third edition through the real service, inheriting Standard.
    final runner = SyncMutationTransactionRunner(
      appDatabase: device.database,
      changes: LibraryChangeSignal(),
    );
    await AlbumEditionManagementService(mutationRunner: runner).createEdition(
      albumId: locket,
      title: 'locket (Anniversary)',
      type: AlbumEditionType.anniversary,
      includeSongsFrom: standard,
      now: _now,
    );

    // Step 4: distinct artwork, with crop positions for a cover and a
    // portrait. Real files, so the backup carries their bytes.
    final art = Directory(path.join(device.root.path, 'my_artwork'));
    await art.create();
    for (final (name, byte) in [
      ('standard', 1),
      ('deluxe-original', 2),
      ('deluxe-cropped', 3),
      ('banner', 4),
      ('portrait-cropped', 5),
    ]) {
      final file = File(path.join(art.path, '$name.png'));
      await file.writeAsBytes(List.filled(64, byte));
      await db.insert(DatabaseTables.artworkAssets, {
        'id': 'art-$name',
        'file_path': file.path,
        'normalized_path': file.path.replaceAll('\\', '/').toLowerCase(),
        'created_at': _now.toIso8601String(),
        'updated_at': _now.toIso8601String(),
      });
    }
    await db.update(
      DatabaseTables.albumEditions,
      {'artwork_id': 'art-standard'},
      where: 'id = ?',
      whereArgs: [standard],
    );
    await db.update(
      DatabaseTables.albumEditions,
      {'artwork_id': 'art-deluxe-cropped'},
      where: 'id = ?',
      whereArgs: [deluxe],
    );
    await db.update(
      DatabaseTables.artists,
      {
        'header_artwork_id': 'art-banner',
        'top_artists_artwork_id': 'art-portrait-cropped',
      },
      where: 'id = ?',
      whereArgs: [madison],
    );
    for (final (type, target, source, output, left) in [
      (
        'albumEdition',
        deluxe,
        'art-deluxe-original',
        'art-deluxe-cropped',
        0.1,
      ),
      ('artistPortrait', madison, 'art-banner', 'art-portrait-cropped', 0.25),
    ]) {
      await db.insert(DatabaseTables.artworkCrops, {
        'target_type': type,
        'target_id': target,
        'source_artwork_id': source,
        'output_artwork_id': output,
        'crop_left': left,
        'crop_top': 0.05,
        'crop_width': 0.6,
        'crop_height': 0.6,
        'created_at': _now.toIso8601String(),
        'updated_at': _now.toIso8601String(),
      });
    }

    // Step 5: soundtrack collaborators and user edits.
    await db.insert(DatabaseTables.albumReleaseClassifications, {
      'album_id': soundtrack,
      'kind': 'soundtrack',
      'authority': 'manual',
      'created_at': _now.toIso8601String(),
      'updated_at': _now.toIso8601String(),
    });
    for (final performer in await db.rawQuery(
      'SELECT DISTINCT artist_id FROM ${DatabaseTables.songs} '
      'WHERE album_id = ?',
      [soundtrack],
    )) {
      await db.insert(DatabaseTables.artistProjectAssignments, {
        'artist_id': performer['artist_id'],
        'album_id': soundtrack,
        'mode': 'grouped',
        'created_at': _now.toIso8601String(),
        'updated_at': _now.toIso8601String(),
      });
    }
    await db.update(
      DatabaseTables.songs,
      {'title': 'Home (Edited)'},
      where: 'id = ?',
      whereArgs: [home],
    );
    await db.insert(DatabaseTables.metadataFieldStates, {
      'entity_type': 'song',
      'entity_id': home,
      'field_name': 'title',
      'authority': 'manual',
      'source': 'user',
      'updated_at': _now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert(DatabaseTables.trackLyrics, {
      'song_id': home,
      'plain_text': 'My own lyrics',
      'created_at': _now.toIso8601String(),
      'updated_at': _now.toIso8601String(),
    });
    await db.update(DatabaseTables.songs, {
      'is_blocked': 1,
    }, where: "title = 'Scene 4'");

    // Step 6: a playlist and three weeks of qualified listening.
    final songs = await db.query(DatabaseTables.songs, orderBy: 'title');
    await db.insert(DatabaseTables.playlists, {
      'id': 'playlist-road-trip',
      'name': 'Road Trip',
      'created_at': _now.toIso8601String(),
      'updated_at': _now.toIso8601String(),
    });
    for (final (position, song) in songs.take(4).indexed) {
      await db.insert(DatabaseTables.playlistItems, {
        'id': 'item-$position',
        'playlist_id': 'playlist-road-trip',
        'song_id': song['id'],
        'position': position,
        'created_at': _now.toIso8601String(),
        'updated_at': _now.toIso8601String(),
      });
    }
    var plays = 0;
    for (final (index, song) in songs.indexed) {
      for (var week = 0; week < 3; week++) {
        for (var n = 0; n <= (index + week) % 4; n++) {
          final at = DateTime.utc(2026, 10, 5 + 7 * week, 10, plays % 60);
          final iso = at.toIso8601String();
          final playId = 'play-${plays++}';
          await db.insert(DatabaseTables.playbackSessions, {
            'id': 'session-$playId',
            'song_id': song['id'],
            'artist_id': song['artist_id'],
            'album_id': song['album_id'],
            'album_edition_id': song['album_edition_id'],
            'song_title': song['title'],
            'artist_name': 'Artist',
            'album_title': 'Album',
            'album_edition_title': 'Edition',
            'started_at': iso,
            'ended_at': iso,
            'listened_duration_ms': 200000,
            'track_duration_ms': 200000,
            'final_position_ms': 200000,
            'end_reason': 'completed',
            'created_at': iso,
            'updated_at': iso,
          });
          await db.insert(DatabaseTables.playbackListeningSegments, {
            'id': 'segment-$playId',
            'playback_session_id': 'session-$playId',
            'started_at': iso,
            'ended_at': iso,
            'listened_duration_ms': 200000,
            'created_at': iso,
            'updated_at': iso,
          });
          await db.insert(DatabaseTables.qualifiedPlays, {
            'id': playId,
            'playback_session_id': 'session-$playId',
            'song_id': song['id'],
            'artist_id': song['artist_id'],
            'album_id': song['album_id'],
            'album_edition_id': song['album_edition_id'],
            'qualified_at': iso,
            'listened_duration_ms': 200000,
            'track_duration_ms': 200000,
            'created_at': iso,
          });
        }
      }
    }

    // Step 7: finalized weekly charts, their Moments, and all-time Moments.
    final library = SqliteLibraryQueryRepository(LibraryQueryDao(db));
    final qualified = SqliteQualifiedPlayRepository(QualifiedPlayDao(db));
    final charts = SqliteChartRepository(device.database);
    final moments = SqliteChartMomentRepository(device.database);
    await ChartFinalizationService(
      builder: ChartSnapshotBuilderService(
        qualifiedPlays: qualified,
        library: library,
        charts: charts,
        playbackSessions: SqlitePlaybackSessionRepository(
          PlaybackSessionDao(db),
        ),
      ),
      charts: charts,
      qualifiedPlays: qualified,
      moments: moments,
      momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 1),
      now: () => _now,
    ).finalizeCompletedWeeks(referenceLocal: _now.toLocal());
    await AllTimeMomentService(
      qualifiedPlays: qualified,
      library: library,
      moments: moments,
      activationUtc: DateTime.utc(2026, 9, 1),
      now: () => _now,
    ).record(referenceLocal: _now.toLocal());

    return {'deluxe': deluxe, 'madison': madison, 'soundtrack': soundtrack};
  }

  Future<Map<String, List<Map<String, Object?>>>> portableRows(
    _Device device,
  ) async {
    final db = await device.database.database;
    return {
      for (final coverage in BackupCoverageContract.portableTables)
        coverage.table: [
          for (final row in await db.rawQuery(
            'SELECT * FROM "${coverage.table}" ORDER BY rowid',
          ))
            {
              for (final entry in row.entries)
                // Artwork lives at a new path on the new phone.
                if (coverage.table != DatabaseTables.artworkAssets ||
                    (entry.key != 'file_path' &&
                        entry.key != 'normalized_path'))
                  entry.key: entry.value,
            },
        ],
    };
  }

  Future<AllTimeChart> allTime(_Device device, ChartType type) async {
    final db = await device.database.database;
    return AllTimeChartService(
      qualifiedPlays: SqliteQualifiedPlayRepository(QualifiedPlayDao(db)),
      library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
    ).load(
      chartType: type,
      referenceLocal: _now.toLocal(),
      viewSize: ChartViewSize.top200,
    );
  }

  test(
    'a clean reinstall restores everything the backup is meant to keep',
    () async {
      final ids = await buildLibrary(phoneA);
      final dbA = await phoneA.database.database;

      // The library is representative before anything is compared.
      final before = await portableRows(phoneA);
      for (final table in BackupCoverageContract.portableTableNames) {
        expect(before[table], isNotEmpty, reason: '$table should have data');
      }
      expect(
        (await dbA.query(
          DatabaseTables.chartMomentEvents,
          where: "scope = 'allTime'",
        )),
        isNotEmpty,
      );

      // Step 8: back up on phone A, saved off the device and read back.
      final controllerA = await phoneA.backupRestore();
      addTearDown(controllerA.dispose);
      await controllerA.createBackup();
      final saved = (await phoneA.downloads.list().toList())
          .whereType<File>()
          .single;

      // Step 9: a fresh installation restores the saved file.
      phoneB.picker.backup = await saved.copy(
        path.join(phoneB.downloads.path, path.basename(saved.path)),
      );
      final controllerB = await phoneB.backupRestore();
      addTearDown(controllerB.dispose);
      await controllerB.chooseBackupToRestore();
      expect(controllerB.preview!.canRestore, isTrue);
      await controllerB.confirmRestore(acknowledged: true);
      expect(controllerB.restoreResult, isNotNull);

      // Step 10: completeness and identity, record for record.
      final after = await portableRows(phoneB);
      for (final table in BackupCoverageContract.portableTableNames) {
        expect(after[table], unorderedEquals(before[table]!), reason: table);
      }

      // No duplicates, no broken references, a sound database.
      final dbB = await phoneB.database.database;
      for (final table in BackupCoverageContract.portableTableNames) {
        final keys = await dbB.rawQuery('PRAGMA table_info("$table")');
        final pk = [
          for (final c in keys)
            if ((c['pk'] as int) > 0) '"${c['name']}"',
        ];
        final distinct = await dbB.rawQuery(
          'SELECT COUNT(*) AS n FROM (SELECT DISTINCT ${pk.join(', ')} '
          'FROM "$table")',
        );
        expect(distinct.single['n'], after[table]!.length, reason: table);
      }
      expect(await dbB.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await dbB.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );

      // Artwork bytes arrived intact, at paths owned by the new phone.
      for (final asset in await dbB.query(DatabaseTables.artworkAssets)) {
        final restored = File(asset['file_path']! as String);
        final original = File(
          (await dbA.query(
                DatabaseTables.artworkAssets,
                where: 'id = ?',
                whereArgs: [asset['id']],
              )).single['file_path']!
              as String,
        );
        expect(path.isWithin(phoneB.support.path, restored.path), isTrue);
        expect(await restored.readAsBytes(), await original.readAsBytes());
      }

      // Crops and soundtrack organization by name, as a person would check.
      final crops = await dbB.query(DatabaseTables.artworkCrops);
      expect(
        crops.firstWhere((c) => c['target_id'] == ids['deluxe'])['crop_left'],
        0.1,
      );
      expect(
        crops.firstWhere((c) => c['target_id'] == ids['madison'])['crop_left'],
        0.25,
      );
      expect(
        (await dbB.query(
          DatabaseTables.albumReleaseClassifications,
        )).single['album_id'],
        ids['soundtrack'],
      );
      expect(
        await dbB.query(DatabaseTables.artistProjectAssignments),
        hasLength(4),
      );

      // The computed charts come out the same: standings, streams, weekly
      // change and weeks in zones.
      for (final type in ChartType.values) {
        final a = await allTime(phoneA, type);
        final b = await allTime(phoneB, type);
        expect(
          [
            for (final e in b.entries)
              (e.entity.entityId, e.rank, e.qualifiedStreamCount, e.peakRank),
          ],
          [
            for (final e in a.entries)
              (e.entity.entityId, e.rank, e.qualifiedStreamCount, e.peakRank),
          ],
          reason: type.name,
        );
        for (final entry in a.entries) {
          final sa = a.statsFor(entry);
          final sb = b.statsFor(entry);
          expect(sb.streamsThisWeek, sa.streamsThisWeek);
          expect(sb.streamsSameTimeLastWeek, sa.streamsSameTimeLastWeek);
          for (final zone in [3, 10, 100]) {
            expect(sb.zones.weeksIn(zone), sa.zones.weeksIn(zone));
          }
        }
      }

      // What a clean reinstall leaves behind, by design: audio file links
      // (the music must be re-linked), import history and review queue.
      for (final table in [
        DatabaseTables.mediaFileBindings,
        DatabaseTables.importBatches,
      ]) {
        expect(await dbA.query(table), isNotEmpty, reason: table);
        expect(await dbB.query(table), isEmpty, reason: table);
      }
    },
  );
}
