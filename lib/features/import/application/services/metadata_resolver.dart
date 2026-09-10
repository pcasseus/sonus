import '../../domain/models/audio_metadata.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/services/audio_metadata_reader.dart';

class MetadataResolver {
  const MetadataResolver({
    required this.primaryReader,
    required this.fallbackReader,
  });

  final AudioMetadataReader primaryReader;
  final AudioMetadataReader fallbackReader;

  Future<AudioMetadata> resolve(ImportCandidate candidate) async {
    try {
      return await primaryReader.read(candidate);
    } catch (_) {
      return fallbackReader.read(candidate);
    }
  }
}
