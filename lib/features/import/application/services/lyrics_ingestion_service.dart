import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';
import 'package:sonus_next/features/player/domain/services/lrc_parser.dart';

class LyricsIngestionService {
  const LyricsIngestionService({
    required this.sourceReader,
    required this.trackLyricsRepository,
  });

  final LyricsSourceReader sourceReader;
  final TrackLyricsRepository trackLyricsRepository;

  Future<void> ingest({
    required ImportCandidate candidate,
    required String songId,
  }) async {
    final source = await sourceReader.read(candidate);

    if (source == null || source.trim().isEmpty) {
      return;
    }

    final syncedLines = LrcParser.parse(source);

    if (syncedLines.isNotEmpty) {
      await trackLyricsRepository.save(songId: songId, syncedText: source);
      return;
    }

    await trackLyricsRepository.save(songId: songId, plainText: source);
  }
}
