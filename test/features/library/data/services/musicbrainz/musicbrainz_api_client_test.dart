import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_api_client.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_http_transport.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_rate_limiter.dart';

void main() {
  group('MusicBrainzApiClient', () {
    late FakeMusicBrainzHttpTransport transport;
    late MusicBrainzApiClient client;

    setUp(() {
      transport = FakeMusicBrainzHttpTransport();

      client = MusicBrainzApiClient(
        transport: transport,
        userAgent: 'Sonus/1.0.0 (metadata integration tests)',
        rateLimiter: MusicBrainzRateLimiter(minimumInterval: Duration.zero),
      );
    });

    test('searches recording endpoint with JSON format', () async {
      transport.response = const MusicBrainzHttpResponse(
        statusCode: 200,
        body: '{"recordings":[]}',
      );

      final result = await client.search(
        entity: MusicBrainzEntity.recording,
        query: 'recording:"Halo" AND artist:"Beyonce"',
        limit: 15,
      );

      expect(result['recordings'], isA<List<dynamic>>());

      expect(transport.requestedUri, isNotNull);
      expect(transport.requestedUri!.path, '/ws/2/recording');
      expect(
        transport.requestedUri!.queryParameters['query'],
        'recording:"Halo" AND artist:"Beyonce"',
      );
      expect(transport.requestedUri!.queryParameters['fmt'], 'json');
      expect(transport.requestedUri!.queryParameters['limit'], '15');
      expect(transport.requestedUri!.queryParameters['offset'], '0');

      expect(transport.requestHeaders['Accept'], 'application/json');
      expect(
        transport.requestHeaders['User-Agent'],
        'Sonus/1.0.0 (metadata integration tests)',
      );
    });

    test('looks up release group with requested includes', () async {
      transport.response = const MusicBrainzHttpResponse(
        statusCode: 200,
        body: '{"id":"rg-1","title":"Album"}',
      );

      final result = await client.lookup(
        entity: MusicBrainzEntity.releaseGroup,
        id: 'rg-1',
        includes: ['artist-credits', 'releases'],
      );

      expect(result['id'], 'rg-1');
      expect(transport.requestedUri!.path, '/ws/2/release-group/rg-1');
      expect(transport.requestedUri!.queryParameters['fmt'], 'json');
      expect(
        transport.requestedUri!.queryParameters['inc'],
        'artist-credits+releases',
      );
    });

    test('rejects blank search query before transport call', () async {
      expect(
        () => client.search(entity: MusicBrainzEntity.artist, query: '   '),
        throwsArgumentError,
      );

      expect(transport.requestCount, 0);
    });

    test('throws typed exception for non-success response', () async {
      transport.response = const MusicBrainzHttpResponse(
        statusCode: 503,
        body: '{"error":"temporarily unavailable"}',
      );

      expect(
        () => client.search(entity: MusicBrainzEntity.artist, query: 'Beyonce'),
        throwsA(
          isA<MusicBrainzApiException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having(
                (error) => error.responseBody,
                'responseBody',
                '{"error":"temporarily unavailable"}',
              ),
        ),
      );
    });

    test('throws typed exception for malformed JSON', () async {
      transport.response = const MusicBrainzHttpResponse(
        statusCode: 200,
        body: 'not-json',
      );

      expect(
        () => client.search(entity: MusicBrainzEntity.artist, query: 'Beyonce'),
        throwsA(isA<MusicBrainzApiException>()),
      );
    });
  });
}

class FakeMusicBrainzHttpTransport implements MusicBrainzHttpTransport {
  MusicBrainzHttpResponse response = const MusicBrainzHttpResponse(
    statusCode: 200,
    body: '{}',
  );

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

    return response;
  }
}
