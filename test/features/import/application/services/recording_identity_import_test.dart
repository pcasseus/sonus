// Import-1 (SN-44 device audit): four "ErrTime" files, two ~2:26 and two
// ~3:16 recordings, collapsed into one song. Three files were "skipped" with
// no binding, no credits and no review row, so a distinct recording vanished.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/player/domain/models/track_lyrics.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';

class _MetadataByPath implements AudioMetadataReader {
  _MetadataByPath(this.byPath);

  final Map<String, AudioMetadata> byPath;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async =>
      byPath[candidate.filePath]!;
}

class _NoFallback implements AudioMetadataReader {
  @override
  Future<AudioMetadata> read(ImportCandidate candidate) =>
      throw StateError('fallback should not run');
}

class _LyricsByPath implements LyricsSourceReader {
  @override
  Future<String?> read(ImportCandidate candidate) async =>
      '[00:01.00]${candidate.filePath}';
}

class _RecordingLyrics implements TrackLyricsRepository {
  final saves = <String, String?>{};

  @override
  Future<void> deleteBySongId(String songId) async {}

  @override
  Future<TrackLyrics?> getBySongId(String songId) async => null;

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) async {
    saves[songId] = syncedText ?? plainText;
  }
}

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() => appDatabase.close());

  AudioMetadata errTime({
    required int seconds,
    List<String> featuredArtists = const [],
    int trackNumber = 1,
  }) {
    return AudioMetadata(
      title: 'ErrTime',
      artistName: 'Cardi B',
      albumTitle: 'Am I The Drama?',
      durationSeconds: seconds,
      trackNumber: trackNumber,
      discNumber: 1,
      isSingle: false,
      featuredArtists: featuredArtists,
    );
  }

  ImportCandidate candidate(String path, {bool withLyrics = false}) {
    return ImportCandidate(
      filePath: path,
      normalizedPath: path.toLowerCase(),
      discoveredAt: now,
      lyricsPath: withLyrics ? '$path.lrc' : null,
    );
  }

  Future<(LibraryImportService, _RecordingLyrics)> service(
    Map<String, AudioMetadata> files,
  ) async {
    final db = await appDatabase.database;
    final lyrics = _RecordingLyrics();

    return (
      LibraryImportService(
        metadataResolver: MetadataResolver(
          primaryReader: _MetadataByPath(files),
          fallbackReader: _NoFallback(),
        ),
        atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
        mediaFileBindingRepository: SqliteMediaFileBindingRepository(
          MediaFileBindingDao(db),
        ),
        lyricsIngestionService: LyricsIngestionService(
          sourceReader: _LyricsByPath(),
          trackLyricsRepository: lyrics,
        ),
      ),
      lyrics,
    );
  }

  Future<List<ImportResult>> importAll(
    LibraryImportService service,
    List<ImportCandidate> candidates,
  ) async => [
    for (final c in candidates) await service.importCandidate(c, now: now),
  ];

  test(
    'two recordings of ErrTime stay two songs; copies are flagged',
    () async {
      final files = {
        'a/ErrTime.mp3': errTime(seconds: 146),
        'b/ErrTime.mp3': errTime(seconds: 147),
        'c/ErrTime.mp3': errTime(seconds: 196),
        'd/ErrTime.mp3': errTime(seconds: 196),
      };
      final (importer, _) = await service(files);

      final results = await importAll(importer, [
        for (final path in files.keys) candidate(path),
      ]);

      final db = await appDatabase.database;
      final songs = await SongDao(db).findAll();
      expect(songs.map((s) => s.durationSeconds), unorderedEquals([146, 196]));

      final short = songs.firstWhere((s) => s.durationSeconds == 146);
      final long = songs.firstWhere((s) => s.durationSeconds == 196);

      expect(results[0].status, ImportResultStatus.imported);
      expect(results[0].songId, short.id);

      // A copy of a recording already in the library is still skipped, but
      // says so and points at the song it duplicates.
      expect(results[1].status, ImportResultStatus.skipped);
      expect(results[1].skipReason, ImportSkipReason.duplicateRecording);
      expect(results[1].songId, short.id);

      expect(results[2].status, ImportResultStatus.imported);
      expect(results[2].songId, long.id);

      expect(results[3].status, ImportResultStatus.skipped);
      expect(results[3].skipReason, ImportSkipReason.duplicateRecording);
      expect(results[3].songId, long.id);

      // The second recording keeps its own file and asks for review.
      final bindings = MediaFileBindingDao(db);
      expect(await bindings.findBySongId(long.id), hasLength(1));
      final review = await SongImportReviewDao(db).findBySongId(long.id);
      expect(review?.reasons, contains(ImportReviewReason.alternateRecording));
      expect(await SongImportReviewDao(db).findBySongId(short.id), isNull);
    },
  );

  test('different featured artists make a different recording', () async {
    final files = {
      'solo.mp3': errTime(seconds: 146),
      'remix.mp3': errTime(seconds: 146, featuredArtists: ['GloRilla']),
    };
    final (importer, _) = await service(files);

    final results = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    expect(
      results.map((r) => r.status),
      everyElement(ImportResultStatus.imported),
    );
    expect(results[0].songId, isNot(results[1].songId));
  });

  test('a close duration is the same recording, not a new song', () async {
    final files = {
      'one.mp3': errTime(seconds: 200),
      'two.mp3': errTime(seconds: 202),
    };
    final (importer, _) = await service(files);

    final results = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(1));
    expect(results[1].skipReason, ImportSkipReason.duplicateRecording);
  });

  test(
    'an unknown duration is not evidence of a different recording',
    () async {
      final files = {
        'one.mp3': errTime(seconds: 200),
        'two.mp3': errTime(seconds: 0),
      };
      final (importer, _) = await service(files);

      await importAll(importer, [
        for (final path in files.keys) candidate(path),
      ]);

      final db = await appDatabase.database;
      expect(await SongDao(db).findAll(), hasLength(1));
    },
  );

  test('SN-44 Import-1, current source: same title and length at another '
      'track position is kept as one song, and the copy is flagged', () async {
    final files = {
      'track03.mp3': errTime(seconds: 146, trackNumber: 3),
      'track09.mp3': errTime(seconds: 147, trackNumber: 9),
    };
    final (importer, _) = await service(files);

    final results = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(1));
    expect(results[1].status, ImportResultStatus.skipped);
    // A different track position is not evidence of a different recording,
    // but it is not proof of a copy either: it is reported, not merged.
    expect(results[1].skipReason, ImportSkipReason.possibleAlternateRecording);
    expect(results[1].songId, results[0].songId);
    expect(
      (await MediaFileBindingDao(
        db,
      ).findBySongId(results[0].songId!)).map((b) => b.filePath),
      ['track03.mp3'],
    );
  });

  test('SN-50 Import-1: an ambiguous same-title, similar-length file is '
      'never merged into the kept song or rewritten, also on a second '
      'import', () async {
    final files = {
      'track03.mp3': errTime(seconds: 146, trackNumber: 3),
      'track09.mp3': errTime(seconds: 147, trackNumber: 9),
    };
    final (importer, _) = await service(files);

    final first = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final db = await appDatabase.database;
    final bindings = MediaFileBindingDao(db);
    final kept = (await SongDao(db).findAll()).single;
    final keptBindings = await bindings.findBySongId(kept.id);

    // The kept song keeps only its own file; the ambiguous file is reported
    // against it, not bound to it, and nothing about the song changes.
    expect(first[0].songId, kept.id);
    expect(first[1].status, ImportResultStatus.skipped);
    expect(first[1].skipReason, ImportSkipReason.possibleAlternateRecording);
    expect(first[1].songId, kept.id);
    expect(keptBindings.map((b) => b.filePath), ['track03.mp3']);
    expect(kept.durationSeconds, 146);

    final again = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final songsAfter = await SongDao(db).findAll();
    expect(songsAfter.map((s) => s.id), [kept.id]);
    expect(songsAfter.single.title, kept.title);
    expect(songsAfter.single.durationSeconds, kept.durationSeconds);
    expect((await bindings.findBySongId(kept.id)).map((b) => b.filePath), [
      'track03.mp3',
    ]);
    expect(again[1].status, ImportResultStatus.skipped);
    expect(again[1].skipReason, ImportSkipReason.possibleAlternateRecording);
    expect(again[1].songId, kept.id);
    expect(await SongImportReviewDao(db).findBySongId(kept.id), isNull);
  });

  test('the same disc and track position from another path is still a '
      'duplicate recording', () async {
    final files = {
      'a/track03.mp3': errTime(seconds: 146, trackNumber: 3),
      'b/track03.mp3': errTime(seconds: 147, trackNumber: 3),
    };
    final (importer, _) = await service(files);

    final results = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(1));
    expect(results[1].status, ImportResultStatus.skipped);
    expect(results[1].skipReason, ImportSkipReason.duplicateRecording);
    expect(results[1].songId, results[0].songId);
  });

  test('a different version label of the same title and length is its own '
      'song', () async {
    final files = {
      'original.mp3': errTime(seconds: 146, trackNumber: 3),
      'club.mp3': AudioMetadata(
        title: 'ErrTime (Club Remix)',
        artistName: 'Cardi B',
        albumTitle: 'Am I The Drama?',
        durationSeconds: 146,
        trackNumber: 9,
        discNumber: 1,
        isSingle: false,
        featuredArtists: const [],
      ),
    };
    final (importer, _) = await service(files);

    final results = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(2));
    expect(
      results.map((r) => r.status),
      everyElement(ImportResultStatus.imported),
    );
    expect(results[0].songId, isNot(results[1].songId));
  });

  test('a possible different recording never attaches its lyrics to the '
      'kept song', () async {
    final files = {
      'track03.mp3': errTime(seconds: 146, trackNumber: 3),
      'track09.mp3': errTime(seconds: 147, trackNumber: 9),
    };
    final (importer, lyrics) = await service(files);

    final results = await importAll(importer, [
      candidate('track03.mp3', withLyrics: true),
      candidate('track09.mp3', withLyrics: true),
    ]);

    expect(results[1].skipReason, ImportSkipReason.possibleAlternateRecording);
    expect(lyrics.saves[results[0].songId], contains('track03.mp3'));
    expect(lyrics.saves.values, isNot(contains(contains('track09.mp3'))));
  });

  test('a duplicate file never attaches its lyrics to the kept song', () async {
    final files = {
      'kept.mp3': errTime(seconds: 146),
      'copy.mp3': errTime(seconds: 146),
    };
    final (importer, lyrics) = await service(files);

    final results = await importAll(importer, [
      candidate('kept.mp3', withLyrics: true),
      candidate('copy.mp3', withLyrics: true),
    ]);

    expect(lyrics.saves[results[0].songId], contains('kept.mp3'));
    expect(lyrics.saves.values, isNot(contains(contains('copy.mp3'))));
  });

  test('SN-44 Import-2: a Deluxe copy of a kept song never replaces its '
      'lyrics with its own sidecar', () async {
    final files = {
      'standard.mp3': errTime(seconds: 146),
      'deluxe.mp3': AudioMetadata(
        title: 'ErrTime',
        artistName: 'Cardi B',
        albumTitle: 'Am I The Drama? (Deluxe)',
        durationSeconds: 146,
        trackNumber: 1,
        discNumber: 1,
        isSingle: false,
        featuredArtists: const [],
      ),
    };
    final (importer, lyrics) = await service(files);

    final results = await importAll(importer, [
      candidate('standard.mp3', withLyrics: true),
      candidate('deluxe.mp3', withLyrics: true),
    ]);

    expect(results[1].skipReason, ImportSkipReason.sharedWithEdition);
    expect(results[1].songId, results[0].songId);
    expect(lyrics.saves[results[0].songId], contains('standard.mp3'));
    expect(lyrics.saves.values, isNot(contains(contains('deluxe.mp3'))));
  });

  test('a rescan of the kept file still refreshes its own lyrics', () async {
    final files = {'kept.mp3': errTime(seconds: 146)};
    final (importer, lyrics) = await service(files);

    final first = await importAll(importer, [candidate('kept.mp3')]);
    final rescan = await importAll(importer, [
      candidate('kept.mp3', withLyrics: true),
    ]);

    expect(rescan.single.skipReason, ImportSkipReason.knownFile);
    expect(lyrics.saves[first.single.songId], contains('kept.mp3'));
  });

  test('rescanning both recordings changes nothing', () async {
    final files = {
      'short.mp3': errTime(seconds: 146),
      'long.mp3': errTime(seconds: 196),
    };
    final (importer, _) = await service(files);
    await importAll(importer, [for (final path in files.keys) candidate(path)]);

    final rescan = await importAll(importer, [
      for (final path in files.keys) candidate(path),
    ]);

    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(2));
    expect(
      rescan.map((r) => r.status),
      everyElement(ImportResultStatus.skipped),
    );
    expect(
      rescan.map((r) => r.skipReason),
      everyElement(ImportSkipReason.knownFile),
    );
  });

  test('a moved file of the same recording still relinks', () async {
    final files = {
      'old/ErrTime.mp3': errTime(seconds: 146),
      'new/ErrTime.mp3': errTime(seconds: 146),
    };
    final (importer, _) = await service(files);
    final first = await importer.importCandidate(
      candidate('old/ErrTime.mp3'),
      now: now,
    );

    final db = await appDatabase.database;
    final bindingDao = MediaFileBindingDao(db);
    final binding = (await bindingDao.findBySongId(first.songId!)).single;
    await bindingDao.update(binding.copyWith(isAvailable: false));

    final moved = await importer.importCandidate(
      candidate('new/ErrTime.mp3'),
      now: now,
    );

    expect(moved.status, ImportResultStatus.relinked);
    expect(moved.songId, first.songId);
  });

  test('a missing file never relinks to a different recording', () async {
    final files = {
      'old/ErrTime.mp3': errTime(seconds: 146),
      'new/ErrTime.mp3': errTime(seconds: 196),
    };
    final (importer, _) = await service(files);
    final first = await importer.importCandidate(
      candidate('old/ErrTime.mp3'),
      now: now,
    );

    final db = await appDatabase.database;
    final bindingDao = MediaFileBindingDao(db);
    final binding = (await bindingDao.findBySongId(first.songId!)).single;
    await bindingDao.update(binding.copyWith(isAvailable: false));

    final other = await importer.importCandidate(
      candidate('new/ErrTime.mp3'),
      now: now,
    );

    expect(other.status, ImportResultStatus.imported);
    expect(other.songId, isNot(first.songId));
    // The original song keeps its identity and its (missing) file record.
    expect(await bindingDao.findBySongId(first.songId!), hasLength(1));
  });
}
