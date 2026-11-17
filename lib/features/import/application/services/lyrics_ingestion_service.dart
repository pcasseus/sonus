import 'dart:developer' as developer;

import 'package:sonus_next/features/import/application/lyrics/id3_lyrics_reader.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/core/lyrics/lyrics_provenance.dart';
import 'package:sonus_next/core/lyrics/sqlite_lyrics_provenance_store.dart';
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
///
/// Database version 48: each text is written with its source (`embedded`,
/// `sidecarLrc` for a `.lrc` file, `sidecarTxt` otherwise) through
/// [LyricsProvenanceWriter.saveAutomatic], text by text. A rescan never
/// replaces the listener's edit or a better source, and a sidecar with only
/// one kind of text leaves the other stored text alone. The file is never
/// rewritten.
class LyricsIngestionService {
  const LyricsIngestionService({
    required this.sourceReader,
    required this.lyricsWriter,
    this.embeddedReader,
  });

  final LyricsSourceReader sourceReader;
  final LyricsProvenanceWriter lyricsWriter;

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
      final stored = await lyricsWriter.read(songId);
      if (stored != null && _hasLyrics(stored)) return;
    }
    final embedded = await _embedded(candidate);

    final sidecarSynced =
        sidecar != null && LrcParser.parse(sidecar).isNotEmpty;
    final sidecarSource = _sidecarSource(candidate);
    final synced = switch ((embedded?.syncedLrc, sidecarSynced)) {
      (final String tag, _) => LyricsCandidate(
        text: tag,
        source: LyricsSource.embedded,
      ),
      (null, true) => LyricsCandidate(text: sidecar!, source: sidecarSource),
      _ => null,
    };
    final plain = switch ((embedded?.plain, sidecar, sidecarSynced)) {
      (final String tag, _, _) => LyricsCandidate(
        text: tag,
        source: LyricsSource.embedded,
      ),
      (null, final String text, false) => LyricsCandidate(
        text: text,
        source: sidecarSource,
      ),
      _ => null,
    };

    if (synced == null && plain == null) return;
    await lyricsWriter.saveAutomatic(
      songId: songId,
      plain: plain,
      synced: synced,
    );
  }

  static bool _hasLyrics(Map<String, Object?> row) => LyricsTextKind.values.any(
    (kind) => LyricsText.fromRow(row, kind).hasText,
  );

  /// A `.lrc` sidecar ranks above any other sidecar file.
  static LyricsSource _sidecarSource(ImportCandidate candidate) =>
      (candidate.lyricsPath ?? '').trim().toLowerCase().endsWith('.lrc')
      ? LyricsSource.sidecarLrc
      : LyricsSource.sidecarTxt;

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
