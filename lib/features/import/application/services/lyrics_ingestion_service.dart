import 'dart:developer' as developer;

import 'package:sonus_next/features/import/application/lyrics/id3_lyrics_reader.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';
import 'package:sonus_next/features/player/domain/services/lrc_parser.dart';

/// Reads the lyrics embedded in a candidate's audio file, if any.
typedef EmbeddedLyricsReader =
    Future<EmbeddedLyrics?> Function(ImportCandidate candidate);

/// Stores a newly imported song's lyrics from the file next to it and the
/// tags inside it.
///
/// App Update 1.3 (REF-1.3-07), the approved source precedence among the
/// sources an import can see (user edits and providers come later and rank
/// above all of these):
///
/// - synchronised: embedded (SYLT) before a sidecar (`.lrc`, or `.txt`)
///   with timestamps;
/// - plain: embedded (USLT) before a sidecar without timestamps.
///
/// The best of each is stored together, so a song can keep plain lyrics
/// beside synchronised ones. Local only: nothing is fetched, uploaded or
/// transcribed.
class LyricsIngestionService {
  const LyricsIngestionService({
    required this.sourceReader,
    required this.trackLyricsRepository,
    this.embeddedReader,
  });

  final LyricsSourceReader sourceReader;
  final TrackLyricsRepository trackLyricsRepository;

  /// Null reads sidecars only.
  final EmbeddedLyricsReader? embeddedReader;

  /// Whether a candidate without a sidecar can still have lyrics.
  bool get readsEmbedded => embeddedReader != null;

  Future<void> ingest({
    required ImportCandidate candidate,
    required String songId,
  }) async {
    final source = (await sourceReader.read(candidate))?.trim();
    final sidecar = source == null || source.isEmpty ? null : source;
    if (sidecar == null) {
      if (!readsEmbedded) return;
      // Rescans import known files again. Without a sidecar, a song's tag
      // only fills in lyrics it does not have: stored lyrics (restored,
      // synced, or edited later) are never replaced from a tag, and the
      // file is not reopened.
      final stored = await trackLyricsRepository.getBySongId(songId);
      if (stored?.hasLyrics ?? false) return;
    }
    final embedded = await _embedded(candidate);

    final sidecarSynced =
        sidecar != null && LrcParser.parse(sidecar).isNotEmpty;
    final synced = embedded?.syncedLrc ?? (sidecarSynced ? sidecar : null);
    final plain = embedded?.plain ?? (sidecarSynced ? null : sidecar);

    if (synced == null && plain == null) return;
    await trackLyricsRepository.save(
      songId: songId,
      plainText: plain,
      syncedText: synced,
    );
  }

  Future<EmbeddedLyrics?> _embedded(ImportCandidate candidate) async {
    final reader = embeddedReader;
    if (reader == null) return null;
    try {
      return await reader(candidate);
    } on Exception catch (error, stackTrace) {
      // Embedded lyrics are optional; a sidecar still counts. The path is
      // not logged.
      developer.log(
        'Embedded lyrics could not be read (${error.runtimeType})',
        name: 'sonus.import.lyrics',
        level: 900,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
