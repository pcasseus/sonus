import '../../domain/entities/album_edition.dart';

/// One edition of an album and the songs it lists.
class EditionListing {
  const EditionListing({
    required this.editionId,
    required this.title,
    required this.type,
    required this.createdAt,
    required this.songIds,
  });

  final String editionId;
  final String title;
  final AlbumEditionType type;
  final DateTime createdAt;
  final Set<String> songIds;
}

/// Songs on one edition that another edition might also want.
class EditionFollowUp {
  const EditionFollowUp({
    required this.sourceEditionId,
    required this.targetEditionId,
    required this.targetTitle,
    required this.songIds,
  });

  final String sourceEditionId;
  final String targetEditionId;
  final String targetTitle;

  /// In the source edition's order.
  final List<String> songIds;
}

/// When a song joins an edition (say Standard), which other editions
/// (say Deluxe) should be offered it too.
///
/// An edition "builds on" another when it lists every song of it, as a
/// Deluxe made from Standard does. Only those editions are offered new
/// songs; nothing is ever added without the user's choice.
abstract final class EditionFollowUps {
  /// Editions that listed every song of [source] before [added] joined it
  /// and do not list all of [added] yet. [source] holds the listing before
  /// the change.
  static List<EditionFollowUp> afterAdding({
    required EditionListing source,
    required List<EditionListing> others,
    required List<String> added,
  }) {
    if (added.isEmpty || source.songIds.isEmpty) {
      return const [];
    }

    return [
      for (final other in others)
        if (other.editionId != source.editionId &&
            other.songIds.containsAll(source.songIds))
          if (_missing(other, added) case final missing when missing.isNotEmpty)
            EditionFollowUp(
              sourceEditionId: source.editionId,
              targetEditionId: other.editionId,
              targetTitle: other.title,
              songIds: missing,
            ),
    ];
  }

  /// Songs added to a Standard edition after another edition was built on
  /// it, for example new Standard songs imported after Deluxe was created.
  ///
  /// [target] must list every other song of [source]; only songs added
  /// after [target] was created count, so songs deliberately left off
  /// [target] when it was made are not offered. [addedAt] gives when each
  /// song joined the library. [dismissed] songs are not offered again.
  static List<EditionFollowUp> laterAdditions({
    required List<EditionListing> editions,
    required List<String> Function(String editionId) orderOf,
    required DateTime? Function(String songId) addedAt,
    Set<String> Function(String targetEditionId)? dismissed,
  }) {
    final result = <EditionFollowUp>[];

    for (final source in editions) {
      for (final target in editions) {
        // Only a Standard edition's additions are offered, to an edition
        // made after it (a Deluxe built on it). The other way round would
        // offer Deluxe-only songs to Standard.
        if (target.editionId == source.editionId ||
            source.type != AlbumEditionType.standard ||
            target.type == AlbumEditionType.standard ||
            !target.createdAt.isAfter(source.createdAt)) {
          continue;
        }

        final gap = source.songIds.difference(target.songIds);
        final shared = source.songIds.intersection(target.songIds);

        // Built on: it lists every older song of the source.
        if (gap.isEmpty || shared.isEmpty) continue;

        final newer = gap.where((songId) {
          final added = addedAt(songId);
          return added != null && added.isAfter(target.createdAt);
        }).toSet();

        if (newer.length != gap.length) continue;

        final hidden = dismissed?.call(target.editionId) ?? const <String>{};
        final offered = [
          for (final songId in orderOf(source.editionId))
            if (newer.contains(songId) && !hidden.contains(songId)) songId,
        ];

        if (offered.isNotEmpty) {
          result.add(
            EditionFollowUp(
              sourceEditionId: source.editionId,
              targetEditionId: target.editionId,
              targetTitle: target.title,
              songIds: offered,
            ),
          );
        }
      }
    }

    return result;
  }

  static List<String> _missing(EditionListing edition, List<String> songIds) {
    final seen = <String>{};
    return [
      for (final songId in songIds)
        if (!edition.songIds.contains(songId) && seen.add(songId)) songId,
    ];
  }
}
