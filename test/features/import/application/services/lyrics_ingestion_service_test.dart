import 'package:flutter_test/flutter_test.dart';
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
  int saveCalls = 0;
  String? savedSongId;
  String? savedPlainText;
  String? savedSyncedText;

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
    saveCalls++;
    savedSongId = songId;
    savedPlainText = plainText;
    savedSyncedText = syncedText;
  }
}
