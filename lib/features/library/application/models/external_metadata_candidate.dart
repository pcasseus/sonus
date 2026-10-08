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

  final String? releaseTitle;
  final String? releaseId;
  final String? releaseGroupId;

  final int? durationSeconds;
  final DateTime? releaseDate;

  final String? primaryType;
  final List<String> secondaryTypes;

  /// Additional typed provider identities that may be useful for later
  /// lookups, persistence, and Cover Art Archive integration.
  final Map<String, String> externalIds;

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
