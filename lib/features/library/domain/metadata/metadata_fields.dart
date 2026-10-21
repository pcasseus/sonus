abstract final class MetadataFields {
  // Artist
  static const String artistName = 'name';
  static const String artistHeaderArtwork = 'headerArtworkId';
  static const String artistTopArtistsArtwork = 'topArtistsArtworkId';

  // Album
  static const String albumArtist = 'artistId';
  static const String albumTitle = 'title';

  // Album edition
  static const String editionTitle = 'title';
  static const String editionType = 'type';
  static const String editionReleaseDate = 'releaseDate';
  static const String editionGenre = 'genre';
  static const String editionArtwork = 'artworkId';

  // Song
  static const String songArtist = 'artistId';
  static const String songArtistCredits = 'artistCredits';
  static const String songAlbum = 'albumId';
  static const String songAlbumEdition = 'albumEditionId';
  static const String songTitle = 'title';
  static const String songTrackNumber = 'trackNumber';
  static const String songDiscNumber = 'discNumber';
  static const String songDuration = 'durationSeconds';
  static const String songIsSingle = 'isSingle';
  static const String songArtwork = 'artworkId';
  static const String songVersionLabel = 'versionLabel';
  static const String songVersionCharacteristics = 'versionCharacteristics';
  static const String songReleaseStatus = 'releaseStatus';
  static const String songIsLeak = 'isLeak';
}
