// SN-50 §5 Option B: files kept out of the library as possible different
// recordings wait in a device-local list for the user's decision.
import 'dart:convert';

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
import 'package:sonus_next/features/import/domain/models/import_file_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/pending_possible_recording.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/services/import_file_probe.dart';
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

/// Per path, the tags read or the failure thrown; a path it does not know
/// is missing.
class _Reader implements AudioMetadataReader {
  _Reader(this.byPath);

  final Map<String, Object> byPath;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    return switch (byPath[candidate.filePath]) {
      final AudioMetadata metadata => metadata,
      final Object failure? => throw failure,
      _ => throw const ImportFileMissing('not in the fake'),
    };
  }
}

class _Probe implements ImportFileProbe {
  _Probe(this.state);

  ImportFileState state;
  final probed = <String>[];

  @override
  Future<ImportFileState> probe(String filePath) async {
    probed.add(filePath);
    return state;
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
    Map<String, AudioMetadata> files, {
    AudioMetadataReader? primaryReader,
    AudioMetadataReader? fallbackReader,
  }) async {
    final db = await appDatabase.database;

    return LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: primaryReader ?? _MetadataByPath(files),
        fallbackReader: fallbackReader ?? _Unreadable(),
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
    ImportFileProbe? fileProbe,
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
      fileProbe: fileProbe,
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

    test('SN-50 W15: a file whose absence is not verified stays listed and '
        'nothing is written', () async {
      final mutable = Map.of(files);
      final (importer, kept, _) = await importBoth(mutable);
      final service = await reviewService(importer);
      final before = await rowsOf(kept.songId!);
      final songsBefore = await countRows(DatabaseTables.songs);
      mutable.remove('drama/track09.mp3');

      final result = await service.importSeparately(
        (await store().getPending()).single,
      );

      // The reader fails without saying the file is gone.
      expect(result.outcome, PossibleRecordingOutcome.checkFailed);
      expect(await store().getPending(), hasLength(1));
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

  // SN-50 §4: a missing file, a file Sonus may no longer read and a file
  // without readable tags are told apart; only a missing or changed file
  // leaves the list.
  group('unreachable files', () {
    final track03 = files['drama/track03.mp3']!;
    final track09 = files['drama/track09.mp3']!;
    const pendingKey = 'import.possible_recordings.pending';

    /// Records track09 as pending (read as [first], track09's tags by
    /// default), then answers [later] for it in the review.
    Future<(PossibleRecordingReviewService, String)> pendingThen(
      Object later, {
      ImportFileProbe? probe,
      Object? first,
    }) async {
      final byPath = <String, Object>{
        'drama/track03.mp3': track03,
        'drama/track09.mp3': first ?? track09,
      };
      final importer = await importService(
        files,
        primaryReader: _Reader(byPath),
        // A path guess with the same facts as the tags.
        fallbackReader: _Reader({'drama/track09.mp3': track09}),
      );
      final kept = await importer.importCandidate(
        candidate('drama/track03.mp3'),
        now: now,
      );
      final ambiguous = await importer.importCandidate(
        candidate('drama/track09.mp3'),
        now: now,
      );
      expect(ambiguous.skipReason, ImportSkipReason.possibleAlternateRecording);
      byPath['drama/track09.mp3'] = later;
      return (await reviewService(importer, fileProbe: probe), kept.songId!);
    }

    /// Import separately of the one pending entry: its outcome, and whether
    /// the entry is still listed. Nothing in the library may change unless
    /// it imported.
    Future<(PossibleRecordingOutcome, bool)> importOnce(
      PossibleRecordingReviewService service,
      String keptId,
    ) async {
      final before = await rowsOf(keptId);
      final songsBefore = await countRows(DatabaseTables.songs);

      final result = await service.importSeparately(
        (await store().getPending()).single,
      );

      expect(await rowsOf(keptId), before);
      if (result.outcome != PossibleRecordingOutcome.imported) {
        expect(await countRows(DatabaseTables.songs), songsBefore);
      }
      return (result.outcome, (await store().getPending()).isNotEmpty);
    }

    test('a lost folder permission keeps the entry', () async {
      final probe = _Probe(ImportFileState.permissionLost);
      final (service, keptId) = await pendingThen(track09, probe: probe);

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.permissionLost,
        true,
      ));
      expect(probe.probed, ['drama/track09.mp3']);
    });

    test('a file that could not be checked stays listed', () async {
      final (service, keptId) = await pendingThen(
        track09,
        probe: _Probe(ImportFileState.unknown),
      );

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.checkFailed,
        true,
      ));
    });

    test('a file the probe finds missing leaves the list', () async {
      final (service, keptId) = await pendingThen(
        track09,
        probe: _Probe(ImportFileState.missing),
      );

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.fileUnavailable,
        false,
      ));
    });

    test('a present file imports separately as before', () async {
      final (service, keptId) = await pendingThen(
        track09,
        probe: _Probe(ImportFileState.present),
      );

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.imported,
        false,
      ));
    });

    test('listing retires a missing file and keeps one Sonus cannot '
        'reach', () async {
      final probe = _Probe(ImportFileState.permissionLost);
      final (service, _) = await pendingThen(track09, probe: probe);

      expect(await service.pending(), hasLength(1));
      expect(await store().getPending(), hasLength(1));

      probe.state = ImportFileState.unknown;
      expect(await service.pending(), hasLength(1));

      probe.state = ImportFileState.missing;
      expect(await service.pending(), isEmpty);
      expect(await store().getPending(), isEmpty);
    });

    test('a read refused for permission keeps the entry', () async {
      final (service, keptId) = await pendingThen(
        const ImportFileAccessDenied('revoked'),
      );

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.permissionLost,
        true,
      ));
    });

    test('an unexplained read failure keeps the entry', () async {
      final (service, keptId) = await pendingThen(StateError('hiccup'));

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.checkFailed,
        true,
      ));
    });

    test('a file missing on read leaves the list', () async {
      final (service, keptId) = await pendingThen(
        const ImportFileMissing('gone'),
      );

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.fileUnavailable,
        false,
      ));
    });

    test('SN-50 W15: tags lost since a tag-based entry was recorded keep '
        'it listed; only a verified missing file leaves', () async {
      final (service, keptId) = await pendingThen(
        const ImportTagsUnreadable('no tags'),
      );
      expect(
        (await store().getPending()).single.metadataSource,
        MetadataSource.embedded,
      );

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.checkFailed,
        true,
      ));
    });

    test('an entry saved before SN-50 §4 is read as tag-based', () async {
      final (service, keptId) = await pendingThen(
        const ImportTagsUnreadable('no tags'),
        first: const ImportTagsUnreadable('no tags'),
      );
      final stored = (jsonDecode(preferences[pendingKey]!) as List)
          .cast<Map<String, Object?>>();
      expect(stored.single['metadataSource'], 'fallback');
      preferences[pendingKey] = jsonEncode([
        for (final json in stored) {...json}..remove('metadataSource'),
      ]);
      final entry = (await store().getPending()).single;
      expect(entry.metadataSource, isNull);
      expect(entry.recordedFromPath, isFalse);

      // SN-50 W15: unreadable tags are not a missing file.
      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.checkFailed,
        true,
      ));
    });

    test('an entry recorded from its path imports separately; the kept '
        'song is untouched', () async {
      final (service, keptId) = await pendingThen(
        const ImportTagsUnreadable('no tags'),
        first: const ImportTagsUnreadable('no tags'),
      );
      final entry = (await store().getPending()).single;
      expect(entry.metadataSource, MetadataSource.fallback);
      expect(entry.recordedFromPath, isTrue);
      final songsBefore = await countRows(DatabaseTables.songs);

      expect(await importOnce(service, keptId), (
        PossibleRecordingOutcome.imported,
        false,
      ));
      expect(await countRows(DatabaseTables.songs), songsBefore + 1);
    });
  });
}
