import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_record_conditional_write_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 17, 10);

  CloudArtistRecord artist({
    String? deleted,
    List<CloudMetadataFieldState>? metadata,
  }) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: 'user-1',
      name: 'Updated Artist',
      canonicalName: 'updated artist',
      headerArtworkId: 'artwork-1',
      topArtistsArtworkId: null,
      metadataFieldStates: metadata,
      createdAt: timestamp.subtract(const Duration(days: 1)),
      updatedAt: timestamp,
      deletedAt: deleted == null ? null : timestamp,
    );
  }

  test(
    'sends full artist payload without blacklist or ownership mutation',
    () async {
      String? function;
      Map<String, dynamic>? arguments;

      final gateway = SupabaseArtistRecordConditionalWriteGateway.forTesting((
        name,
        params,
      ) async {
        function = name;
        arguments = params;
        return [
          {'outcome': 'applied', 'server_revision': 8},
        ];
      });

      final result = await gateway.updateArtist(
        artist: artist(
          metadata: [
            CloudMetadataFieldState(
              fieldName: 'name',
              authority: 'manual',
              source: 'user',
              updatedAt: timestamp,
            ),
          ],
        ),
        expectedServerRevision: 7,
      );

      expect(function, 'update_artist_record_if_revision');
      expect(arguments?['p_artist_id'], 'artist-1');
      expect(arguments?['p_expected_revision'], 7);
      expect(arguments?['p_name'], 'Updated Artist');
      expect(arguments?['p_canonical_name'], 'updated artist');
      expect(arguments?['p_header_artwork_id'], 'artwork-1');
      expect(arguments?['p_top_artists_artwork_id'], isNull);
      expect(arguments?['p_updated_at'], timestamp.toIso8601String());
      expect(arguments?.containsKey('p_is_blacklisted'), isFalse);
      expect(arguments?.containsKey('p_user_id'), isFalse);
      expect(arguments?.containsKey('p_created_at'), isFalse);
      expect(arguments?.containsKey('p_deleted_at'), isFalse);

      final metadata = arguments?['p_metadata_field_states'] as List;
      expect(metadata, hasLength(1));
      expect((metadata.single as Map)['field_name'], 'name');
      expect((metadata.single as Map)['authority'], 'manual');

      expect(result.outcome, CloudConditionalWriteOutcome.applied);
      expect(result.serverRevision, 8);
    },
  );

  test('conflict returns actual server revision', () async {
    final gateway = SupabaseArtistRecordConditionalWriteGateway.forTesting(
      (name, params) async => [
        {'outcome': 'conflict', 'server_revision': 12},
      ],
    );

    final result = await gateway.updateArtist(
      artist: artist(),
      expectedServerRevision: 7,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 12);
  });

  test('not found has no revision', () async {
    final gateway = SupabaseArtistRecordConditionalWriteGateway.forTesting(
      (name, params) async => [
        {'outcome': 'not_found', 'server_revision': null},
      ],
    );

    final result = await gateway.updateArtist(
      artist: artist(),
      expectedServerRevision: 7,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.notFound);
    expect(result.serverRevision, isNull);
  });

  test('rejects malformed responses and incorrect applied revisions', () async {
    for (final response in <Object?>[
      null,
      [],
      {'outcome': 'applied', 'server_revision': 8},
      [
        {'outcome': 'applied', 'server_revision': 8},
        {'outcome': 'applied', 'server_revision': 8},
      ],
      [
        {'outcome': 'applied', 'server_revision': 7},
      ],
      [
        {'outcome': 'applied', 'server_revision': 9},
      ],
      [
        {'outcome': 'conflict', 'server_revision': 0},
      ],
      [
        {'outcome': 'unknown', 'server_revision': 8},
      ],
    ]) {
      final gateway = SupabaseArtistRecordConditionalWriteGateway.forTesting(
        (name, params) async => response,
      );

      await expectLater(
        gateway.updateArtist(artist: artist(), expectedServerRevision: 7),
        throwsStateError,
      );
    }
  });

  test('rejects deleted artist and invalid revision before RPC', () async {
    var calls = 0;

    final gateway = SupabaseArtistRecordConditionalWriteGateway.forTesting((
      name,
      params,
    ) async {
      calls++;
      return [
        {'outcome': 'applied', 'server_revision': 8},
      ];
    });

    await expectLater(
      gateway.updateArtist(
        artist: artist(deleted: 'yes'),
        expectedServerRevision: 7,
      ),
      throwsArgumentError,
    );

    await expectLater(
      gateway.updateArtist(artist: artist(), expectedServerRevision: 0),
      throwsArgumentError,
    );

    expect(calls, 0);
  });

  test('propagates transport errors', () async {
    final gateway = SupabaseArtistRecordConditionalWriteGateway.forTesting(
      (name, params) async => throw StateError('Network unavailable'),
    );

    await expectLater(
      gateway.updateArtist(artist: artist(), expectedServerRevision: 7),
      throwsA(isA<StateError>()),
    );
  });
}
