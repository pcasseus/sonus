import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_create_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 14);

  CloudArtistRecord artist({bool deleted = false}) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: 'account-1',
      name: 'New Artist',
      canonicalName: 'new artist',
      headerArtworkId: 'artwork-1',
      metadataFieldStates: [
        CloudMetadataFieldState(
          fieldName: 'name',
          authority: 'manual',
          source: 'user',
          updatedAt: now,
        ),
      ],
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now,
      deletedAt: deleted ? now : null,
    );
  }

  test('sends complete insert-only artist payload', () async {
    String? calledFunction;
    Map<String, dynamic>? parameters;

    final gateway = SupabaseArtistCreateGateway.forTesting((name, args) async {
      calledFunction = name;
      parameters = args;
      return [
        {'outcome': 'applied', 'server_revision': 1},
      ];
    });

    final record = artist();
    final result = await gateway.createArtist(artist: record);

    expect(calledFunction, 'create_artist_if_absent');
    expect(parameters?['p_artist_id'], record.id);
    expect(parameters?['p_name'], record.name);
    expect(parameters?['p_canonical_name'], record.canonicalName);
    expect(parameters?['p_header_artwork_id'], 'artwork-1');
    expect(parameters?['p_top_artists_artwork_id'], isNull);
    expect(
      parameters?['p_created_at'],
      record.createdAt.toUtc().toIso8601String(),
    );
    expect(
      parameters?['p_updated_at'],
      record.updatedAt.toUtc().toIso8601String(),
    );

    final metadata = parameters?['p_metadata_field_states'] as List;
    expect(metadata, hasLength(1));
    expect((metadata.single as Map)['field_name'], 'name');

    expect(parameters?.containsKey('p_user_id'), isFalse);
    expect(parameters?.containsKey('p_is_blacklisted'), isFalse);
    expect(parameters?.containsKey('p_deleted_at'), isFalse);

    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 1);
  });

  test('existing artist returns conflict without claiming success', () async {
    final gateway = SupabaseArtistCreateGateway.forTesting(
      (name, args) async => [
        {'outcome': 'conflict', 'server_revision': 7},
      ],
    );

    final result = await gateway.createArtist(artist: artist());

    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 7);
  });

  test('cross-account collision returns not found', () async {
    final gateway = SupabaseArtistCreateGateway.forTesting(
      (name, args) async => [
        {'outcome': 'not_found', 'server_revision': null},
      ],
    );

    final result = await gateway.createArtist(artist: artist());

    expect(result.outcome, CloudConditionalWriteOutcome.notFound);
    expect(result.serverRevision, isNull);
  });

  test('rejects malformed and unexpected responses', () async {
    for (final response in <Object?>[
      null,
      [],
      {'outcome': 'applied', 'server_revision': 1},
      [
        {'outcome': 'applied', 'server_revision': 1},
        {'outcome': 'applied', 'server_revision': 1},
      ],
      [
        {'outcome': 'applied', 'server_revision': 2},
      ],
      [
        {'outcome': 'applied', 'server_revision': null},
      ],
      [
        {'outcome': 'conflict', 'server_revision': 0},
      ],
      [
        {'outcome': 'unknown', 'server_revision': 1},
      ],
    ]) {
      final gateway = SupabaseArtistCreateGateway.forTesting(
        (name, args) async => response,
      );

      await expectLater(
        gateway.createArtist(artist: artist()),
        throwsStateError,
      );
    }
  });

  test('rejects deleted artist without calling server', () async {
    var calls = 0;

    final gateway = SupabaseArtistCreateGateway.forTesting((name, args) async {
      calls++;
      return [
        {'outcome': 'applied', 'server_revision': 1},
      ];
    });

    await expectLater(
      gateway.createArtist(artist: artist(deleted: true)),
      throwsArgumentError,
    );

    expect(calls, 0);
  });

  test('propagates server and transport failures', () async {
    final gateway = SupabaseArtistCreateGateway.forTesting(
      (name, args) async => throw StateError('Connection failed'),
    );

    await expectLater(gateway.createArtist(artist: artist()), throwsStateError);
  });
}
