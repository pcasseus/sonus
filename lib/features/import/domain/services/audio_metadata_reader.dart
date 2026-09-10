import '../models/audio_metadata.dart';
import '../models/import_candidate.dart';

abstract interface class AudioMetadataReader {
  Future<AudioMetadata> read(ImportCandidate candidate);
}
