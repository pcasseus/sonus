import '../../application/models/chart_moment_feed_item.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';

/// How a story's pictures are arranged, from what the headline is about.
enum MomentVisualLayout {
  /// A song story: the song's cover, then its artist.
  songAndArtist,

  /// An Album or EP story: the release's cover, then its owner.
  releaseAndOwner,

  /// One artist passing another: both portraits, in headline order.
  artistAndArtist,

  /// One song passing another: both covers, in headline order.
  songAndSong,

  /// One release passing another: both covers, in headline order.
  releaseAndRelease,

  /// A song by two credited artists: both portraits.
  collaboration,

  /// An artist on their own.
  singlePortrait,

  /// A release, or a song with three or more artists, on its own.
  singleCover,
}

enum MomentImageKind { cover, portrait }

/// One picture: what it shows (entity and kind) and the saved image, if
/// any. A missing image shows a placeholder, never someone else's picture.
class MomentImage {
  const MomentImage({required this.kind, required this.entityId, this.path});

  final MomentImageKind kind;

  /// The song, release or artist pictured.
  final String entityId;
  final String? path;

  bool get hasImage => path?.trim().isNotEmpty ?? false;
}

class MomentVisual {
  const MomentVisual({required this.layout, required this.left, this.right});

  final MomentVisualLayout layout;
  final MomentImage left;
  final MomentImage? right;
}

/// Chooses a story's pictures (SN-45): they show exactly who and what the
/// chosen headline names, from the library's own artwork. Nothing is
/// fetched online.
abstract final class MomentVisuals {
  static MomentVisual select({
    required ChartMomentFeedItem item,
    required MomentFamily family,
    required MomentFacts facts,
    required HeadlineVariant variant,
    required MomentLookups lookups,
    String? headline,
  }) {
    final entity = item.entity;
    final related = item.relatedEntity;
    final namesRival = variant.requires.contains(MomentFact.rival);

    MomentImage cover(String id, {required bool song}) => MomentImage(
      kind: MomentImageKind.cover,
      entityId: id,
      path: song ? lookups.songCover(id) : lookups.releaseCover(id),
    );
    MomentImage portrait(String id) => MomentImage(
      kind: MomentImageKind.portrait,
      entityId: id,
      path: lookups.artistPortrait(id),
    );

    switch (family) {
      case MomentFamily.artistTopArtist when related != null:
        return MomentVisual(
          layout: MomentVisualLayout.artistAndArtist,
          left: portrait(entity.entityId),
          right: portrait(related.entityId),
        );
      case MomentFamily.artistTopArtist || MomentFamily.artistStreamMilestone:
        return MomentVisual(
          layout: MomentVisualLayout.singlePortrait,
          left: portrait(entity.entityId),
        );
      case MomentFamily.artistSimultaneous:
        final artistId = entity.artistId;
        return artistId == null
            ? MomentVisual(
                layout: MomentVisualLayout.singleCover,
                left: cover(entity.entityId, song: true),
              )
            : MomentVisual(
                layout: MomentVisualLayout.singlePortrait,
                left: portrait(artistId),
              );
      default:
        break;
    }

    if (family.isRelease) {
      final release = cover(entity.entityId, song: false);
      if (namesRival && related != null) {
        return MomentVisual(
          layout: MomentVisualLayout.releaseAndRelease,
          left: release,
          right: cover(related.entityId, song: false),
        );
      }
      final ownerId = entity.artistId;
      if (family == MomentFamily.releaseStreamMilestone ||
          family == MomentFamily.releaseWeeksMilestone ||
          ownerId == null) {
        return MomentVisual(
          layout: MomentVisualLayout.singleCover,
          left: release,
        );
      }
      return MomentVisual(
        layout: MomentVisualLayout.releaseAndOwner,
        left: release,
        right: portrait(ownerId),
      );
    }

    // Songs.
    final song = cover(entity.entityId, song: true);
    if (namesRival && related != null) {
      return MomentVisual(
        layout: MomentVisualLayout.songAndSong,
        left: song,
        right: cover(related.entityId, song: true),
      );
    }

    final featured = lookups.featuredOf(entity.entityId);
    if (featured.length >= 2) {
      // Three or more artists: the cover pictures them all fairly.
      return MomentVisual(layout: MomentVisualLayout.singleCover, left: song);
    }

    final artistId = entity.artistId;
    // Both portraits only when the headline names both artists.
    final namesGuest =
        featured.length == 1 &&
        (headline ?? variant.build(facts)).contains(featured.single);
    if (namesGuest && artistId != null) {
      final guestId = lookups.artistIdNamed(featured.single);
      if (guestId != null && guestId != artistId) {
        return MomentVisual(
          layout: MomentVisualLayout.collaboration,
          left: portrait(artistId),
          right: portrait(guestId),
        );
      }
    }

    if (artistId == null) {
      return MomentVisual(layout: MomentVisualLayout.singleCover, left: song);
    }
    return MomentVisual(
      layout: MomentVisualLayout.songAndArtist,
      left: song,
      right: portrait(artistId),
    );
  }
}
