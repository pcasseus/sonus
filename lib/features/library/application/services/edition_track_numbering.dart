import '../../../sync/application/services/sync_mutation_context.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album_edition_track.dart';
import '../../domain/services/album_edition_track_order.dart';

/// What renumbering an edition's tracks did.
class EditionRenumberResult {
  const EditionRenumberResult({
    required this.renumbered,
    required this.manualNumbersKept,
  });

  static const EditionRenumberResult none = EditionRenumberResult(
    renumbered: 0,
    manualNumbersKept: 0,
  );

  /// Listings whose track number changed.
  final int renumbered;

  /// Listings the user numbered by hand whose number renumbering would
  /// change. They were left as they are; only the user can approve
  /// changing them (SN-50 A-Q7A).
  final int manualNumbersKept;
}

/// The edition's listings in the order they are shown: the hand-made order
/// when someone reordered the edition, otherwise disc then track number.
/// Matches `editionTrackOrderBy`.
List<AlbumEditionTrack> editionTracksInShownOrder(
  Iterable<AlbumEditionTrack> memberships,
) {
  final reordered = memberships.any(
    (m) => m.orderingAuthority == AlbumEditionTrackAuthority.manual,
  );

  return [...memberships]..sort(
    reordered
        ? (a, b) {
            final position = a.sortPosition.compareTo(b.sortPosition);
            return position != 0 ? position : compareByDiscAndTrack(a, b);
          }
        : compareByDiscAndTrack,
  );
}

/// The disc a listing is shown on; unknown discs show as disc 1.
int shownDiscOf(AlbumEditionTrack membership) =>
    membership.discNumber <= 0 ? 1 : membership.discNumber;

/// Numbers the edition's tracks 1, 2, 3… on each disc, in the order they
/// are shown (SN-50 A3, A-Q7B), so removing songs never leaves gaps.
///
/// Only inferred numbers change unless [overwriteManual] is set; the rest
/// are counted in [EditionRenumberResult.manualNumbersKept]. Tracks with an
/// unknown number (0) keep it and are not counted. Listings of [exclude]
/// keep their number but still take their place in the count. Each changed
/// listing queues its song for sync, and the song's own copy of its number
/// follows when this is its home edition.
Future<EditionRenumberResult> renumberEditionTracks(
  SyncMutationContext context, {
  required String editionId,
  required String? userId,
  required DateTime timestamp,
  bool overwriteManual = false,
  Set<String> exclude = const {},
}) async {
  final memberships = editionTracksInShownOrder(
    await context.albumEditionTrackRepository.getByEditionId(editionId),
  );
  final nextByDisc = <int, int>{};
  var renumbered = 0;
  var manualNumbersKept = 0;

  for (final membership in memberships) {
    if (membership.trackNumber <= 0) continue;

    final target = nextByDisc.update(
      shownDiscOf(membership),
      (number) => number + 1,
      ifAbsent: () => 1,
    );

    if (membership.trackNumber == target ||
        exclude.contains(membership.songId)) {
      continue;
    }

    if (membership.numberingAuthority == AlbumEditionTrackAuthority.manual &&
        !overwriteManual) {
      manualNumbersKept++;
      continue;
    }

    await context.albumEditionTrackRepository.save(
      membership.copyWith(trackNumber: target, updatedAt: timestamp),
    );

    final song = await context.songRepository.getById(membership.songId);
    if (song != null &&
        song.albumEditionId == editionId &&
        song.trackNumber != target) {
      await context.songRepository.save(
        song.copyWith(trackNumber: target, updatedAt: timestamp),
      );
    }

    await context.localSyncRepository.recordUpsert(
      userId: userId?.trim(),
      entityType: CloudDataEntity.song,
      entityId: membership.songId,
    );
    renumbered++;
  }

  return EditionRenumberResult(
    renumbered: renumbered,
    manualNumbersKept: manualNumbersKept,
  );
}
