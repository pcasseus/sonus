import '../entities/song_single_presentation.dart';

/// Songs' Single presentations (App Update 1.3, REF-1.3-04). Local only:
/// kept in backups, never synced.
abstract interface class SongSinglePresentationRepository {
  /// The song's presentation with its cover file, or null when none.
  Future<SongSinglePresentation?> getBySongId(String songId);

  /// Every presentation with its cover file, by Song ID (one query).
  Future<Map<String, SongSinglePresentation>> getAll();

  /// Stores [presentation], replacing the song's previous one. An empty
  /// presentation removes the row. Never touches `songs.is_single`, the
  /// song, its album or its artwork.
  Future<void> save(SongSinglePresentation presentation);

  /// Removes the song's presentation (the listener cleared it).
  Future<void> clear(String songId);
}
