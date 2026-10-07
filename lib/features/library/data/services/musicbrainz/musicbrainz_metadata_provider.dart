import '../../../application/models/external_metadata_candidate.dart';
import '../../../application/models/external_metadata_search_query.dart';
import '../../../application/services/metadata_provider.dart';
import 'musicbrainz_api_client.dart';

class MusicBrainzMetadataProvider implements MetadataProvider {
  const MusicBrainzMetadataProvider({required this.client});

  final MusicBrainzApiClient client;

  @override
  ExternalMetadataProviderKind get providerKind =>
      ExternalMetadataProviderKind.musicBrainz;

  @override
  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  ) async {
    if (query.isBlank) {
      return const [];
    }

    switch (query.entityKind) {
      case ExternalMetadataEntityKind.artist:
        return _searchArtists(query);

      case ExternalMetadataEntityKind.album:
        return _searchReleaseGroups(query);

      case ExternalMetadataEntityKind.track:
        return _searchRecordings(query);
    }
  }

  @override
  Future<ExternalMetadataCandidate?> lookup({
    required ExternalMetadataEntityKind entityKind,
    required String providerEntityId,
  }) async {
    final normalizedId = providerEntityId.trim();

    if (normalizedId.isEmpty) {
      return null;
    }

    switch (entityKind) {
      case ExternalMetadataEntityKind.artist:
        final json = await client.lookup(
          entity: MusicBrainzEntity.artist,
          id: normalizedId,
        );

        return _mapArtist(json);

      case ExternalMetadataEntityKind.album:
        final json = await client.lookup(
          entity: MusicBrainzEntity.releaseGroup,
          id: normalizedId,
          includes: const ['artist-credits', 'releases'],
        );

        return _mapReleaseGroup(json);

      case ExternalMetadataEntityKind.track:
        final json = await client.lookup(
          entity: MusicBrainzEntity.recording,
          id: normalizedId,
          includes: const ['artist-credits', 'releases'],
        );

        return _mapRecording(json);
    }
  }

  Future<List<ExternalMetadataCandidate>> _searchArtists(
    ExternalMetadataSearchQuery query,
  ) async {
    final artistName = _trimmed(query.artistName) ?? _trimmed(query.title);

    if (artistName == null) {
      return const [];
    }

    final json = await client.search(
      entity: MusicBrainzEntity.artist,
      query: 'artist:${_lucenePhrase(artistName)}',
      limit: _normalizedLimit(query.limit),
    );

    return _mapList(json['artists'], _mapArtist);
  }

  Future<List<ExternalMetadataCandidate>> _searchReleaseGroups(
    ExternalMetadataSearchQuery query,
  ) async {
    final albumTitle = _trimmed(query.albumTitle) ?? _trimmed(query.title);

    if (albumTitle == null) {
      return const [];
    }

    final clauses = <String>['releasegroup:${_lucenePhrase(albumTitle)}'];

    final artistName = _trimmed(query.artistName);

    if (artistName != null) {
      clauses.add('artist:${_lucenePhrase(artistName)}');
    }

    final json = await client.search(
      entity: MusicBrainzEntity.releaseGroup,
      query: clauses.join(' AND '),
      limit: _normalizedLimit(query.limit),
    );

    return _mapList(json['release-groups'], _mapReleaseGroup);
  }

  Future<List<ExternalMetadataCandidate>> _searchRecordings(
    ExternalMetadataSearchQuery query,
  ) async {
    final title = _trimmed(query.title);

    if (title == null) {
      return const [];
    }

    final clauses = <String>['recording:${_lucenePhrase(title)}'];

    final artistName = _trimmed(query.artistName);
    final albumTitle = _trimmed(query.albumTitle);

    if (artistName != null) {
      clauses.add('artist:${_lucenePhrase(artistName)}');
    }

    if (albumTitle != null) {
      clauses.add('release:${_lucenePhrase(albumTitle)}');
    }

    final json = await client.search(
      entity: MusicBrainzEntity.recording,
      query: clauses.join(' AND '),
      limit: _normalizedLimit(query.limit),
    );

    return _mapList(json['recordings'], _mapRecording);
  }

  ExternalMetadataCandidate? _mapArtist(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final name = _string(json['name']);

    if (id == null || name == null) {
      return null;
    }

    final externalIds = <String, String>{'musicBrainzArtistId': id};

    final sortName = _string(json['sort-name']);
    final disambiguation = _string(json['disambiguation']);
    final country = _string(json['country']);
    final type = _string(json['type']);

    if (sortName != null) {
      externalIds['musicBrainzArtistSortName'] = sortName;
    }

    if (disambiguation != null) {
      externalIds['musicBrainzArtistDisambiguation'] = disambiguation;
    }

    if (country != null) {
      externalIds['musicBrainzArtistCountry'] = country;
    }

    return ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.artist,
      providerEntityId: id,
      displayName: name,
      primaryType: type,
      externalIds: externalIds,
    );
  }

  ExternalMetadataCandidate? _mapReleaseGroup(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final title = _string(json['title']);

    if (id == null || title == null) {
      return null;
    }

    final releases = _maps(json['releases']);
    final primaryRelease = releases.isEmpty ? null : releases.first;
    final releaseId = primaryRelease == null
        ? null
        : _string(primaryRelease['id']);

    final releaseDate =
        _parsePartialDate(json['first-release-date']) ??
        (primaryRelease == null
            ? null
            : _parsePartialDate(primaryRelease['date']));

    final externalIds = <String, String>{'musicBrainzReleaseGroupId': id};

    if (releaseId != null) {
      externalIds['musicBrainzReleaseId'] = releaseId;
    }

    return ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.album,
      providerEntityId: id,
      displayName: title,
      artistCredits: _artistCredits(json['artist-credit']),
      releaseTitle: title,
      releaseId: releaseId,
      releaseGroupId: id,
      releaseDate: releaseDate,
      primaryType: _string(json['primary-type']),
      secondaryTypes: _strings(json['secondary-types']),
      externalIds: externalIds,
    );
  }

  ExternalMetadataCandidate? _mapRecording(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final title = _string(json['title']);

    if (id == null || title == null) {
      return null;
    }

    final releases = _maps(json['releases']);
    final release = releases.isEmpty ? null : releases.first;

    final releaseId = release == null ? null : _string(release['id']);
    final releaseTitle = release == null ? null : _string(release['title']);

    final releaseGroup = release == null
        ? null
        : _mapValue(release['release-group']);

    final releaseGroupId = releaseGroup == null
        ? null
        : _string(releaseGroup['id']);

    final firstReleaseDate =
        _parsePartialDate(json['first-release-date']) ??
        (release == null ? null : _parsePartialDate(release['date']));

    final externalIds = <String, String>{'musicBrainzRecordingId': id};

    if (releaseId != null) {
      externalIds['musicBrainzReleaseId'] = releaseId;
    }

    if (releaseGroupId != null) {
      externalIds['musicBrainzReleaseGroupId'] = releaseGroupId;
    }

    return ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.track,
      providerEntityId: id,
      displayName: title,
      artistCredits: _artistCredits(json['artist-credit']),
      releaseTitle: releaseTitle,
      releaseId: releaseId,
      releaseGroupId: releaseGroupId,
      durationSeconds: _durationSeconds(json['length']),
      releaseDate: firstReleaseDate,
      primaryType: releaseGroup == null
          ? null
          : _string(releaseGroup['primary-type']),
      secondaryTypes: releaseGroup == null
          ? const []
          : _strings(releaseGroup['secondary-types']),
      externalIds: externalIds,
    );
  }

  List<ExternalMetadataArtistCredit> _artistCredits(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    final credits = <ExternalMetadataArtistCredit>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final entry = Map<String, dynamic>.from(item);
      final artist = _mapValue(entry['artist']);

      final creditedName =
          _string(entry['name']) ??
          (artist == null ? null : _string(artist['name']));

      if (creditedName == null) {
        continue;
      }

      credits.add(
        ExternalMetadataArtistCredit(
          name: creditedName,
          providerArtistId: artist == null ? null : _string(artist['id']),
          joinPhrase: _rawString(entry['joinphrase']) ?? '',
        ),
      );
    }

    return List.unmodifiable(credits);
  }

  List<ExternalMetadataCandidate> _mapList(
    Object? raw,
    ExternalMetadataCandidate? Function(Map<String, dynamic>) mapper,
  ) {
    if (raw is! List) {
      return const [];
    }

    final result = <ExternalMetadataCandidate>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final candidate = mapper(Map<String, dynamic>.from(item));

      if (candidate != null) {
        result.add(candidate);
      }
    }

    return List.unmodifiable(result);
  }

  static int _normalizedLimit(int limit) {
    if (limit < 1) {
      return 1;
    }

    if (limit > 100) {
      return 100;
    }

    return limit;
  }

  static String _lucenePhrase(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

    return '"$escaped"';
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  static String? _string(Object? value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();

    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _rawString(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return value;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) {
      return const [];
    }

    return List.unmodifiable(
      value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static Map<String, dynamic>? _mapValue(Object? value) {
    if (value is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(value);
  }

  static int? _durationSeconds(Object? length) {
    if (length is! num || length < 0) {
      return null;
    }

    return (length / 1000).round();
  }

  static DateTime? _parsePartialDate(Object? value) {
    final raw = _string(value);

    if (raw == null) {
      return null;
    }

    final parts = raw.split('-');

    if (parts.isEmpty || parts.length > 3) {
      return null;
    }

    final year = int.tryParse(parts[0]);

    if (year == null || year < 1) {
      return null;
    }

    final month = parts.length >= 2 ? int.tryParse(parts[1]) : 1;
    final day = parts.length >= 3 ? int.tryParse(parts[2]) : 1;

    if (month == null ||
        day == null ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }

    try {
      final parsed = DateTime.utc(year, month, day);

      if (parsed.year != year || parsed.month != month || parsed.day != day) {
        return null;
      }

      return parsed;
    } on ArgumentError {
      return null;
    }
  }
}
