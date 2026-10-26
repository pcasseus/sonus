import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sonus_next/features/sync/application/services/cloud_archive_gateway.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_archive_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';

class _Request {
  _Request(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final String body;

  String? query(String name) => uri.queryParameters[name];
}

Map<String, Object?> _row(String key, {int revision = 1}) => {
  'user_id': 'user-1',
  'library_id': 'main',
  'kind': 'lyrics',
  'record_key': key,
  'record_id': 'lyrics:$key',
  'payload': {'song_id': key, 'plain_text': 'Words', 'position': 1.5},
  'is_deleted': false,
  'client_updated_at': '2026-10-24T00:00:00.000Z',
  'server_updated_at': '2026-10-25T12:00:00.123456Z',
  'server_revision': revision,
};

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseCloudArchiveGateway gateway;
  final requests = <_Request>[];
  late Object? Function(_Request request) respond;
  int status = 200;

  setUp(() async {
    requests.clear();
    status = 200;
    respond = (_) => [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final recorded = _Request(
        request.method,
        request.uri,
        request.headers,
        await utf8.decodeStream(request),
      );
      requests.add(recorded);
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(respond(recorded)));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    gateway = SupabaseCloudArchiveGateway(client: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  final record = CloudArchiveRecord(
    kind: CloudArchiveKind.lyrics,
    key: 'song-1',
    payload: const {'song_id': 'song-1', 'plain_text': 'Words'},
    clientUpdatedAt: DateTime.utc(2026, 10, 24),
  );

  group('availability', () {
    test('a server without the table has no archive', () async {
      status = 404;
      respond = (_) => {
        'code': 'PGRST205',
        'message': 'Could not find the table',
      };

      expect(await gateway.isAvailable(), isFalse);
      expect(await gateway.isAvailable(), isFalse);
      expect(requests, hasLength(1), reason: 'remembered');
    });

    test('a server with the table has one', () async {
      expect(await gateway.isAvailable(), isTrue);
      expect(requests.single.uri.path, '/rest/v1/sonus_archive_records');
    });

    test('any other failure is not mistaken for a missing archive', () async {
      status = 401;
      respond = (_) => {'code': 'PGRST301', 'message': 'JWT expired'};

      await expectLater(
        gateway.isAvailable(),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('writes', () {
    test('insert-if-absent never overwrites an existing record', () async {
      respond = (_) => [
        {'server_revision': 1},
      ];

      final result = await gateway.insertIfAbsent(
        userId: 'user-1',
        record: record,
      );

      expect(result.outcome, CloudArchiveWriteOutcome.applied);
      expect(result.serverRevision, 1);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.query('on_conflict'),
        'user_id,library_id,kind,record_key',
      );
      expect(
        request.headers.value('prefer'),
        contains('resolution=ignore-duplicates'),
      );
      final body = jsonDecode(request.body);
      final row = Map<String, dynamic>.from(body is List ? body.first : body);
      expect(row, {
        'user_id': 'user-1',
        'library_id': 'main',
        'kind': 'lyrics',
        'record_key': 'song-1',
        'payload': {'song_id': 'song-1', 'plain_text': 'Words'},
        'is_deleted': false,
        'client_updated_at': '2026-10-24T00:00:00.000Z',
      });
      expect(row, isNot(contains('server_revision')));
    });

    test('an existing record is reported as a conflict', () async {
      final result = await gateway.insertIfAbsent(
        userId: 'user-1',
        record: record,
      );

      expect(result.outcome, CloudArchiveWriteOutcome.conflict);
    });

    test('an update applies only at the expected revision', () async {
      respond = (_) => [
        {'server_revision': 4},
      ];

      final result = await gateway.updateIfRevision(
        userId: 'user-1',
        record: record,
        expectedServerRevision: 3,
      );

      expect(result.serverRevision, 4);
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.query('server_revision'), 'eq.3');
      expect(request.query('user_id'), 'eq.user-1');
      expect(request.query('library_id'), 'eq.main');
      expect(request.query('kind'), 'eq.lyrics');
      expect(request.query('record_key'), 'eq.song-1');
      expect(
        jsonDecode(request.body),
        isNot(contains('user_id')),
        reason: 'identity is never rewritten',
      );
    });
  });

  group('reads', () {
    test('a page continues exactly after the cursor', () async {
      respond = (request) =>
          request.query('server_updated_at') == 'eq.2026-10-25T12:00:00.123456Z'
          ? [_row('b')]
          : [_row('c', revision: 2)];

      final page = await gateway.readPage(
        userId: 'user-1',
        after: CloudArchiveCursor(
          serverUpdatedAt: DateTime.parse('2026-10-25T12:00:00.123456Z'),
          recordId: 'lyrics:a',
        ),
        limit: 5,
      );

      expect([for (final r in page) r.key], ['b', 'c']);
      expect(requests, hasLength(2));
      expect(requests[0].query('record_id'), 'gt.lyrics:a');
      expect(requests[0].query('limit'), '5');
      expect(
        requests[1].query('server_updated_at'),
        'gt.2026-10-25T12:00:00.123456Z',
      );
      expect(requests[1].query('limit'), '4');
      for (final request in requests) {
        expect(request.query('user_id'), 'eq.user-1');
        expect(request.query('kind'), startsWith('in.('));
        expect(request.query('kind'), contains('listening_session'));
      }
    });

    test('rows read back exactly, to the microsecond', () async {
      respond = (_) => [_row('song-1', revision: 7)];

      final read = (await gateway.fetch(
        userId: 'user-1',
        kind: CloudArchiveKind.lyrics,
        keys: ['song-1'],
      )).single;

      expect(read.recordId, 'lyrics:song-1');
      expect(read.serverRevision, 7);
      expect(
        read.serverUpdatedAt,
        DateTime.parse('2026-10-25T12:00:00.123456Z'),
      );
      expect(read.payload['position'], 1.5);
      expect(requests.single.query('record_key'), 'in.("song-1")');
    });

    test('no request is made for no keys', () async {
      expect(
        await gateway.fetch(
          userId: 'user-1',
          kind: CloudArchiveKind.lyrics,
          keys: const [],
        ),
        isEmpty,
      );
      expect(requests, isEmpty);
    });
  });
}
