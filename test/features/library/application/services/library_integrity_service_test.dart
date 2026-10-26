import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/library/application/models/library_health_report.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/library_integrity_service.dart';
import 'package:sonus_next/features/library/data/daos/library_integrity_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late LibraryIntegrityService integrity;
  final missingFiles = <String>{};
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() async {
    missingFiles.clear();
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    var outbox = 0;
    integrity = LibraryIntegrityService(
      dao: LibraryIntegrityDao(await appDatabase.database),
      editions: AlbumEditionManagementService(
        mutationRunner: SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          generateId: () => 'outbox_${++outbox}',
          now: () => now,
        ),
      ),
      fileExists: (path) async => !missingFiles.contains(path),
      now: () => now,
    );
  });

  tearDown(() => appDatabase.close());

  Future<String> importTrack(
    String title,
    int track, {
    int seconds = 180,
    bool statedFormat = true,
  }) async {
    final path = 'Artist/Album/$title.mp3';
    final result = await AtomicLibraryImporter(appDatabase: appDatabase).import(
      candidate: ImportCandidate(
        filePath: path,
        normalizedPath: path.toLowerCase(),
        discoveredAt: now,
      ),
      metadata: AudioMetadata(
        title: title,
        artistName: 'Artist',
        albumTitle: 'Album',
        durationSeconds: seconds,
        trackNumber: track,
        discNumber: 1,
        isSingle: false,
        featuredArtists: const [],
      ),
      now: now,
    );
    if (statedFormat) {
      // The fixture album is short; its format is stated so that only the
      // check under test reports anything.
      await (await appDatabase.database).rawInsert(
        'INSERT OR IGNORE INTO ${DatabaseTables.albumReleaseClassifications} '
        '(album_id, format, format_authority, created_at, updated_at) '
        "SELECT album_id, 'album', 'manual', ?, ? FROM "
        '${DatabaseTables.songs} WHERE id = ?',
        [now.toIso8601String(), now.toIso8601String(), result.songId],
      );
    }
    return result.songId!;
  }

  Future<Map<String, List<Map<String, Object?>>>> everyRow() async {
    final db = await appDatabase.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return {
      for (final table in tables)
        table['name']! as String: await db.query(table['name']! as String),
    };
  }

  HealthFinding finding(LibraryHealthReport report, HealthCheck check) =>
      report.findings.firstWhere((f) => f.check == check);

  test('a clean import verifies, with its counts', () async {
    await importTrack('One', 1);
    await importTrack('Two', 2);

    final report = await integrity.verify(
      importCounts: const ImportHealthCounts(
        imported: 2,
        relinked: 0,
        skipped: 0,
        failed: 0,
      ),
    );

    expect(report.songCount, 2);
    expect(report.isHealthy, isTrue);
    expect(report.withSeverity(HealthSeverity.needsReview), isEmpty);
    expect(report.withSeverity(HealthSeverity.safeCorrection), isEmpty);
    expect(report.importCounts?.imported, 2);
    expect(
      finding(report, HealthCheck.playableFiles).severity,
      HealthSeverity.verified,
    );
  });

  test('verifying writes nothing and gives the same answer twice', () async {
    await importTrack('One', 1);
    final before = await everyRow();

    final first = await integrity.verify();
    final second = await integrity.verify();

    expect(await everyRow(), before);
    expect(
      second.findings.map((f) => (f.check, f.severity, f.entityIds)),
      first.findings.map((f) => (f.check, f.severity, f.entityIds)),
    );
  });

  group('release formats', () {
    test('a short release with no stated format is listed for review, '
        'never guessed', () async {
      await importTrack('One', 1, statedFormat: false);
      await importTrack('Two', 2, statedFormat: false);
      final before = await everyRow();

      final report = await integrity.verify();
      final formats = finding(report, HealthCheck.releaseFormats);
      expect(formats.severity, HealthSeverity.needsReview);
      expect(formats.summary, contains('might be a Single'));
      expect(
        [
          for (final r in formats.formatReviews)
            (r.title, r.owner, r.songCount),
        ],
        [('Album', 'Artist', 2)],
      );
      expect(await everyRow(), before, reason: 'verifying writes nothing');
    });

    test(
      'a stated format clears it, and is not counted as a soundtrack',
      () async {
        await importTrack('One', 1);

        final report = await integrity.verify();
        expect(
          finding(report, HealthCheck.releaseFormats).severity,
          HealthSeverity.verified,
        );
        expect(
          finding(report, HealthCheck.soundtrackOrganization).summary,
          'No albums are classified as soundtracks or compilations yet.',
        );
      },
    );
  });

  group('finds', () {
    test('a collapsed or duplicated recording for review', () async {
      final one = await importTrack('One', 1);
      final db = await appDatabase.database;
      final song = (await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: [one],
      )).single;
      // A copy of the same recording, as an older import could leave.
      await db.insert(DatabaseTables.songs, {...song, 'id': 'song-copy'});

      final report = await integrity.verify();
      final duplicates = finding(report, HealthCheck.duplicateRecordings);

      expect(duplicates.severity, HealthSeverity.needsReview);
      expect(duplicates.entityIds.single, contains('song-copy'));
      expect(report.isHealthy, isFalse);
    });

    test('missing audio and artwork files as warnings', () async {
      final one = await importTrack('One', 1);
      final db = await appDatabase.database;
      await db.update(
        DatabaseTables.mediaFileBindings,
        {'is_available': 0},
        where: 'song_id = ?',
        whereArgs: [one],
      );
      await db.insert(DatabaseTables.artworkAssets, {
        'id': 'art-1',
        'file_path': '/gone.jpg',
        'normalized_path': '/gone.jpg',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      missingFiles.add('/gone.jpg');

      final report = await integrity.verify();

      expect(finding(report, HealthCheck.playableFiles).entityIds, [one]);
      expect(finding(report, HealthCheck.artworkFiles).entityIds, ['art-1']);
      expect(report.isHealthy, isTrue, reason: 'warnings only');
    });
  });

  group('safe corrections', () {
    test('are offered, applied only on request, and then verify', () async {
      final one = await importTrack('One', 1);
      final db = await appDatabase.database;
      await db.update(DatabaseTables.albumEditions, {'is_primary': 0});
      await db.delete(
        DatabaseTables.albumEditionTracks,
        where: 'song_id = ?',
        whereArgs: [one],
      );

      final report = await integrity.verify();
      final primary = finding(report, HealthCheck.primaryEdition);
      final listing = finding(report, HealthCheck.editionListings);

      expect(primary.severity, HealthSeverity.safeCorrection);
      expect(listing.severity, HealthSeverity.safeCorrection);
      expect(listing.entityIds, [one]);

      // Nothing was corrected by verifying.
      expect(
        (await integrity.verify()).findings.map((f) => f.severity),
        report.findings.map((f) => f.severity),
      );

      for (final correction in [
        ...primary.corrections,
        ...listing.corrections,
      ]) {
        await integrity.applyCorrection(correction);
      }

      final after = await integrity.verify();
      expect(after.withSeverity(HealthSeverity.safeCorrection), isEmpty);
      expect(after.isHealthy, isTrue);
    });

    test('several primary editions need review, not a guess', () async {
      await importTrack('One', 1);
      final db = await appDatabase.database;
      final edition = (await db.query(DatabaseTables.albumEditions)).single;
      await db.insert(DatabaseTables.albumEditions, {
        ...edition,
        'id': 'edition-2',
        'title': 'Album (Deluxe)',
      });

      final primary = finding(
        await integrity.verify(),
        HealthCheck.primaryEdition,
      );

      expect(primary.severity, HealthSeverity.needsReview);
      expect(primary.corrections, isEmpty);
    });
  });

  group('SN-45 split folders (preview only)', () {
    Future<void> legacyImport(String path, String title, String artist) {
      // Without a folder placement, as imports before SN-45 worked.
      return AtomicLibraryImporter(appDatabase: appDatabase).import(
        candidate: ImportCandidate(
          filePath: path,
          normalizedPath: path.toLowerCase(),
          discoveredAt: now,
        ),
        metadata: AudioMetadata(
          title: title,
          artistName: artist,
          albumTitle: 'Starstruck',
          durationSeconds: 180,
          trackNumber: 1,
          discNumber: 1,
          isSingle: false,
          featuredArtists: const [],
        ),
        now: now,
      );
    }

    HealthFinding splitFinding(LibraryHealthReport report) =>
        report.findings.singleWhere((f) => f.check == HealthCheck.splitFolders);

    test('a folder split by artist tags is reported with its albums', () async {
      await legacyImport('/m/Starstruck/1.mp3', 'A', 'Artist 1');
      await legacyImport('/m/Starstruck/2.mp3', 'B', 'Artist 2');
      await legacyImport('/m/Starstruck/3.mp3', 'C', 'Artist 2');

      final finding = splitFinding(await integrity.verify());

      expect(finding.severity, HealthSeverity.warning);
      expect(finding.folderSplits.single.folderName, 'Starstruck');
      expect(
        finding.folderSplits.single.albums.map((a) => (a.owner, a.songCount)),
        [('Artist 2', 2), ('Artist 1', 1)],
      );
      expect(finding.corrections, isEmpty, reason: 'never merged here');
    });

    test('checking changes nothing', () async {
      await legacyImport('/m/Starstruck/1.mp3', 'A', 'Artist 1');
      await legacyImport('/m/Starstruck/2.mp3', 'B', 'Artist 2');
      final db = await appDatabase.database;
      Future<List<Object?>> snapshot() async => [
        await db.query(DatabaseTables.albums, orderBy: 'id'),
        await db.query(DatabaseTables.songs, orderBy: 'id'),
        await db.query(DatabaseTables.syncOutbox),
      ];
      final before = await snapshot();

      await integrity.verify();

      expect(await snapshot(), before);
    });

    test('one album per folder is verified', () async {
      await legacyImport('/m/locket/1.mp3', 'A', 'Madison Beer');
      await legacyImport('/m/locket/2.mp3', 'B', 'Madison Beer');

      final finding = splitFinding(await integrity.verify());
      expect(finding.severity, HealthSeverity.verified);
    });
  });
}
