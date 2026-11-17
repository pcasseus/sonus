import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/lyrics/id3_lyrics_reader.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/core/lyrics/lyrics_provenance.dart';
import 'package:sonus_next/core/lyrics/sqlite_lyrics_provenance_store.dart';

void main() {
  test('stores timestamped LRC as synced lyrics', () async {
    final reader = _FakeLyricsSourceReader('[00:01.00]First line');
    final repository = _RecordingLyricsWriter();
    final service = LyricsIngestionService(
      sourceReader: reader,
      lyricsWriter: repository,
    );

    await service.ingest(candidate: _candidate(), songId: 'song-1');

    expect(repository.saveCalls, 1);
    expect(repository.savedSongId, 'song-1');
    expect(repository.savedPlainText, isNull);
    expect(repository.savedSyncedText, '[00:01.00]First line');
  });

  test('stores untimestamped sidecar text as plain lyrics', () async {
    final reader = _FakeLyricsSourceReader('First line\nSecond line');
    final repository = _RecordingLyricsWriter();
    final service = LyricsIngestionService(
      sourceReader: reader,
      lyricsWriter: repository,
    );

    await service.ingest(candidate: _candidate(), songId: 'song-1');

    expect(repository.saveCalls, 1);
    expect(repository.savedPlainText, 'First line\nSecond line');
    expect(repository.savedSyncedText, isNull);
  });

  test('does nothing when sidecar reader returns no lyrics', () async {
    final reader = _FakeLyricsSourceReader(null);
    final repository = _RecordingLyricsWriter();
    final service = LyricsIngestionService(
      sourceReader: reader,
      lyricsWriter: repository,
    );

    await service.ingest(candidate: _candidate(), songId: 'song-1');

    expect(repository.saveCalls, 0);
  });

  // App Update 1.3 (REF-1.3-07): embedded lyrics and the approved source
  // precedence.
  group('embedded lyrics', () {
    Future<_RecordingLyricsWriter> ingest({
      String? sidecar,
      EmbeddedLyrics? embedded,
      Object? embeddedError,
    }) async {
      final repository = _RecordingLyricsWriter();
      await LyricsIngestionService(
        sourceReader: _FakeLyricsSourceReader(sidecar),
        lyricsWriter: repository,
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
      final repository = _RecordingLyricsWriter(
        stored: const {'song_id': 'song-1', 'plain_text': 'Restored'},
      );
      var tagReads = 0;
      await LyricsIngestionService(
        sourceReader: const _FakeLyricsSourceReader(null),
        lyricsWriter: repository,
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

class _RecordingLyricsWriter implements LyricsProvenanceWriter {
  _RecordingLyricsWriter({this.stored});

  /// Lyrics the song already has.
  final Map<String, Object?>? stored;
  int saveCalls = 0;
  String? savedSongId;
  String? savedPlainText;
  String? savedSyncedText;
  LyricsSource? savedPlainSource;
  LyricsSource? savedSyncedSource;

  @override
  Future<Map<String, Object?>?> read(String songId) async => stored;

  @override
  Future<LyricsWriteResult> saveAutomatic({
    required String songId,
    LyricsCandidate? plain,
    LyricsCandidate? synced,
    LyricsProviderDetails? provider,
  }) async {
    saveCalls++;
    savedSongId = songId;
    savedPlainText = plain?.text;
    savedSyncedText = synced?.text;
    savedPlainSource = plain?.source;
    savedSyncedSource = synced?.source;
    return LyricsWriteResult(plain: plain != null, synced: synced != null);
  }
}
