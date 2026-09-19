import '../../domain/models/audio_metadata.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/resolved_metadata.dart';
import '../../domain/services/audio_metadata_reader.dart';

class MetadataResolver {
  const MetadataResolver({
    required this.primaryReader,
    required this.fallbackReader,
  });

  final AudioMetadataReader primaryReader;
  final AudioMetadataReader fallbackReader;

  Future<ResolvedMetadata> resolve(ImportCandidate candidate) async {
    AudioMetadata primary;

    try {
      primary = await primaryReader.read(candidate);
    } catch (_) {
      final metadata = await fallbackReader.read(candidate);

      return ResolvedMetadata(
        metadata: metadata,
        source: MetadataSource.fallback,
      );
    }

    if (!_needsFallback(primary)) {
      return ResolvedMetadata(
        metadata: primary,
        source: MetadataSource.embedded,
      );
    }

    final fallback = await fallbackReader.read(candidate);

    return ResolvedMetadata(
      metadata: _merge(primary, fallback),
      source: MetadataSource.mixed,
    );
  }

  bool _needsFallback(AudioMetadata metadata) {
    return metadata.title.trim().isEmpty ||
        metadata.artistName.trim().isEmpty ||
        metadata.albumTitle.trim().isEmpty;
  }

  AudioMetadata _merge(AudioMetadata primary, AudioMetadata fallback) {
    return AudioMetadata(
      title: _preferText(primary.title, fallback.title),
      artistName: _preferText(primary.artistName, fallback.artistName),
      albumTitle: _preferText(primary.albumTitle, fallback.albumTitle),
      albumArtistName: _preferOptionalText(
        primary.albumArtistName,
        fallback.albumArtistName,
      ),
      durationSeconds: primary.durationSeconds > 0
          ? primary.durationSeconds
          : fallback.durationSeconds,
      trackNumber: primary.trackNumber > 0
          ? primary.trackNumber
          : fallback.trackNumber,
      discNumber: primary.discNumber >= 0
          ? primary.discNumber
          : fallback.discNumber,
      isSingle: primary.isSingle,
      featuredArtists: primary.featuredArtists,
      releaseDate: primary.releaseDate ?? fallback.releaseDate,
      genre: _preferOptionalText(primary.genre, fallback.genre),
    );
  }

  String _preferText(String primary, String fallback) {
    final cleaned = primary.trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  String? _preferOptionalText(String? primary, String? fallback) {
    final cleaned = primary?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return fallback;
    }

    return cleaned;
  }
}
