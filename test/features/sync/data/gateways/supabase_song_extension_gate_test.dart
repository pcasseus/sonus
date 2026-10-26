import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sonus_next/features/sync/application/services/cloud_record_equivalence.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

final _t = DateTime.utc(2026, 10, 25, 12);

CloudSongRecord _song({bool extensions = true}) => CloudSongRecord(
  id: 'song_1',
  userId: 'user_1',
  artistId: 'artist_1',
  albumId: 'album_1',
  albumEditionId: 'edition_standard',
  title: 'Song',
  canonicalTitle: 'song',
  trackNumber: 3,
  durationSeconds: 200,
  isSingle: false,
  featuredArtists: const ['Guest'],
  createdAt: _t,
  updatedAt: _t,
  editionMemberships: extensions
      ? const [
          CloudEditionMembership(
            albumEditionId: 'edition_deluxe',
            discNumber: 1,
            trackNumber: 3,
            sortPosition: 2,
            numberingAuthority: 'inferred',
            orderingAuthority: 'manual',
          ),
        ]
      : null,
  artistCredits: extensions
      ? const [
          CloudSongCredit(
            id: 'credit_1',
            artistId: 'artist_2',
            creditedName: 'Guest',
            canonicalCreditedName: 'guest',
            role: 'featured',
            position: 1,
          ),
        ]
      : null,
);

void main() {
  group('row mapping', () {
    test('memberships and credits round-trip through JSON', () {
      final row =
          jsonDecode(
                jsonEncode({
                  ...SupabaseCloudRecordMapper.toRow(_song()),
                  'server_updated_at': _t.toIso8601String(),
                  'server_revision': 1,
                }),
              )
              as Map<String, dynamic>;

      final back =
          SupabaseCloudRecordMapper.fromRow(
                entityType: CloudDataEntity.song,
                row: row,
              ).record
              as CloudSongRecord;

      expect(back.editionMemberships!.single.albumEditionId, 'edition_deluxe');
      expect(back.editionMemberships!.single.orderingAuthority, 'manual');
      expect(back.artistCredits!.single.role, 'featured');
      expect(CloudRecordEquivalence.isEquivalent(back, _song()), isTrue);
    });

    test('a row from before the columns existed means "not provided"', () {
      final row = SupabaseCloudRecordMapper.toRow(_song(extensions: false))
        ..['server_updated_at'] = _t.toIso8601String()
        ..['server_revision'] = 1;

      final back =
          SupabaseCloudRecordMapper.fromRow(
                entityType: CloudDataEntity.song,
                row: row,
              ).record
              as CloudSongRecord;

      expect(row.containsKey('edition_memberships'), isFalse);
      expect(back.editionMemberships, isNull);
      expect(back.artistCredits, isNull);
    });

    test('equivalence compares the lists only when both sides carry them', () {
      expect(
        CloudRecordEquivalence.isEquivalent(_song(), _song(extensions: false)),
        isTrue,
        reason: 'an older server cannot store them, so they cannot differ',
      );

      final changed = CloudSongRecord(
        id: 'song_1',
        userId: 'user_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_standard',
        title: 'Song',
        canonicalTitle: 'song',
        trackNumber: 3,
        durationSeconds: 200,
        isSingle: false,
        featuredArtists: const ['Guest'],
        createdAt: _t,
        updatedAt: _t,
        editionMemberships: const [],
        artistCredits: _song().artistCredits,
      );
      expect(CloudRecordEquivalence.isEquivalent(_song(), changed), isFalse);
    });
  });

  group('the server capability gate', () {
    late HttpServer server;
    late SupabaseClient client;
    late bool serverHasColumns;
    final writes = <Map<String, dynamic>>[];
    var probes = 0;

    setUp(() async {
      writes.clear();
      probes = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decodeStream(request);
        final response = request.response
          ..headers.contentType = ContentType.json;

        if (request.method == 'GET' &&
            (request.uri.queryParameters['select'] ?? '').contains(
              'edition_memberships',
            )) {
          probes++;
          if (serverHasColumns) {
            response.write('[]');
          } else {
            response
              ..statusCode = 400
              ..write(
                jsonEncode({
                  'code': '42703',
                  'message': 'column songs.edition_memberships does not exist',
                }),
              );
          }
        } else {
          if (body.isNotEmpty) {
            final decoded = jsonDecode(body);
            writes.add(
              Map<String, dynamic>.from(
                decoded is List ? decoded.first : decoded,
              ),
            );
          }
          response.write(
            jsonEncode([
              {'server_revision': 1},
            ]),
          );
        }
        await response.close();
      });
      client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    });

    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });

    test('an older server gets song writes without the new columns', () async {
      serverHasColumns = false;
      final gateway = SupabaseCloudSyncGateway(client: client);

      await gateway.insertIfAbsent(_song());
      await gateway.insertIfAbsent(_song());

      expect(writes, hasLength(2));
      for (final row in writes) {
        expect(row.containsKey('edition_memberships'), isFalse);
        expect(row.containsKey('artist_credits'), isFalse);
        expect(row['title'], 'Song');
      }
      expect(probes, 1, reason: 'asked once per session');
    });

    test('a migrated server gets memberships and credits', () async {
      serverHasColumns = true;
      final gateway = SupabaseCloudSyncGateway(client: client);

      await gateway.updateIfRevision(_song(), expectedServerRevision: 1);

      expect(writes.single['edition_memberships'], hasLength(1));
      expect(writes.single['artist_credits'], hasLength(1));
    });

    test('non-song records never trigger the probe', () async {
      serverHasColumns = false;
      final gateway = SupabaseCloudSyncGateway(client: client);

      await gateway.insertIfAbsent(
        CloudAlbumRecord(
          id: 'album_1',
          userId: 'user_1',
          artistId: 'artist_1',
          title: 'Album',
          canonicalTitle: 'album',
          createdAt: _t,
          updatedAt: _t,
        ),
      );

      expect(probes, 0);
    });
  });
}
