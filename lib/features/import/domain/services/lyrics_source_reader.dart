import '../models/import_candidate.dart';

abstract interface class LyricsSourceReader {
  Future<String?> read(ImportCandidate candidate);
}
