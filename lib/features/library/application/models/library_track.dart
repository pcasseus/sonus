import '../../domain/entities/album_edition.dart';
import '../../domain/entities/song.dart';
import 'release_display_title.dart';
import 'song_credit_line.dart';
import 'song_display_title.dart';

class LibraryTrack {
  const LibraryTrack({
    required this.songId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    this.primaryEditionTitle,
    required this.albumEditionId,
    required this.albumEditionTitle,
    required this.albumEditionType,
    required this.trackNumber,
    this.discNumber = 1,
    required this.durationSeconds,
    required this.isSingle,
    required this.featuredArtists,
    this.coPrimaryArtists = const [],
    this.guestArtists = const [],
    this.versionLabel,
    this.versionCharacteristics = const [],
    this.releaseStatus = SongReleaseStatus.released,
    this.isLeak = false,
    required this.dateAdded,
    required this.isAvailable,
    this.isSongBlocked = false,
    this.filePath,
    this.artworkId,
    this.artworkPath,
  });

  final String songId;
  final String title;

  final String artistId;
  final String artistName;

  final String albumId;

  /// The release's stored base title. Charts and listening history record
  /// this one, so it must not follow the primary edition.
  final String albumTitle;

  /// The release's primary edition title, when read.
  final String? primaryEditionTitle;

  /// The release title shown in current lists (SN-50 A-Q3).
  String get albumDisplayTitle => releaseDisplayTitle(
    baseTitle: albumTitle,
    editionTitle: primaryEditionTitle,
  );

  final String albumEditionId;
  final String albumEditionTitle;
  final AlbumEditionType albumEditionType;

  final int trackNumber;
  final int discNumber;
  final int durationSeconds;
  final bool isSingle;
  final List<String> featuredArtists;

  /// Structured co-primary and guest credit names, in credit order.
  final List<String> coPrimaryArtists;
  final List<String> guestArtists;

  /// The role-aware performer line shown in lists and playback.
  String get creditLine => songCreditLine(
    primaryArtistName: artistName,
    coPrimaryArtists: coPrimaryArtists,
    featuredArtists: featuredArtists,
    guestArtists: guestArtists,
  );

  /// The credit line for a row on a page that already names the release
  /// artist: "Ft. Cy with Eve", co-primaries kept, or empty.
  String get releaseCreditLine => songCreditLine(
    primaryArtistName: artistName,
    coPrimaryArtists: coPrimaryArtists,
    featuredArtists: featuredArtists,
    guestArtists: guestArtists,
    omitPrimary: true,
  );

  /// The title with its version qualifier, for current surfaces only.
  String get displayTitle => songDisplayTitle(
    title: title,
    versionLabel: versionLabel,
    characteristics: versionCharacteristics,
  );

  final String? versionLabel;
  final List<SongVersionCharacteristic> versionCharacteristics;
  final SongReleaseStatus releaseStatus;
  final bool isLeak;
  final DateTime dateAdded;

  final String? filePath;
  final bool isAvailable;

  final bool isSongBlocked;

  bool get isBlocked => isSongBlocked;

  final String? artworkId;
  final String? artworkPath;
}
