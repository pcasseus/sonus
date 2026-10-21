import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase appDatabase;
  late SonusBackupOrchestrator orchestrator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_backup_integration_');

    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    orchestrator = SonusBackupOrchestrator(
      exporter: SqliteBackupExporter(
        appDatabase: appDatabase,
        generateId: () => 'integration-backup',
        now: () => DateTime.utc(2026, 10, 21),
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> expectNoTemporaryBackupDirectories() async {
    final children = await root.list().toList();

    expect(
      children.where((entity) {
        final name = path.basename(entity.path);
        return name.startsWith('.sonus_backup_stage_') ||
            name.startsWith('.sonus_verified_');
      }),
      isEmpty,
    );
  }

  test('exports an empty SQLite database into a verified backup', () async {
    final destination = File(path.join(root.path, 'empty.sonusbackup'));

    final result = await orchestrator.createBackup(destination: destination);

    expect(result.path, destination.path);
    expect(await destination.exists(), isTrue);
    expect(await destination.length(), greaterThan(0));

    final decoded = await const BackupArchiveVerifier().verify(destination);

    expect(decoded.manifest.backupId, 'integration-backup');
    expect(decoded.payload.tables.length, 17);
    expect(decoded.payload.totalRows, 0);
    expect(decoded.manifest.totalRows, 0);

    await expectNoTemporaryBackupDirectories();
  });

  test('preserves SQLite records and managed artwork', () async {
    const timestamp = '2026-10-21T00:00:00.000Z';

    final artwork = File(path.join(root.path, 'original-cover.jpg'));

    const artworkBytes = <int>[255, 216, 255, 224, 10, 20, 30, 40, 255, 217];

    await artwork.writeAsBytes(artworkBytes);

    final db = await appDatabase.database;

    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'artwork-original',
      'file_path': artwork.path,
      'normalized_path': artwork.path,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.artists, {
      'id': 'artist-original',
      'name': 'Original Artist',
      'canonical_name': 'original artist',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album-original',
      'artist_id': 'artist-original',
      'title': 'Original Album',
      'canonical_title': 'original album',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition-original',
      'album_id': 'album-original',
      'title': 'Standard Edition',
      'type': 'standard',
      'is_primary': 1,
      'artwork_id': 'artwork-original',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert(DatabaseTables.playlists, {
      'id': 'playlist-original',
      'name': 'My Favorites',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    final destination = File(path.join(root.path, 'populated.sonusbackup'));

    await orchestrator.createBackup(destination: destination);

    final decoded = await const BackupArchiveVerifier().verify(destination);

    final artworkRows = decoded.payload.tables[DatabaseTables.artworkAssets]!;
    final artists = decoded.payload.tables[DatabaseTables.artists]!;
    final albums = decoded.payload.tables[DatabaseTables.albums]!;
    final editions = decoded.payload.tables[DatabaseTables.albumEditions]!;
    final playlists = decoded.payload.tables[DatabaseTables.playlists]!;

    expect(decoded.payload.totalRows, 5);

    expect(artworkRows.single['id'], 'artwork-original');
    expect(artists.single['id'], 'artist-original');
    expect(albums.single['id'], 'album-original');
    expect(albums.single['artist_id'], 'artist-original');
    expect(editions.single['id'], 'edition-original');
    expect(editions.single['album_id'], 'album-original');
    expect(editions.single['artwork_id'], 'artwork-original');
    expect(playlists.single['id'], 'playlist-original');

    expect(decoded.manifest.rowCounts[DatabaseTables.artworkAssets], 1);
    expect(decoded.manifest.rowCounts[DatabaseTables.artists], 1);
    expect(decoded.manifest.rowCounts[DatabaseTables.albums], 1);
    expect(decoded.manifest.rowCounts[DatabaseTables.playlists], 1);

    expect(await destination.exists(), isTrue);

    final archiveInput = InputFileStream(destination.path);

    try {
      final archive = ZipDecoder().decodeStream(archiveInput);
      final artworkHash = sha256
          .convert(utf8.encode('artwork-original'))
          .toString();
      final artworkEntry = archive.find('artwork/$artworkHash.jpg');

      expect(artworkEntry, isNotNull);

      final archivedBytes = artworkEntry!.readBytes();

      expect(
        archivedBytes,
        artworkBytes,
        reason: 'Archived artwork bytes differ from source artwork.',
      );
    } finally {
      await archiveInput.close();
    }
    await expectNoTemporaryBackupDirectories();
  });

  test('missing artwork prevents publication and cleans staging', () async {
    const timestamp = '2026-10-21T00:00:00.000Z';

    final missingPath = path.join(root.path, 'missing-cover.jpg');

    final db = await appDatabase.database;

    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'missing-artwork',
      'file_path': missingPath,
      'normalized_path': missingPath,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    final destination = File(
      path.join(root.path, 'should-not-exist.sonusbackup'),
    );

    await expectLater(
      orchestrator.createBackup(destination: destination),
      throwsFormatException,
    );

    expect(await destination.exists(), isFalse);

    await expectNoTemporaryBackupDirectories();
  });
}
