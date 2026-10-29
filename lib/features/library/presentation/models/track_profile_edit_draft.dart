import '../../../../core/identity/text_normalizer.dart';
import '../../application/models/library_artist.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/song_artist_credit.dart';

typedef TrackArtistCreationCallback =
    Future<LibraryArtist?> Function(String name);

class TrackProfileCreditDraft {
  const TrackProfileCreditDraft({
    required this.creditedName,
    required this.role,
    this.artistId,
  }) : assert(
         role != SongArtistCreditRole.primary,
         'Additional Track Studio credits cannot use the primary role.',
       );

  final String creditedName;
  final SongArtistCreditRole role;
  final String? artistId;

  /// The credit to save. Track Studio links credits only to an artist the
  /// person chose, never by a matching name alone (SN-50 C-Q2).
  SongArtistCreditInput toInput() {
    return SongArtistCreditInput(
      creditedName: creditedName,
      role: role,
      artistId: artistId,
      linkByName: false,
    );
  }
}

/// The credits Track Studio starts from (SN-50 C-Q4): the song's structured
/// [credits] in order, plus its older [legacyFeaturedArtists] names when it
/// has no structured featured credit, so saving never silently drops them.
/// Only the song being edited is affected, and only when it is saved.
List<TrackProfileCreditDraft> trackStudioInitialCredits({
  required Iterable<SongArtistCredit> credits,
  required List<String> legacyFeaturedArtists,
  required String primaryArtistId,
  required String primaryArtistName,
}) {
  final ordered = [
    for (final credit in credits)
      if (credit.role != SongArtistCreditRole.primary) credit,
  ]..sort((left, right) => left.position.compareTo(right.position));
  final drafts = [
    for (final credit in ordered)
      TrackProfileCreditDraft(
        creditedName: credit.creditedName,
        role: credit.role,
        artistId: credit.artistId,
      ),
  ];

  if (ordered.any((credit) => credit.role == SongArtistCreditRole.featured)) {
    return drafts;
  }

  final identities = SongCreditIdentitySet(
    primaryArtistId: primaryArtistId,
    primaryCanonicalName: TextNormalizer.canonicalize(primaryArtistName),
  );

  for (final draft in drafts) {
    identities.add(
      canonicalName: TextNormalizer.canonicalize(draft.creditedName),
      artistId: draft.artistId,
    );
  }

  for (final name in legacyFeaturedArtists) {
    final trimmed = name.trim();
    final canonicalName = TextNormalizer.canonicalize(trimmed);

    if (canonicalName.isNotEmpty &&
        identities.add(canonicalName: canonicalName)) {
      drafts.add(
        TrackProfileCreditDraft(
          creditedName: trimmed,
          role: SongArtistCreditRole.featured,
        ),
      );
    }
  }

  return drafts;
}

class TrackProfileEditDraft {
  const TrackProfileEditDraft({
    required this.title,
    required this.trackNumber,
    required this.discNumber,
    required this.featuredArtists,
    this.additionalCredits = const [],
    required this.isSingle,
    this.versionLabel,
    this.versionCharacteristics = const [],
    this.releaseStatus = SongReleaseStatus.released,
    this.isLeak = false,
    required this.artistId,
    required this.albumId,
    this.moveToEditionId,
    this.placementEditionId,
  });

  final String title;
  final int trackNumber;
  final int discNumber;
  final List<String> featuredArtists;
  final List<TrackProfileCreditDraft> additionalCredits;
  final bool isSingle;

  final String? versionLabel;
  final List<SongVersionCharacteristic> versionCharacteristics;
  final SongReleaseStatus releaseStatus;
  final bool isLeak;
  final String artistId;
  final String albumId;

  /// The edition a track moves into. Set only when the user chose another
  /// album; an ordinary save leaves it null, so no edition membership
  /// changes.
  final String? moveToEditionId;

  /// The edition listing the editor was opened from. Disc and track number
  /// edits apply to that listing only.
  final String? placementEditionId;
}
