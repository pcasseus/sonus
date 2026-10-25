// J3 / Studio-1: Album Studio and Album Profile listed tracks in the order
// files were discovered, because ordering used sort_position first and
// import appends each new track at the end.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late AlbumEditionTrackOrderingService ordering;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    var outbox = 0;
    ordering = AlbumEditionTrackOrderingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++outbox}',
        now: () => now,
      ),
    );
  });

  tearDown(() => appDatabase.close());

  /// Imports [tracks] (title, disc, track) in the given discovery order and
  /// returns the edition id.
  Future<String> importInOrder(List<(String, int, int)> tracks) async {
    final importer = AtomicLibraryImporter(appDatabase: appDatabase);
    String? editionId;

    for (final (title, disc, track) in tracks) {
      final path = 'Artist/Album/$title.mp3';
      final result = await importer.import(
        candidate: ImportCandidate(
          filePath: path,
          normalizedPath: path.toLowerCase(),
          discoveredAt: now,
        ),
        metadata: AudioMetadata(
          title: title,
          artistName: 'Artist',
          albumTitle: 'Album',
          durationSeconds: 180,
          trackNumber: track,
          discNumber: disc,
          isSingle: false,
          featuredArtists: const [],
        ),
        metadataSource: MetadataSource.embedded,
        now: now,
      );
      final db = await appDatabase.database;
      final row = await db.query(
        DatabaseTables.songs,
        columns: ['album_edition_id'],
        where: 'id = ?',
        whereArgs: [result.songId],
      );
      editionId = row.single['album_edition_id']! as String;
    }

    return editionId!;
  }

  Future<List<String>> listed(String editionId) async {
    final db = await appDatabase.database;
    final tracks = await LibraryQueryDao(
      db,
    ).findTracksByAlbumEditionId(editionId);
    final memberships = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(editionId);
    final titles = tracks.map((t) => t.title).toList();
    final membershipOrder = [
      for (final m in memberships)
        tracks.firstWhere((t) => t.songId == m.songId).title,
    ];
    expect(membershipOrder, titles, reason: 'both listings agree');
    return titles;
  }

  Future<String> songIdOf(String editionId, String title) async {
    final db = await appDatabase.database;
    final tracks = await LibraryQueryDao(
      db,
    ).findTracksByAlbumEditionId(editionId);
    return tracks.firstWhere((t) => t.title == title).songId;
  }

  test('tracks list by track number, not discovery order', () async {
    final edition = await importInOrder([
      ('Three', 1, 3),
      ('One', 1, 1),
      ('Two', 1, 2),
    ]);

    expect(await listed(edition), ['One', 'Two', 'Three']);
  });

  test('discs come in order, each by track number', () async {
    final edition = await importInOrder([
      ('2-1', 2, 1),
      ('1-2', 1, 2),
      ('2-2', 2, 2),
      ('1-1', 1, 1),
    ]);

    expect(await listed(edition), ['1-1', '1-2', '2-1', '2-2']);
  });

  test(
    'unknown track numbers follow the numbered tracks of their disc',
    () async {
      final edition = await importInOrder([
        ('Unnumbered', 1, 0),
        ('Two', 1, 2),
        ('One', 1, 1),
      ]);

      expect(await listed(edition), ['One', 'Two', 'Unnumbered']);
    },
  );

  test('a renumbered track moves to its new place', () async {
    final edition = await importInOrder([
      ('One', 1, 1),
      ('Two', 1, 2),
      ('Three', 1, 3),
    ]);

    await ordering.updateTrackPlacement(
      userId: null,
      albumEditionId: edition,
      songId: await songIdOf(edition, 'One'),
      discNumber: 1,
      trackNumber: 4,
      now: now,
    );

    expect(await listed(edition), ['Two', 'Three', 'One']);
  });

  group('deliberate manual order', () {
    Future<String> manuallyOrdered() async {
      final edition = await importInOrder([
        ('One', 1, 1),
        ('Two', 1, 2),
        ('Three', 1, 3),
      ]);
      await ordering.reorderEdition(
        albumEditionId: edition,
        orderedSongIds: [
          await songIdOf(edition, 'Three'),
          await songIdOf(edition, 'One'),
          await songIdOf(edition, 'Two'),
        ],
        now: now,
      );
      return edition;
    }

    test('is kept', () async {
      final edition = await manuallyOrdered();

      expect(await listed(edition), ['Three', 'One', 'Two']);
    });

    test('survives a renumbering and a new track', () async {
      final edition = await manuallyOrdered();

      await ordering.updateTrackPlacement(
        userId: null,
        albumEditionId: edition,
        songId: await songIdOf(edition, 'Three'),
        discNumber: 1,
        trackNumber: 9,
        now: now,
      );
      await importInOrder([('Bonus', 1, 4)]);

      expect(await listed(edition), ['Three', 'One', 'Two', 'Bonus']);
    });

    test('"Sort by disc & track" restores automatic order', () async {
      final edition = await manuallyOrdered();

      final result = await ordering.sortByDiscAndTrack(
        albumEditionId: edition,
        now: now,
      );

      expect(result.changed, isTrue);
      expect(await listed(edition), ['One', 'Two', 'Three']);

      final db = await appDatabase.database;
      final memberships = await AlbumEditionTrackDao(
        db,
      ).findByEditionId(edition);
      expect(
        memberships.map((m) => m.orderingAuthority),
        everyElement(AlbumEditionTrackAuthority.inferred),
      );

      // From now on the edition follows its numbers again.
      await ordering.updateTrackPlacement(
        userId: null,
        albumEditionId: edition,
        songId: await songIdOf(edition, 'One'),
        discNumber: 1,
        trackNumber: 4,
        now: now,
      );
      expect(await listed(edition), ['Two', 'Three', 'One']);
    });

    test(
      '"Sort by disc & track" twice changes nothing the second time',
      () async {
        final edition = await manuallyOrdered();

        await ordering.sortByDiscAndTrack(albumEditionId: edition, now: now);
        final second = await ordering.sortByDiscAndTrack(
          albumEditionId: edition,
          now: now,
        );

        expect(second.changed, isFalse);
      },
    );
  });

  test(
    'libraries imported before the fix list correctly without a rewrite',
    () async {
      final edition = await importInOrder([
        ('Three', 1, 3),
        ('One', 1, 1),
        ('Two', 1, 2),
      ]);
      final db = await appDatabase.database;
      final before = await db.query(DatabaseTables.albumEditionTracks);

      expect(await listed(edition), ['One', 'Two', 'Three']);

      // Reading the order writes nothing: stored rows are untouched.
      expect(await db.query(DatabaseTables.albumEditionTracks), before);
    },
  );
}
