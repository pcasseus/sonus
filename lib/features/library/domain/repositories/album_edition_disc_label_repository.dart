import '../entities/album_edition_disc_label.dart';

/// Disc names, per edition and disc number (REF-13c). Local only.
abstract interface class AlbumEditionDiscLabelRepository {
  Future<List<AlbumEditionDiscLabel>> getByEditionId(String editionId);

  /// Names [label]'s disc, replacing any name it had.
  Future<void> save(AlbumEditionDiscLabel label);

  Future<void> delete({required String editionId, required int discNumber});

  /// Forgets the names of [editionId]'s discs other than [discs]: a disc
  /// with no songs left loses its name, so a new disc with that number
  /// later starts unnamed.
  Future<void> keepOnly({required String editionId, required Set<int> discs});
}
