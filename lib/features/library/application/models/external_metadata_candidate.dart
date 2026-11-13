import '../../domain/services/genre_catalog.dart';
import '../../domain/entities/release_date.dart';
import 'external_metadata_search_query.dart';

enum ExternalMetadataProviderKind { musicBrainz }

class ExternalMetadataArtistCredit {
  const ExternalMetadataArtistCredit({
    required this.name,
    this.providerArtistId,
    this.joinPhrase = '',
  });

  final String name;
  final String? providerArtistId;
  final String joinPhrase;
}

/// One specific release a candidate appears on: a Standard, a Deluxe, a
/// regional or a compilation release, with the track's place on it when the
/// provider reports one.
class ExternalMetadataReleaseOption {
  const ExternalMetadataReleaseOption({
    required this.releaseId,
    required this.title,
    this.releaseGroupId,
    this.releaseDate,
    this.country,
    this.status,
    this.mediumPosition,
    this.trackNumber,
    this.trackCount,
  });

  final String releaseId;
  final String title;
  final String? releaseGroupId;

  /// As exact as MusicBrainz knows it: a year, a month or a day.
  final ReleaseDate? releaseDate;
  final String? country;
  final String? status;

  /// Disc (medium) the track is on, when known.
  final int? mediumPosition;

  /// The track's number on that medium, when known.
  final int? trackNumber;

  /// Tracks on the release, when known.
  final int? trackCount;
}

/// A genre MusicBrainz lists for a release group, with how many editors
/// voted for it (App Update 1.2, REF-17).
class ExternalMetadataGenre {
  const ExternalMetadataGenre({required this.name, required this.count});

  final String name;
  final int count;
}

class ExternalMetadataCandidate {
  const ExternalMetadataCandidate({
    required this.provider,
    required this.entityKind,
    required this.providerEntityId,
    required this.displayName,
    this.artistCredits = const [],
    this.releaseTitle,
    this.releaseId,
    this.releaseGroupId,
    this.durationSeconds,
    this.releaseDate,
    this.primaryType,
    this.secondaryTypes = const [],
    this.externalIds = const {},
    this.releaseOptions = const [],
    this.genres = const [],
  });

  final ExternalMetadataProviderKind provider;
  final ExternalMetadataEntityKind entityKind;

  /// Primary provider identity for this candidate.
  ///
  /// For MusicBrainz this is normally an Artist MBID, Recording MBID,
  /// Release MBID, or Release Group MBID depending on [entityKind].
  final String providerEntityId;

  final String displayName;
  final List<ExternalMetadataArtistCredit> artistCredits;

  /// The release, only when the provider's answer names exactly one.
  /// A recording or release group usually spans several releases; choosing
  /// one is [releaseOptions]' job, never "the first".
  final String? releaseTitle;
  final String? releaseId;

  /// Set when every release shares one release group.
  final String? releaseGroupId;

  /// Every release the provider listed, in its order.
  final List<ExternalMetadataReleaseOption> releaseOptions;

  final int? durationSeconds;

  /// The first release date, as exact as MusicBrainz knows it.
  final ReleaseDate? releaseDate;

  final String? primaryType;
  final List<String> secondaryTypes;

  /// Additional typed provider identities that may be useful for later
  /// lookups, persistence, and Cover Art Archive integration.
  final Map<String, String> externalIds;

  /// Genres MusicBrainz lists, most votes first. Only an album looked up
  /// by its identity has them; search results do not.
  final List<ExternalMetadataGenre> genres;

  /// The genre category to suggest, or null when MusicBrainz's genres do
  /// not name exactly one (see [GenreCatalog.fromVotes]).
  String? get suggestedGenre => GenreCatalog.fromVotes([
    for (final genre in genres) (genre.name, genre.count),
  ]);

  String get sourceReference {
    switch (provider) {
      case ExternalMetadataProviderKind.musicBrainz:
        switch (entityKind) {
          case ExternalMetadataEntityKind.artist:
            return 'musicbrainz:artist:$providerEntityId';
          case ExternalMetadataEntityKind.album:
            return 'musicbrainz:release-group:$providerEntityId';
          case ExternalMetadataEntityKind.track:
            return 'musicbrainz:recording:$providerEntityId';
        }
    }
  }
}
