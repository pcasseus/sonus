import '../../application/models/library_artist.dart';
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
