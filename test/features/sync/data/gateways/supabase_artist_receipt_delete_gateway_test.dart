import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_receipt_delete_gateway.dart';

void main() {
  final deletedAt = DateTime.utc(2026, 10, 17, 12, 30);

  Object response(String outcome, int? revision) => [
    {'outcome': outcome, 'server_revision': revision},
  ];

  test('deletion sends exact RPC name and mutation payload', () async {
    String? calledName;
    Map<String, dynamic>? calledParameters;

    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting((
      name,
      parameters,
    ) async {
      calledName = name;
      calledParameters = parameters;
      return response('applied', 8);
    });

    final result = await gateway.deleteArtist(
      artistId: 'artist-1',
      expectedServerRevision: 7,
      outboxId: 'outbox-delete-1',
      mutationRevision: 4,
      deletedAt: deletedAt,
    );

    expect(calledName, SupabaseArtistReceiptDeleteGateway.deleteRpcName);

    expect(calledParameters, {
      'p_artist_id': 'artist-1',
      'p_expected_revision': 7,
      'p_outbox_id': 'outbox-delete-1',
      'p_mutation_revision': 4,
      'p_deleted_at': deletedAt.toIso8601String(),
    });

    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 8);
  });

  test('deletion timestamp is normalized to UTC', () async {
    Map<String, dynamic>? sent;

    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting((
      _,
      parameters,
    ) async {
      sent = parameters;
      return response('applied', 2);
    });

    await gateway.deleteArtist(
      artistId: 'artist-1',
      expectedServerRevision: 1,
      outboxId: 'outbox-1',
      mutationRevision: 1,
      deletedAt: DateTime.parse('2026-10-17T08:30:00-04:00'),
    );

    expect(sent?['p_deleted_at'], '2026-10-17T12:30:00.000Z');
  });

  test('exact deletion retry accepts replayed revision', () async {
    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting(
      (_, _) async => response('replayed', 8),
    );

    final result = await gateway.deleteArtist(
      artistId: 'artist-1',
      expectedServerRevision: 7,
      outboxId: 'outbox-1',
      mutationRevision: 2,
      deletedAt: deletedAt,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.replayed);
    expect(result.serverRevision, 8);
  });

  test('conflict preserves observed server revision', () async {
    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting(
      (_, _) async => response('conflict', 12),
    );

    final result = await gateway.deleteArtist(
      artistId: 'artist-1',
      expectedServerRevision: 7,
      outboxId: 'outbox-1',
      mutationRevision: 2,
      deletedAt: deletedAt,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 12);
  });

  test('missing artist remains not_found', () async {
    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting(
      (_, _) async => response('not_found', null),
    );

    final result = await gateway.deleteArtist(
      artistId: 'missing-artist',
      expectedServerRevision: 1,
      outboxId: 'outbox-1',
      mutationRevision: 1,
      deletedAt: deletedAt,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.notFound);
    expect(result.serverRevision, isNull);
  });

  test('applied response rejects incorrect next revision', () async {
    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting(
      (_, _) async => response('applied', 9),
    );

    await expectLater(
      gateway.deleteArtist(
        artistId: 'artist-1',
        expectedServerRevision: 7,
        outboxId: 'outbox-1',
        mutationRevision: 1,
        deletedAt: deletedAt,
      ),
      throwsStateError,
    );
  });

  test('replayed response rejects incorrect next revision', () async {
    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting(
      (_, _) async => response('replayed', 9),
    );

    await expectLater(
      gateway.deleteArtist(
        artistId: 'artist-1',
        expectedServerRevision: 7,
        outboxId: 'outbox-1',
        mutationRevision: 1,
        deletedAt: deletedAt,
      ),
      throwsStateError,
    );
  });

  test('invalid arguments never invoke the RPC', () async {
    var calls = 0;

    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting((_, _) async {
      calls++;
      return response('applied', 2);
    });

    Future<void> invalid({
      String artistId = 'artist-1',
      int expectedRevision = 1,
      String outboxId = 'outbox-1',
      int mutationRevision = 1,
    }) async {
      await expectLater(
        gateway.deleteArtist(
          artistId: artistId,
          expectedServerRevision: expectedRevision,
          outboxId: outboxId,
          mutationRevision: mutationRevision,
          deletedAt: deletedAt,
        ),
        throwsArgumentError,
      );
    }

    await invalid(artistId: '  ');
    await invalid(expectedRevision: 0);
    await invalid(expectedRevision: 9223372036854775807);
    await invalid(outboxId: '  ');
    await invalid(mutationRevision: 0);

    expect(calls, 0);
  });

  test('malformed RPC responses are rejected', () async {
    final malformedResponses = <Object?>[
      null,
      <Object>[],
      <Object>[1],
      <Object>[
        {'outcome': 'applied', 'server_revision': 2},
        {'outcome': 'applied', 'server_revision': 2},
      ],
    ];

    for (final malformed in malformedResponses) {
      final gateway = SupabaseArtistReceiptDeleteGateway.forTesting(
        (_, _) async => malformed,
      );

      await expectLater(
        gateway.deleteArtist(
          artistId: 'artist-1',
          expectedServerRevision: 1,
          outboxId: 'outbox-1',
          mutationRevision: 1,
          deletedAt: deletedAt,
        ),
        throwsStateError,
      );
    }
  });
}
