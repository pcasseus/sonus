import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_receipt_write_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 17, 10);
  final updatedAt = DateTime.utc(2026, 10, 17, 11);

  CloudArtistRecord artist() => CloudArtistRecord(
    id: 'artist-1',
    userId: 'user-1',
    name: 'Test Artist',
    canonicalName: 'test artist',
    createdAt: createdAt,
    updatedAt: updatedAt,
    metadataFieldStates: const [],
  );

  Object response(String outcome, int? revision) => [
    {'outcome': outcome, 'server_revision': revision},
  ];

  test('creation sends exact mutation identity and artist data', () async {
    String? calledName;
    Map<String, dynamic>? calledParameters;

    final gateway = SupabaseArtistReceiptWriteGateway.forTesting((
      name,
      parameters,
    ) async {
      calledName = name;
      calledParameters = parameters;
      return response('applied', 1);
    });

    final result = await gateway.createArtist(
      artist: artist(),
      outboxId: 'outbox-123',
      mutationRevision: 4,
    );

    expect(calledName, SupabaseArtistReceiptWriteGateway.createRpcName);
    expect(calledParameters?['p_artist_id'], 'artist-1');
    expect(calledParameters?['p_outbox_id'], 'outbox-123');
    expect(calledParameters?['p_mutation_revision'], 4);
    expect(calledParameters?['p_name'], 'Test Artist');
    expect(calledParameters?['p_canonical_name'], 'test artist');
    expect(calledParameters?['p_header_artwork_id'], isNull);
    expect(calledParameters?['p_top_artists_artwork_id'], isNull);
    expect(calledParameters?['p_metadata_field_states'], isA<List>());
    expect(calledParameters?['p_created_at'], createdAt.toIso8601String());
    expect(calledParameters?['p_updated_at'], updatedAt.toIso8601String());
    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 1);
  });

  test('creation recognizes a verified replay', () async {
    final gateway = SupabaseArtistReceiptWriteGateway.forTesting(
      (_, _) async => response('replayed', 1),
    );

    final result = await gateway.createArtist(
      artist: artist(),
      outboxId: 'outbox-123',
      mutationRevision: 4,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.replayed);
    expect(result.serverRevision, 1);
  });

  test('update sends baseline and mutation identity', () async {
    String? calledName;
    Map<String, dynamic>? calledParameters;

    final gateway = SupabaseArtistReceiptWriteGateway.forTesting((
      name,
      parameters,
    ) async {
      calledName = name;
      calledParameters = parameters;
      return response('applied', 8);
    });

    final result = await gateway.updateArtist(
      artist: artist(),
      expectedServerRevision: 7,
      outboxId: 'outbox-456',
      mutationRevision: 9,
    );

    expect(calledName, SupabaseArtistReceiptWriteGateway.updateRpcName);
    expect(calledParameters?['p_expected_revision'], 7);
    expect(calledParameters?['p_outbox_id'], 'outbox-456');
    expect(calledParameters?['p_mutation_revision'], 9);
    expect(calledParameters?['p_artist_id'], 'artist-1');
    expect(calledParameters?['p_name'], 'Test Artist');
    expect(calledParameters?['p_metadata_field_states'], isA<List>());
    expect(calledParameters?['p_updated_at'], updatedAt.toIso8601String());
    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 8);
  });

  test('update recognizes a verified replay', () async {
    final gateway = SupabaseArtistReceiptWriteGateway.forTesting(
      (_, _) async => response('replayed', 8),
    );

    final result = await gateway.updateArtist(
      artist: artist(),
      expectedServerRevision: 7,
      outboxId: 'outbox-456',
      mutationRevision: 9,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.replayed);
    expect(result.serverRevision, 8);
  });

  test('creation rejects incorrect successful revision', () async {
    final gateway = SupabaseArtistReceiptWriteGateway.forTesting(
      (_, _) async => response('replayed', 2),
    );

    await expectLater(
      gateway.createArtist(
        artist: artist(),
        outboxId: 'outbox-123',
        mutationRevision: 1,
      ),
      throwsStateError,
    );
  });

  test('update rejects incorrect successful revision', () async {
    final gateway = SupabaseArtistReceiptWriteGateway.forTesting(
      (_, _) async => response('applied', 12),
    );

    await expectLater(
      gateway.updateArtist(
        artist: artist(),
        expectedServerRevision: 7,
        outboxId: 'outbox-123',
        mutationRevision: 1,
      ),
      throwsStateError,
    );
  });

  test('invalid mutation identity never calls RPC', () async {
    var calls = 0;

    final gateway = SupabaseArtistReceiptWriteGateway.forTesting((_, _) async {
      calls++;
      return response('applied', 1);
    });

    await expectLater(
      gateway.createArtist(
        artist: artist(),
        outboxId: '   ',
        mutationRevision: 1,
      ),
      throwsArgumentError,
    );

    await expectLater(
      gateway.createArtist(
        artist: artist(),
        outboxId: 'outbox-123',
        mutationRevision: 0,
      ),
      throwsArgumentError,
    );

    await expectLater(
      gateway.updateArtist(
        artist: artist(),
        expectedServerRevision: 0,
        outboxId: 'outbox-123',
        mutationRevision: 1,
      ),
      throwsArgumentError,
    );

    expect(calls, 0);
  });

  test('malformed RPC response is rejected', () async {
    final gateway = SupabaseArtistReceiptWriteGateway.forTesting(
      (_, _) async => <Object>[],
    );

    await expectLater(
      gateway.createArtist(
        artist: artist(),
        outboxId: 'outbox-123',
        mutationRevision: 1,
      ),
      throwsStateError,
    );
  });

  test('conflict preserves its observed revision', () async {
    final gateway = SupabaseArtistReceiptWriteGateway.forTesting(
      (_, _) async => response('conflict', 15),
    );

    final result = await gateway.updateArtist(
      artist: artist(),
      expectedServerRevision: 7,
      outboxId: 'outbox-123',
      mutationRevision: 1,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 15);
  });
}
