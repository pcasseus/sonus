/// The name a listener gave one disc of an edition, such as "Bonus Tracks"
/// (App Update 1.2, REF-13c).
///
/// It belongs to the disc number on that edition, not to the songs on it,
/// so reordering songs or moving them between discs leaves it in place.
class AlbumEditionDiscLabel {
  const AlbumEditionDiscLabel({
    required this.albumEditionId,
    required this.discNumber,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  final String albumEditionId;

  /// 1 or more.
  final int discNumber;

  /// Never blank.
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// "Disc 2" or "Disc 2 — Bonus Tracks".
String discTitle(int disc, {String? label}) {
  final name = label?.trim();
  return name == null || name.isEmpty ? 'Disc $disc' : 'Disc $disc — $name';
}
