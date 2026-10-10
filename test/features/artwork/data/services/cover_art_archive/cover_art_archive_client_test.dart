import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/application/models/cover_art_archive_image.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_client.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_http_transport.dart';

const mbid = '12345678-1234-1234-1234-123456789abc';

void main() {
  late FakeArchiveTransport transport;
  late CoverArtArchiveClient client;

  setUp(() {
    transport = FakeArchiveTransport();
    client = CoverArtArchiveClient(
      transport: transport,
      userAgent: 'Sonus/1.0 (test)',
    );
  });

  test('reads front/back artwork from release group', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 200,
      body: '''
{
  "images": [
    {
      "id": 42,
      "image": "https://coverartarchive.org/image/front.jpg",
      "front": true,
      "back": false,
      "approved": true,
      "types": ["Front"],
      "thumbnails": {
        "250": "https://coverartarchive.org/image/front-250.jpg"
      }
    },
    {
      "id": 43,
      "image": "https://coverartarchive.org/image/back.jpg",
      "front": false,
      "back": true,
      "types": ["Back"]
    }
  ]
}
''',
    );

    final images = await client.lookup(
      entity: CoverArtArchiveEntity.releaseGroup,
      id: mbid,
    );

    expect(images, hasLength(2));
    expect(images.first.front, isTrue);
    expect(images.first.back, isFalse);
    expect(images.first.approved, isTrue);
    expect(images.first.imageId, '42');
    expect(images.first.types, ['Front']);
    expect(
      images.first.thumbnailUrl,
      'https://coverartarchive.org/image/front-250.jpg',
    );
    expect(images.last.back, isTrue);
    expect(images.first.sourceReference, 'coverartarchive:release-group:$mbid');
    expect(transport.requestedUri!.path, '/release-group/$mbid');
    expect(transport.requestHeaders['Accept'], 'application/json');
    expect(transport.requestHeaders['User-Agent'], 'Sonus/1.0 (test)');
  });

  test('supports release-specific lookup', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 200,
      body: '{"images":[]}',
    );

    final images = await client.lookup(
      entity: CoverArtArchiveEntity.release,
      id: mbid,
    );

    expect(images, isEmpty);
    expect(transport.requestedUri!.path, '/release/$mbid');
  });

  test('404 means no available artwork', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 404,
      body: 'Not Found',
    );

    expect(
      await client.lookup(entity: CoverArtArchiveEntity.release, id: mbid),
      isEmpty,
    );
  });

  test('other HTTP errors remain failures', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 503,
      body: 'Unavailable',
    );

    await expectLater(
      client.lookup(entity: CoverArtArchiveEntity.release, id: mbid),
      throwsA(
        isA<CoverArtArchiveException>().having(
          (e) => e.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });

  test('invalid UUID never reaches network', () async {
    await expectLater(
      client.lookup(entity: CoverArtArchiveEntity.release, id: '../invalid'),
      throwsArgumentError,
    );
    expect(transport.requestCount, 0);
  });

  test('invalid JSON remains a failure', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 200,
      body: '{"other":[]}',
    );

    await expectLater(
      client.lookup(entity: CoverArtArchiveEntity.releaseGroup, id: mbid),
      throwsA(isA<CoverArtArchiveException>()),
    );
  });

  test('rejects blank User-Agent without network access', () async {
    final invalidClient = CoverArtArchiveClient(
      transport: transport,
      userAgent: '   ',
    );

    await expectLater(
      invalidClient.lookup(entity: CoverArtArchiveEntity.release, id: mbid),
      throwsStateError,
    );

    expect(transport.requestCount, 0);
  });

  test('normalizes mixed-case MusicBrainz identifiers', () async {
    await client.lookup(
      entity: CoverArtArchiveEntity.release,
      id: '  ${mbid.toUpperCase()}  ',
    );

    expect(transport.requestedUri!.path, '/release/$mbid');
  });

  test('ignores invalid thumbnails but keeps valid artwork', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 200,
      body: '''
{
  "images": [
    {
      "image": "https://coverartarchive.org/image/valid.jpg",
      "front": true,
      "thumbnails": {
        "250": "https://evil.example/untrusted.jpg",
        "small": "not-a-url"
      }
    }
  ]
}
''',
    );

    final images = await client.lookup(
      entity: CoverArtArchiveEntity.release,
      id: mbid,
    );

    expect(images, hasLength(1));
    expect(images.single.front, isTrue);
    expect(images.single.thumbnailUrl, isNull);
  });
  test('invalid or insecure image URLs are discarded', () async {
    transport.response = const MusicBrainzHttpResponse(
      statusCode: 200,
      body: '''
{"images":[
  {"image":"http://example.com/unsafe.jpg","front":true},
  {"image":"not-a-url"},
  {"image":"https://coverartarchive.org/valid.jpg","front":true}
]}
''',
    );

    final images = await client.lookup(
      entity: CoverArtArchiveEntity.release,
      id: mbid,
    );

    expect(images, hasLength(1));
    expect(images.single.front, isTrue);
  });
}

class FakeArchiveTransport implements MusicBrainzHttpTransport {
  MusicBrainzHttpResponse response = const MusicBrainzHttpResponse(
    statusCode: 200,
    body: '{"images":[]}',
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
