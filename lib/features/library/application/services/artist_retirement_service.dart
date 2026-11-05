import '../../domain/repositories/artist_reference_repository.dart';
import '../models/library_artist.dart';

/// Safe artist retirement (UI redesign A1, decision D8): which artists are
/// in use, which are kept only for history, and which could be removed.
///
/// Derived on every call from what refers to each artist, so nothing is
/// stored and nothing changes: an import or edit that uses a retired artist
/// again makes it active at once. Only reads; never deletes anything.
class ArtistRetirementService {
  /// [_repository] opens the read-only reference lookups when needed.
  ArtistRetirementService(this._repository);

  final Future<ArtistReferenceSummaryRepository> Function() _repository;

  /// Every stored artist with its state and reference counts.
  Future<List<ArtistReferenceSummary>> classifyAll() async {
    return (await _repository()).summarizeAll();
  }

  /// Ids of artists kept only for history.
  Future<Set<String>> retiredArtistIds() async {
    return (await _repository()).findRetiredArtistIds();
  }

  /// [artists] without the retired ones, for pickers and search: a retired
  /// artist is not offered for new songs or credits. Active artists, and
  /// artists not yet used (such as one just created in a picker), stay.
  Future<List<LibraryArtist>> withoutRetired(
    List<LibraryArtist> artists,
  ) async {
    final retired = await retiredArtistIds();
    if (retired.isEmpty) {
      return artists;
    }
    return artists
        .where((artist) => !retired.contains(artist.artistId))
        .toList(growable: false);
  }
}
