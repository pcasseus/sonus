import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_api_client.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_http_transport.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_metadata_provider.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_rate_limiter.dart';

void main() {
  group('MusicBrainzMetadataProvider', () {
    late FakeMusicBrainzHttpTransport transport;
    late MusicBrainzMetadataProvider provider;

    setUp(() {
      transport = FakeMusicBrainzHttpTransport();

      provider = MusicBrainzMetadataProvider(
        client: MusicBrainzApiClient(
          transport: transport,
          userAgent: 'Sonus/1.0.0 (provider tests)',
          rateLimiter: MusicBrainzRateLimiter(minimumInterval: Duration.zero),
        ),
      );
    });

    test(
      'blank search returns no candidates without network request',
      () async {
        final results = await provider.search(
          const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.track,
          ),
        );

        expect(results, isEmpty);
        expect(transport.requestCount, 0);
      },
    );

    test('artist search maps MusicBrainz identity', () async {
      transport.responseBody = '''
{
  "artists": [
    {
      "id": "artist-mbid",
      "name": "Beyoncé",
      "sort-name": "Beyoncé",
      "type": "Person",
      "country": "US",
      "disambiguation": "American singer"
    }
  ]
}
''';

      final results = await provider.search(
        const ExternalMetadataSearchQuery(
          entityKind: ExternalMetadataEntityKind.artist,
          artistName: 'Beyoncé',
        ),
      );

      expect(results, hasLength(1));

      final result = results.single;

      expect(transport.requestedUri!.path, '/ws/2/artist');
      expect(
        transport.requestedUri!.queryParameters['query'],
        'artist:"Beyoncé"',
      );

      expect(result.entityKind, ExternalMetadataEntityKind.artist);
      expect(result.providerEntityId, 'artist-mbid');
      expect(result.displayName, 'Beyoncé');
      expect(result.primaryType, 'Person');
      expect(result.externalIds['musicBrainzArtistId'], 'artist-mbid');
      expect(result.externalIds['musicBrainzArtistCountry'], 'US');
    });

    test(
      'album search maps release-group identity and artist credits',
      () async {
        transport.responseBody = '''
{
  "release-groups": [
    {
      "id": "release-group-mbid",
      "title": "Renaissance",
      "first-release-date": "2022-07-29",
      "primary-type": "Album",
      "secondary-types": [],
      "artist-credit": [
        {
          "name": "Beyoncé",
          "joinphrase": "",
          "artist": {
            "id": "artist-mbid",
            "name": "Beyoncé"
          }
        }
      ],
      "releases": [
        {
          "id": "release-mbid",
          "title": "Renaissance",
          "date": "2022-07-29"
        }
      ]
    }
  ]
}
''';

        final results = await provider.search(
          const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.album,
            albumTitle: 'Renaissance',
            artistName: 'Beyoncé',
          ),
        );

        expect(results, hasLength(1));

        final result = results.single;

        expect(transport.requestedUri!.path, '/ws/2/release-group');
        expect(
          transport.requestedUri!.queryParameters['query'],
          'releasegroup:"Renaissance" AND artist:"Beyoncé"',
        );

        expect(result.entityKind, ExternalMetadataEntityKind.album);
        expect(result.providerEntityId, 'release-group-mbid');
        expect(result.displayName, 'Renaissance');
        expect(result.releaseGroupId, 'release-group-mbid');
        expect(result.releaseId, 'release-mbid');
        expect(result.primaryType, 'Album');
        expect(result.releaseDate, DateTime.utc(2022, 7, 29));

        expect(result.artistCredits, hasLength(1));
        expect(result.artistCredits.single.name, 'Beyoncé');
        expect(result.artistCredits.single.providerArtistId, 'artist-mbid');
      },
    );

    test(
      'track search maps duration, credits, and release identities',
      () async {
        transport.responseBody = '''
{
  "recordings": [
    {
      "id": "recording-mbid",
      "title": "Alien Superstar",
      "length": 215826,
      "first-release-date": "2022-07-29",
      "artist-credit": [
        {
          "name": "Beyoncé",
          "joinphrase": " feat. ",
          "artist": {
            "id": "artist-primary",
            "name": "Beyoncé"
          }
        },
        {
          "name": "Guest Artist",
          "joinphrase": "",
          "artist": {
            "id": "artist-guest",
            "name": "Guest Artist"
          }
        }
      ],
      "releases": [
        {
          "id": "release-mbid",
          "title": "Renaissance",
          "date": "2022-07-29",
          "release-group": {
            "id": "release-group-mbid",
            "primary-type": "Album",
            "secondary-types": []
          }
        }
      ]
    }
  ]
}
''';

        final results = await provider.search(
          const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.track,
            title: 'Alien Superstar',
            artistName: 'Beyoncé',
            albumTitle: 'Renaissance',
          ),
        );

        expect(results, hasLength(1));

        final result = results.single;

        expect(transport.requestedUri!.path, '/ws/2/recording');

        expect(
          transport.requestedUri!.queryParameters['query'],
          'recording:"Alien Superstar" AND '
          'artist:"Beyoncé" AND '
          'release:"Renaissance"',
        );

        expect(result.entityKind, ExternalMetadataEntityKind.track);
        expect(result.providerEntityId, 'recording-mbid');
        expect(result.displayName, 'Alien Superstar');
        expect(result.durationSeconds, 216);
        expect(result.releaseTitle, 'Renaissance');
        expect(result.releaseId, 'release-mbid');
        expect(result.releaseGroupId, 'release-group-mbid');
        expect(result.releaseDate, DateTime.utc(2022, 7, 29));

        expect(result.artistCredits, hasLength(2));
        expect(result.artistCredits[0].name, 'Beyoncé');
        expect(result.artistCredits[0].joinPhrase, ' feat. ');
        expect(result.artistCredits[0].providerArtistId, 'artist-primary');
        expect(result.artistCredits[1].name, 'Guest Artist');

        expect(result.externalIds['musicBrainzRecordingId'], 'recording-mbid');
        expect(result.externalIds['musicBrainzReleaseId'], 'release-mbid');
        expect(
          result.externalIds['musicBrainzReleaseGroupId'],
          'release-group-mbid',
        );
      },
    );

    test('artist lookup maps direct entity response', () async {
      transport.responseBody = '''
{
  "id": "artist-mbid",
  "name": "Beyoncé",
  "type": "Person"
}
''';

      final result = await provider.lookup(
        entityKind: ExternalMetadataEntityKind.artist,
        providerEntityId: 'artist-mbid',
      );

      expect(result, isNotNull);
      expect(result!.providerEntityId, 'artist-mbid');
      expect(result.displayName, 'Beyoncé');

      expect(transport.requestedUri!.path, '/ws/2/artist/artist-mbid');
    });

    test('album lookup requests artist credits and releases', () async {
      transport.responseBody = '''
{
  "id": "release-group-mbid",
  "title": "Renaissance",
  "primary-type": "Album",
  "artist-credit": [],
  "releases": []
}
''';

      final result = await provider.lookup(
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: 'release-group-mbid',
      );

      expect(result, isNotNull);
      expect(result!.releaseGroupId, 'release-group-mbid');

      expect(
        transport.requestedUri!.queryParameters['inc'],
        'artist-credits+releases',
      );
    });

    test('track lookup requests artist credits and releases', () async {
      transport.responseBody = '''
{
  "id": "recording-mbid",
  "title": "Track",
  "length": 123456,
  "artist-credit": [],
  "releases": []
}
''';

      final result = await provider.lookup(
        entityKind: ExternalMetadataEntityKind.track,
        providerEntityId: 'recording-mbid',
      );

      expect(result, isNotNull);
      expect(result!.durationSeconds, 123);

      expect(
        transport.requestedUri!.queryParameters['inc'],
        'artist-credits+releases',
      );
    });

    test(
      'partial MusicBrainz date uses first day of available precision',
      () async {
        transport.responseBody = '''
{
  "release-groups": [
    {
      "id": "rg-year",
      "title": "Year Album",
      "first-release-date": "2020"
    },
    {
      "id": "rg-month",
      "title": "Month Album",
      "first-release-date": "2021-05"
    }
  ]
}
''';

        final results = await provider.search(
          const ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.album,
            albumTitle: 'Album',
          ),
        );

        expect(results, hasLength(2));
        expect(results[0].releaseDate, DateTime.utc(2020, 1, 1));
        expect(results[1].releaseDate, DateTime.utc(2021, 5, 1));
      },
    );

    test('malformed result entries are skipped safely', () async {
      transport.responseBody = '''
{
  "artists": [
    {"id": "missing-name"},
    {"name": "Missing ID"},
    {"id": "valid-id", "name": "Valid Artist"}
  ]
}
''';

      final results = await provider.search(
        const ExternalMetadataSearchQuery(
          entityKind: ExternalMetadataEntityKind.artist,
          artistName: 'Artist',
        ),
      );

      expect(results, hasLength(1));
      expect(results.single.providerEntityId, 'valid-id');
    });

    test('Lucene search phrases escape quotes and backslashes', () async {
      transport.responseBody = '{"recordings":[]}';

      await provider.search(
        const ExternalMetadataSearchQuery(
          entityKind: ExternalMetadataEntityKind.track,
          title: r'Song "Live" \ Demo',
          artistName: 'Artist',
        ),
      );

      expect(
        transport.requestedUri!.queryParameters['query'],
        r'recording:"Song \"Live\" \\ Demo" AND artist:"Artist"',
      );
    });
  });
}

class FakeMusicBrainzHttpTransport implements MusicBrainzHttpTransport {
  String responseBody = '{}';

  Uri? requestedUri;
  Map<String, String> requestHeaders = const {};
  int requestCount = 0;

  @override
  Future<MusicBrainzHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    requestCount++;
    requestedUri = uri;
    requestHeaders = Map<String, String>.from(headers);

    return MusicBrainzHttpResponse(statusCode: 200, body: responseBody);
  }
}
