import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/lyrics/id3_lyrics_reader.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/features/player/domain/models/track_lyrics.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';

void main() {
  test('stores timestamped LRC as synced lyrics', () async {
    final reader = _FakeLyricsSourceReader('[00:01.00]First line');
    final repository = _RecordingTrackLyricsRepository();
    final service = LyricsIngestionService(
      sourceReader: reader,
      trackLyricsRepository: repository,
    );

    await service.ingest(candidate: _candidate(), songId: 'song-1');

    expect(repository.saveCalls, 1);
    expect(repository.savedSongId, 'song-1');
    expect(repository.savedPlainText, isNull);
    expect(repository.savedSyncedText, '[00:01.00]First line');
  });

  test('stores untimestamped sidecar text as plain lyrics', () async {
    final reader = _FakeLyricsSourceReader('First line\nSecond line');
    final repository = _RecordingTrackLyricsRepository();
    final service = LyricsIngestionService(
      sourceReader: reader,
      trackLyricsRepository: repository,
    );

    await service.ingest(candidate: _candidate(), songId: 'song-1');

    expect(repository.saveCalls, 1);
    expect(repository.savedPlainText, 'First line\nSecond line');
    expect(repository.savedSyncedText, isNull);
  });

  test('does nothing when sidecar reader returns no lyrics', () async {
    final reader = _FakeLyricsSourceReader(null);
    final repository = _RecordingTrackLyricsRepository();
    final service = LyricsIngestionService(
      sourceReader: reader,
      trackLyricsRepository: repository,
    );

    await service.ingest(candidate: _candidate(), songId: 'song-1');

    expect(repository.saveCalls, 0);
  });

  // App Update 1.3 (REF-1.3-07): embedded lyrics and the approved source
  // precedence.
  group('embedded lyrics', () {
    Future<_RecordingTrackLyricsRepository> ingest({
      String? sidecar,
      EmbeddedLyrics? embedded,
      Object? embeddedError,
    }) async {
      final repository = _RecordingTrackLyricsRepository();
      await LyricsIngestionService(
        sourceReader: _FakeLyricsSourceReader(sidecar),
        trackLyricsRepository: repository,
        embeddedReader: (_) async {
          if (embeddedError != null) throw embeddedError;
          return embedded;
        },
      ).ingest(candidate: _candidate(), songId: 'song-1');
      return repository;
    }

    test('without a sidecar, the tag lyrics are stored', () async {
      final saved = await ingest(
        embedded: const EmbeddedLyrics(
          plain: 'Tag words',
          syncedLrc: '[00:01.00]Tag line',
        ),
      );
      expect(saved.savedPlainText, 'Tag words');
      expect(saved.savedSyncedText, '[00:01.00]Tag line');
    });

    test('embedded synchronised lyrics come before a timed sidecar', () async {
      final saved = await ingest(
        sidecar: '[00:05.00]Sidecar line',
        embedded: const EmbeddedLyrics(syncedLrc: '[00:01.00]Tag line'),
      );
      expect(saved.savedSyncedText, '[00:01.00]Tag line');
      expect(saved.savedPlainText, isNull);
    });

    test('a timed sidecar comes before embedded plain lyrics, and both '
        'are kept', () async {
      final saved = await ingest(
        sidecar: '[00:05.00]Sidecar line',
        embedded: const EmbeddedLyrics(plain: 'Tag words'),
      );
      expect(saved.savedSyncedText, '[00:05.00]Sidecar line');
      expect(saved.savedPlainText, 'Tag words');
    });

    test('embedded plain lyrics come before a plain sidecar', () async {
      final saved = await ingest(
        sidecar: 'Sidecar words',
        embedded: const EmbeddedLyrics(plain: 'Tag words'),
      );
      expect(saved.savedPlainText, 'Tag words');
      expect(saved.savedSyncedText, isNull);
    });

    test('an unreadable tag never stops the sidecar', () async {
      final saved = await ingest(
        sidecar: 'Sidecar words',
        embeddedError: const FileSystemException('gone'),
      );
      expect(saved.savedPlainText, 'Sidecar words');
    });

    test('without a sidecar, stored lyrics are never replaced from a tag, '
        'and the file is not read', () async {
      final repository = _RecordingTrackLyricsRepository(
        stored: const TrackLyrics(songId: 'song-1', plainText: 'Restored'),
      );
      var tagReads = 0;
      await LyricsIngestionService(
        sourceReader: const _FakeLyricsSourceReader(null),
        trackLyricsRepository: repository,
        embeddedReader: (_) async {
          tagReads++;
          return const EmbeddedLyrics(plain: 'Tag words');
        },
      ).ingest(candidate: _candidate(), songId: 'song-1');
      expect(repository.saveCalls, 0);
      expect(tagReads, 0);
    });

    test('nothing anywhere: nothing saved', () async {
      final saved = await ingest();
      expect(saved.saveCalls, 0);
    });
  });
}

ImportCandidate _candidate() {
  return ImportCandidate(
    filePath: 'song.mp3',
    normalizedPath: 'song.mp3',
    discoveredAt: DateTime(2026),
    lyricsPath: 'song.lrc',
  );
}

class _FakeLyricsSourceReader implements LyricsSourceReader {
  const _FakeLyricsSourceReader(this.value);

  final String? value;

  @override
  Future<String?> read(ImportCandidate candidate) async => value;
}

class _RecordingTrackLyricsRepository implements TrackLyricsRepository {
  _RecordingTrackLyricsRepository({this.stored});

  /// Lyrics the song already has.
  final TrackLyrics? stored;
  int saveCalls = 0;
  String? savedSongId;
  String? savedPlainText;
  String? savedSyncedText;

  @override
  Future<void> deleteBySongId(String songId) async {}

  @override
  Future<TrackLyrics?> getBySongId(String songId) async => stored;

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) async {
    saveCalls++;
    savedSongId = songId;
    savedPlainText = plainText;
    savedSyncedText = syncedText;
  }
}
