import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/artist_dependency_receipt_replay_gateway.dart';
import 'package:sonus_next/features/sync/data/gateways/artist_journal_replay_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/artist_dependency_journal_entry.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 12);

  ArtistDependencyJournalEntry request() {
    return ArtistDependencyJournalEntry(
      userId: 'user-1',
      artistId: 'artist-1',
      requestId: 'dependency-request-1',
      createdAt: now,
      requestJson: jsonEncode({
        'function_name': 'create_artist_with_receipt',
        'parameters': {
          'p_artist_id': 'artist-1',
          'p_outbox_id': 'dependency-request-1',
          'p_mutation_revision': 1,
          'p_name': 'Example Artist',
          'p_canonical_name': 'example artist',
          'p_header_artwork_id': null,
          'p_top_artists_artwork_id': null,
          'p_metadata_field_states': null,
          'p_created_at': now.toIso8601String(),
          'p_updated_at': now.toIso8601String(),
        },
      }),
    );
  }

  test('first submission preserves the dependency request identity', () async {
    var calls = 0;

    final gateway = ArtistDependencyReceiptReplayGateway(
      artistGateway: ArtistJournalReplayGateway(
        invokeRpc: (functionName, parameters) async {
          calls++;

          expect(functionName, 'create_artist_with_receipt');
          expect(parameters['p_artist_id'], 'artist-1');
          expect(parameters['p_outbox_id'], 'dependency-request-1');
          expect(parameters['p_mutation_revision'], 1);

          return [
            {'outcome': 'applied', 'server_revision': 1},
          ];
        },
      ),
    );

    final result = await gateway.replay(request());

    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 1);
    expect(calls, 1);
  });

  test('retry recognizes server-verified replay', () async {
    final identities = <String>[];
    var calls = 0;

    final gateway = ArtistDependencyReceiptReplayGateway(
      artistGateway: ArtistJournalReplayGateway(
        invokeRpc: (functionName, parameters) async {
          calls++;
          identities.add(parameters['p_outbox_id'] as String);

          if (calls == 1) {
            throw StateError('Response lost after server commit.');
          }

          return [
            {'outcome': 'replayed', 'server_revision': 1},
          ];
        },
      ),
    );

    final original = request();

    await expectLater(gateway.replay(original), throwsStateError);

    final result = await gateway.replay(original);

    expect(result.outcome, CloudConditionalWriteOutcome.replayed);
    expect(result.serverRevision, 1);
    expect(identities, ['dependency-request-1', 'dependency-request-1']);
  });

  test('unrelated cloud conflict remains a conflict', () async {
    final gateway = ArtistDependencyReceiptReplayGateway(
      artistGateway: ArtistJournalReplayGateway(
        invokeRpc: (functionName, parameters) async {
          return [
            {'outcome': 'conflict', 'server_revision': 4},
          ];
        },
      ),
    );

    final result = await gateway.replay(request());

    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 4);
  });

  test('invalid successful server revision is rejected', () async {
    final gateway = ArtistDependencyReceiptReplayGateway(
      artistGateway: ArtistJournalReplayGateway(
        invokeRpc: (functionName, parameters) async {
          return [
            {'outcome': 'replayed', 'server_revision': 2},
          ];
        },
      ),
    );

    await expectLater(gateway.replay(request()), throwsStateError);
  });
}
