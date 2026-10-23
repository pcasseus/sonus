import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/application/services/import_source_reconciliation_service.dart';
import 'package:sonus_next/features/import/data/daos/import_source_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/import_source.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late ImportSourceReconciliationService service;

  final initial = DateTime.utc(2026, 10, 23);
  final snapshot = initial.add(const Duration(minutes: 1));
  final scanned = initial.add(const Duration(minutes: 5));

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    service = ImportSourceReconciliationService(appDatabase: database);

    await database.transaction((tx) async {
      // The binding's song must exist; foreign keys stay enforced.
      await ArtistDao(tx).insert(
        Artist(
          id: 'artist_1',
          name: 'Artist',
          canonicalName: 'artist',
          createdAt: initial,
          updatedAt: initial,
        ),
      );
      await AlbumDao(tx).insert(
        Album(
          id: 'album_1',
          artistId: 'artist_1',
          title: 'Album',
          canonicalTitle: 'album',
          createdAt: initial,
          updatedAt: initial,
        ),
      );
      await AlbumEditionDao(tx).insert(
        AlbumEdition(
          id: 'edition_1',
          albumId: 'album_1',
          title: 'Album',
          type: AlbumEditionType.standard,
          isPrimary: true,
          createdAt: initial,
          updatedAt: initial,
        ),
      );
      await SongDao(tx).insert(
        Song(
          id: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_1',
          title: 'Song',
          canonicalTitle: 'song',
          trackNumber: 1,
          durationSeconds: 180,
          isSingle: false,
          featuredArtists: const [],
          createdAt: initial,
          updatedAt: initial,
        ),
      );
      await ImportSourceDao(tx).insert(
        ImportSource(
          id: 'source_1',
          rootPath: 'C:/Music',
          normalizedRootPath: 'c:/music',
          createdAt: initial,
          updatedAt: initial,
        ),
      );
      await MediaFileBindingDao(tx).insert(
        MediaFileBinding(
          id: 'binding_1',
          songId: 'song_1',
          filePath: 'C:/Music/song.mp3',
          normalizedPath: 'c:/music/song.mp3',
          sourceId: 'source_1',
          isAvailable: true,
          createdAt: initial,
          updatedAt: initial,
        ),
      );
    });
  });

  tearDown(() async {
    await database.close();
  });

  Future<ImportSource?> readSource() async {
    return ImportSourceDao(await database.database).findById('source_1');
  }

  Future<MediaFileBinding?> readBinding() async {
    return MediaFileBindingDao(await database.database).findById('binding_1');
  }

  test('commits updates before notifying playback', () async {
    var callbackCount = 0;

    await service.reconcile(
      sourceId: 'source_1',
      seenPaths: <String>{},
      discoveredAt: snapshot,
      scannedAt: scanned,
      onSongsBecameUnavailable: (ids) async {
        callbackCount++;
        expect(database.mutationCoordinator.activeMutations, 0);
        expect(ids, {'song_1'});
        expect((await readBinding())?.isAvailable, isFalse);
        expect((await readSource())?.lastScannedAt, scanned);
      },
    );

    expect(callbackCount, 1);
  });

  test('preserves seen paths and advances source timestamp', () async {
    await service.reconcile(
      sourceId: 'source_1',
      seenPaths: {'c:/music/song.mp3'},
      discoveredAt: snapshot,
      scannedAt: scanned,
    );

    expect((await readBinding())?.isAvailable, isTrue);
    expect((await readSource())?.lastScannedAt, scanned);
  });

  test('rolls back binding changes if source update fails', () async {
    final db = await database.database;

    await db.execute('''
      CREATE TRIGGER reject_source_scan
      BEFORE UPDATE ON import_sources
      BEGIN
        SELECT RAISE(ABORT, 'test rejection');
      END
    ''');

    var notified = false;

    await expectLater(
      service.reconcile(
        sourceId: 'source_1',
        seenPaths: <String>{},
        discoveredAt: snapshot,
        scannedAt: scanned,
        onSongsBecameUnavailable: (_) async {
          notified = true;
        },
      ),
      throwsA(isA<Exception>()),
    );

    expect((await readBinding())?.isAvailable, isTrue);
    expect((await readSource())?.lastScannedAt, isNull);
    expect(notified, isFalse);
  });

  test('restore admission rejects the entire reconciliation', () async {
    final entered = Completer<void>();
    final release = Completer<void>();

    final exclusive = database.mutationCoordinator.runExclusiveRestore(
      () async {
        entered.complete();
        await release.future;
      },
    );

    await entered.future;
    var notified = false;

    try {
      await expectLater(
        service.reconcile(
          sourceId: 'source_1',
          seenPaths: <String>{},
          discoveredAt: snapshot,
          scannedAt: scanned,
          onSongsBecameUnavailable: (_) async {
            notified = true;
          },
        ),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      expect((await readBinding())?.isAvailable, isTrue);
      expect((await readSource())?.lastScannedAt, isNull);
      expect(notified, isFalse);
    } finally {
      release.complete();
      await exclusive;
    }
  });

  test('older scans do not overwrite newer results', () async {
    final newer = scanned.add(const Duration(minutes: 10));

    await service.reconcile(
      sourceId: 'source_1',
      seenPaths: {'c:/music/song.mp3'},
      discoveredAt: newer,
      scannedAt: newer,
    );

    await service.reconcile(
      sourceId: 'source_1',
      seenPaths: <String>{},
      discoveredAt: snapshot,
      scannedAt: scanned,
    );

    expect((await readBinding())?.isAvailable, isTrue);
    expect((await readSource())?.lastScannedAt, newer);
  });

  group('overlapping scans', () {
    // A newer scan imported a file the older scan's snapshot never saw.
    Future<void> newerScanAddsBinding(DateTime importedAt) async {
      await MediaFileBindingDao(await database.database).insert(
        MediaFileBinding(
          id: 'binding_2',
          songId: 'song_1',
          filePath: 'C:/Music/new.mp3',
          normalizedPath: 'c:/music/new.mp3',
          sourceId: 'source_1',
          isAvailable: true,
          createdAt: importedAt,
          updatedAt: importedAt,
        ),
      );
    }

    Future<MediaFileBinding?> readNewBinding() async {
      return MediaFileBindingDao(await database.database).findById('binding_2');
    }

    test('an older snapshot finishing later never hides newer files', () async {
      // Older scan: snapshot at +1m. Newer scan: snapshot and import at +2m,
      // reconciled at +3m. The older scan completes last, at +5m.
      final newerImport = initial.add(const Duration(minutes: 2));
      await newerScanAddsBinding(newerImport);

      await service.reconcile(
        sourceId: 'source_1',
        seenPaths: {'c:/music/song.mp3', 'c:/music/new.mp3'},
        discoveredAt: newerImport,
        scannedAt: initial.add(const Duration(minutes: 3)),
      );

      var notified = false;
      await service.reconcile(
        sourceId: 'source_1',
        seenPaths: {'c:/music/song.mp3'},
        discoveredAt: snapshot,
        scannedAt: scanned,
        onSongsBecameUnavailable: (_) async => notified = true,
      );

      expect((await readNewBinding())?.isAvailable, isTrue);
      expect((await readBinding())?.isAvailable, isTrue);
      expect(notified, isFalse);
    });

    test(
      'a binding unchanged since the snapshot is still reconciled',
      () async {
        await newerScanAddsBinding(initial);

        await service.reconcile(
          sourceId: 'source_1',
          seenPaths: {'c:/music/song.mp3'},
          discoveredAt: snapshot,
          scannedAt: scanned,
        );

        expect((await readNewBinding())?.isAvailable, isFalse);
        expect((await readNewBinding())?.updatedAt, scanned);
        expect((await readBinding())?.isAvailable, isTrue);
      },
    );
  });
}
