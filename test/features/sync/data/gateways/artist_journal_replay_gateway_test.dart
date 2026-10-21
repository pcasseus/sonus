import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/artist_receipt_request_codec.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/artist_journal_replay_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/artist_write_journal_entry.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 12);

  CloudArtistRecord artist() => CloudArtistRecord(
    id: 'artist_1',
    userId: 'user_1',
    name: 'Original Artist',
    canonicalName: 'original artist',
    createdAt: now.subtract(const Duration(days: 4)),
    updatedAt: now,
  );

  test('creation snapshot preserves exact RPC contract', () {
    final entry = ArtistReceiptRequestCodec.forUpsert(
      artist: artist(),
      outboxId: 'outbox_1',
      mutationRevision: 3,
      expectedServerRevision: null,
      preparedAt: now,
    );

    final request = ArtistReceiptRequestCodec.decode(entry);

    expect(request.functionName, ArtistReceiptRequestCodec.createFunction);
    expect(request.parameters['p_artist_id'], 'artist_1');
    expect(request.parameters['p_mutation_revision'], 3);
    expect(request.parameters['p_name'], 'Original Artist');
    expect(request.parameters.containsKey('p_created_at'), isTrue);
    expect(request.parameters.containsKey('p_expected_revision'), isFalse);
    expect(request.parameters['p_metadata_field_states'], isNull);
  });

  test('update snapshot retains original expected revision', () {
    final entry = ArtistReceiptRequestCodec.forUpsert(
      artist: artist(),
      outboxId: 'outbox_1',
      mutationRevision: 4,
      expectedServerRevision: 7,
      preparedAt: now,
    );

    final request = ArtistReceiptRequestCodec.decode(entry);

    expect(request.functionName, ArtistReceiptRequestCodec.updateFunction);
    expect(request.parameters['p_expected_revision'], 7);
    expect(request.parameters['p_mutation_revision'], 4);
    expect(request.parameters.containsKey('p_created_at'), isFalse);
  });

  test('deletion snapshot keeps original deletion timestamp', () {
    final deletedAt = now.subtract(const Duration(hours: 2));

    final entry = ArtistReceiptRequestCodec.forDelete(
      userId: 'user_1',
      artistId: 'artist_1',
      outboxId: 'outbox_1',
      mutationRevision: 5,
      expectedServerRevision: 9,
      deletedAt: deletedAt,
      preparedAt: now,
    );

    final request = ArtistReceiptRequestCodec.decode(entry);

    expect(request.functionName, ArtistReceiptRequestCodec.deleteFunction);
    expect(request.parameters['p_expected_revision'], 9);
    expect(request.parameters['p_deleted_at'], deletedAt.toIso8601String());
  });

  test('replay submits stored snapshot and accepts replay receipt', () async {
    final entry = ArtistReceiptRequestCodec.forUpsert(
      artist: artist(),
      outboxId: 'outbox_1',
      mutationRevision: 2,
      expectedServerRevision: 7,
      preparedAt: now,
    );

    String? invokedFunction;
    Map<String, dynamic>? invokedParameters;

    final gateway = ArtistJournalReplayGateway(
      invokeRpc: (name, parameters) async {
        invokedFunction = name;
        invokedParameters = Map<String, dynamic>.from(parameters);
        return [
          {'outcome': 'replayed', 'server_revision': 8},
        ];
      },
    );

    final result = await gateway.replay(entry);
    final stored = ArtistReceiptRequestCodec.decode(entry);

    expect(result.outcome, CloudConditionalWriteOutcome.replayed);
    expect(result.serverRevision, 8);
    expect(invokedFunction, stored.functionName);
    expect(invokedParameters, stored.parameters);
  });

  test('invalid stored operation cannot invoke cloud RPC', () async {
    final original = ArtistReceiptRequestCodec.forUpsert(
      artist: artist(),
      outboxId: 'outbox_1',
      mutationRevision: 1,
      expectedServerRevision: null,
      preparedAt: now,
    );

    final tampered = original.toRow();
    final request = jsonDecode(original.requestJson) as Map<String, dynamic>;

    request['function_name'] = ArtistReceiptRequestCodec.deleteFunction;
    tampered['request_json'] = jsonEncode(request);

    final invalid = (await () async {
      return original;
    }());

    // The entry stays otherwise identical; only its payload is altered.
    final malformed = invalid.toRow()
      ..['request_json'] = tampered['request_json'];

    var calls = 0;
    final gateway = ArtistJournalReplayGateway(
      invokeRpc: (_, _) async {
        calls++;
        return [
          {'outcome': 'applied', 'server_revision': 1},
        ];
      },
    );

    await expectLater(
      gateway.replay(
        // Reconstruct through the actual persisted-row parser.
        // Invalid RPC semantics must be detected before dispatch.
        _restored(malformed),
      ),
      throwsStateError,
    );

    expect(calls, 0);
  });

  test('unexpected receipt revision is rejected', () async {
    final entry = ArtistReceiptRequestCodec.forUpsert(
      artist: artist(),
      outboxId: 'outbox_1',
      mutationRevision: 2,
      expectedServerRevision: 7,
      preparedAt: now,
    );

    final gateway = ArtistJournalReplayGateway(
      invokeRpc: (_, _) async => [
        {'outcome': 'replayed', 'server_revision': 99},
      ],
    );

    await expectLater(gateway.replay(entry), throwsStateError);
  });
}

ArtistWriteJournalEntry _restored(Map<String, Object?> row) {
  return ArtistWriteJournalEntry.fromRow(row);
}
