// SN-50 §5 Option B: files kept out of the library as possible different
// recordings wait in a device-local list for the user's decision.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/application/services/possible_recording_review_service.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/data/services/possible_recording_store.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding_factory.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/pending_possible_recording.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';

class _MetadataByPath implements AudioMetadataReader {
  _MetadataByPath(this.byPath);

  final Map<String, AudioMetadata> byPath;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    final metadata = byPath[candidate.filePath];
    if (metadata == null) throw StateError('file is missing');
    return metadata;
  }
}

class _Unreadable implements AudioMetadataReader {
  @override
  Future<AudioMetadata> read(ImportCandidate candidate) =>
      throw StateError('no fallback');
}

/// Answers as if one song had been deleted.
class _WithoutSong implements SongRepository {
  _WithoutSong(this.inner, this.deletedId);

  final SongRepository inner;
  final String deletedId;

  @override
  Future<Song?> getById(String id) async =>
      id == deletedId ? null : inner.getById(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Map<String, String> preferences;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    preferences = {};
  });

  tearDown(() => appDatabase.close());

  AudioMetadata errTime({required int seconds, int trackNumber = 1}) {
    return AudioMetadata(
      title: 'ErrTime',
      artistName: 'Fictional Harbour',
      albumTitle: 'Quiet Rooms',
      durationSeconds: seconds,
      trackNumber: trackNumber,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }

  ImportCandidate candidate(String path) {
    return ImportCandidate(
      filePath: path,
      normalizedPath: TextNormalizer.normalizePath(path),
      discoveredAt: now,
    );
  }

  PossibleRecordingStore store() {
    return PossibleRecordingStore.forTesting(
      getString: (key) async => preferences[key],
      setString: (key, value) async => preferences[key] = value,
    );
  }

  Future<LibraryImportService> importService(
    Map<String, AudioMetadata> files,
  ) async {
    final db = await appDatabase.database;

    return LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: _MetadataByPath(files),
        fallbackReader: _Unreadable(),
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
      mediaFileBindingRepository: SqliteMediaFileBindingRepository(
        MediaFileBindingDao(db),
      ),
      possibleRecordingStore: store(),
    );
  }

  Future<PossibleRecordingReviewService> reviewService(
    LibraryImportService importer, {
    String? deletedSongId,
  }) async {
    final db = await appDatabase.database;
    final songs = SqliteSongRepository(SongDao(db));

    return PossibleRecordingReviewService(
      store: store(),
      libraryImportService: importer,
      mediaFileBindingRepository: SqliteMediaFileBindingRepository(
        MediaFileBindingDao(db),
      ),
      songRepository: deletedSongId == null
          ? songs
          : _WithoutSong(songs, deletedSongId),
      now: () => now,
    );
  }

  /// Every library row that names [songId], so a test can prove nothing
  /// about the song changed.
  Future<Map<String, List<Map<String, Object?>>>> rowsOf(String songId) async {
    final db = await appDatabase.database;

    return {
      'songs': await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: [songId],
      ),
      for (final table in [
        DatabaseTables.mediaFileBindings,
        DatabaseTables.albumEditionTracks,
        DatabaseTables.songArtistCredits,
        DatabaseTables.songImportReviews,
      ])
        table: await db.query(table, where: 'song_id = ?', whereArgs: [songId]),
    };
  }

  Future<int> countRows(String table) async {
    final db = await appDatabase.database;
    return (await db.query(table)).length;
  }

  // Import-1: the same title and a similar length at another track position.
  final files = {
    'drama/track03.mp3': errTime(seconds: 146, trackNumber: 3),
    'drama/track09.mp3': errTime(seconds: 147, trackNumber: 9),
  };

  Future<(LibraryImportService, ImportResult, ImportResult)> importBoth(
    Map<String, AudioMetadata> files,
  ) async {
    final importer = await importService(files);
    final kept = await importer.importCandidate(
      candidate('drama/track03.mp3'),
      now: now,
    );
    final ambiguous = await importer.importCandidate(
      candidate('drama/track09.mp3'),
      now: now,
    );
    expect(kept.status, ImportResultStatus.imported);
    expect(ambiguous.skipReason, ImportSkipReason.possibleAlternateRecording);
    return (importer, kept, ambiguous);
  }

  group('recording', () {
    test('an ambiguous import adds one pending entry', () async {
      final (_, kept, _) = await importBoth(files);

      final entry = (await store().getPending()).single;
      expect(
        entry.normalizedPath,
        TextNormalizer.normalizePath('drama/track09.mp3'),
      );
      expect(entry.filePath, 'drama/track09.mp3');
      expect(entry.candidateSongId, kept.songId);
      expect(entry.title, 'ErrTime');
      expect(entry.artistName, 'Fictional Harbour');
      expect(entry.albumTitle, 'Quiet Rooms');
      expect(entry.discNumber, 1);
      expect(entry.trackNumber, 9);
      expect(entry.durationSeconds, 147);
      expect(entry.firstSeenAt, now);
    });

    test('rescanning adds no second entry and keeps when it was first '
        'seen', () async {
      final (importer, _, _) = await importBoth(files);

      final again = await importer.importCandidate(
        candidate('drama/track09.mp3'),
        now: now.add(const Duration(days: 3)),
      );

      expect(again.skipReason, ImportSkipReason.possibleAlternateRecording);
      final entry = (await store().getPending()).single;
      expect(entry.firstSeenAt, now);
    });

    test('a file marked as the same recording is reported as a copy and '
        'not listed again', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer);
      await service.markSameRecording((await store().getPending()).single);

      final again = await importer.importCandidate(
        candidate('drama/track09.mp3'),
        now: now,
      );

      expect(again.status, ImportResultStatus.skipped);
      expect(again.skipReason, ImportSkipReason.duplicateRecording);
      expect(again.songId, kept.songId);
      expect(await store().getPending(), isEmpty);
    });

    test('a different file at a path marked as the same recording is '
        'reported again', () async {
      final mutable = Map.of(files);
      final (importer, _, _) = await importBoth(mutable);
      final service = await reviewService(importer);
      await service.markSameRecording((await store().getPending()).single);

      mutable['drama/track09.mp3'] = errTime(seconds: 149, trackNumber: 9);
      final again = await importer.importCandidate(
        candidate('drama/track09.mp3'),
        now: now,
      );

      expect(again.skipReason, ImportSkipReason.possibleAlternateRecording);
      expect((await store().getPending()).single.durationSeconds, 149);
    });
  });

  group('actions', () {
    test('Import separately makes a new song flagged as a possible '
        'different recording; the kept song is untouched', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer);
      final before = await rowsOf(kept.songId!);
      final songsBefore = await countRows(DatabaseTables.songs);

      final result = await service.importSeparately(
        (await store().getPending()).single,
      );

      expect(result.outcome, PossibleRecordingOutcome.imported);
      final newSongId = result.importResult!.songId!;
      expect(newSongId, isNot(kept.songId));
      expect(await countRows(DatabaseTables.songs), songsBefore + 1);
      expect(await rowsOf(kept.songId!), before);

      final db = await appDatabase.database;
      final review = await SongImportReviewDao(db).findBySongId(newSongId);
      expect(review?.reasons, contains(ImportReviewReason.alternateRecording));
      final binding = (await MediaFileBindingDao(
        db,
      ).findBySongId(newSongId)).single;
      expect(binding.filePath, 'drama/track09.mp3');
      final newSong = (await SongDao(db).findById(newSongId))!;
      expect(newSong.trackNumber, 9);
      expect(newSong.durationSeconds, 147);
      expect(await store().getPending(), isEmpty);

      // A rescan now finds the file in the library.
      final again = await importer.importCandidate(
        candidate('drama/track09.mp3'),
        now: now,
      );
      expect(again.skipReason, ImportSkipReason.knownFile);
      expect(await store().getPending(), isEmpty);
    });

    test('Same recording writes nothing to the library and leaves the '
        'list', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer);
      final before = await rowsOf(kept.songId!);
      final songsBefore = await countRows(DatabaseTables.songs);
      final bindingsBefore = await countRows(DatabaseTables.mediaFileBindings);

      await service.markSameRecording((await store().getPending()).single);

      expect(await store().getPending(), isEmpty);
      expect(await service.pending(), isEmpty);
      expect(await rowsOf(kept.songId!), before);
      expect(await countRows(DatabaseTables.songs), songsBefore);
      expect(await countRows(DatabaseTables.mediaFileBindings), bindingsBefore);
    });

    test('Not now keeps the entry', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer);

      final items = await service.pending();

      expect(items.single.entry.filePath, 'drama/track09.mp3');
      expect(items.single.candidate?.id, kept.songId);
      // Leaving it for later is no action: it is still there next time.
      expect(await service.pending(), hasLength(1));
    });

    test('a missing file leaves the list and nothing is written', () async {
      final mutable = Map.of(files);
      final (importer, kept, _) = await importBoth(mutable);
      final service = await reviewService(importer);
      final before = await rowsOf(kept.songId!);
      final songsBefore = await countRows(DatabaseTables.songs);
      mutable.remove('drama/track09.mp3');

      final result = await service.importSeparately(
        (await store().getPending()).single,
      );

      expect(result.outcome, PossibleRecordingOutcome.fileUnavailable);
      expect(await store().getPending(), isEmpty);
      expect(await countRows(DatabaseTables.songs), songsBefore);
      expect(await rowsOf(kept.songId!), before);
    });

    test('a path already in the library leaves the list and nothing is '
        'written', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer);
      final entry = (await store().getPending()).single;
      final db = await appDatabase.database;
      await MediaFileBindingDao(db).insert(
        MediaFileBindingFactory.create(
          songId: kept.songId!,
          filePath: 'drama/track09.mp3',
          lastSeenAt: now,
          now: now,
        ),
      );
      final before = await rowsOf(kept.songId!);
      final songsBefore = await countRows(DatabaseTables.songs);

      final result = await service.importSeparately(entry);

      expect(result.outcome, PossibleRecordingOutcome.alreadyImported);
      expect(await store().getPending(), isEmpty);
      expect(await countRows(DatabaseTables.songs), songsBefore);
      expect(await rowsOf(kept.songId!), before);
    });

    test('a deleted song leaves the list and nothing is written', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer, deletedSongId: kept.songId);
      final songsBefore = await countRows(DatabaseTables.songs);
      final bindingsBefore = await countRows(DatabaseTables.mediaFileBindings);

      final result = await service.importSeparately(
        (await store().getPending()).single,
      );

      expect(result.outcome, PossibleRecordingOutcome.candidateMissing);
      expect(await store().getPending(), isEmpty);
      expect(await countRows(DatabaseTables.songs), songsBefore);
      expect(await countRows(DatabaseTables.mediaFileBindings), bindingsBefore);
    });

    test('a file whose tags changed is handled as a fresh import would and '
        'leaves the list', () async {
      final mutable = Map.of(files);
      final (importer, kept, _) = await importBoth(mutable);
      final service = await reviewService(importer);
      final before = await rowsOf(kept.songId!);
      mutable['drama/track09.mp3'] = errTime(seconds: 147, trackNumber: 3);

      final result = await service.importSeparately(
        (await store().getPending()).single,
      );

      // Now at the kept song's own position: a copy, so nothing is written.
      expect(result.outcome, PossibleRecordingOutcome.handledByImport);
      expect(
        result.importResult?.skipReason,
        ImportSkipReason.duplicateRecording,
      );
      expect(await store().getPending(), isEmpty);
      expect(await rowsOf(kept.songId!), before);
    });

    test('a file already in the library is dropped when the list is '
        'read', () async {
      final (importer, kept, _) = await importBoth(files);
      final service = await reviewService(importer);
      final db = await appDatabase.database;
      await MediaFileBindingDao(db).insert(
        MediaFileBindingFactory.create(
          songId: kept.songId!,
          filePath: 'drama/track09.mp3',
          lastSeenAt: now,
          now: now,
        ),
      );

      expect(await service.pending(), isEmpty);
      expect(await store().getPending(), isEmpty);
    });

    test('a stored entry for an unknown song can be read', () async {
      final importer = await importService(files);
      final service = await reviewService(importer);
      await store().upsert(
        PendingPossibleRecording(
          normalizedPath: 'gone.mp3',
          filePath: 'gone.mp3',
          candidateSongId: 'song-gone',
          title: 'Gone',
          artistName: 'Fictional Harbour',
          albumTitle: 'Quiet Rooms',
          discNumber: 1,
          trackNumber: 2,
          durationSeconds: 100,
          firstSeenAt: now,
        ),
      );

      final item = (await service.pending()).single;
      expect(item.candidate, isNull);
    });
  });
}
