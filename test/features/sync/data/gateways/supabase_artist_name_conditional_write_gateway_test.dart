import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_name_conditional_write_gateway.dart';

void main() {
  final updatedAt = DateTime.utc(2026, 10, 17, 8, 30);

  Future<CloudConditionalWriteResult> invokeWith(
    Object? response, {
    int expectedRevision = 7,
  }) {
    final gateway = SupabaseArtistNameConditionalWriteGateway.forTesting(
      (functionName, parameters) async => response,
    );
    return gateway.updateArtistName(
      artistId: 'artist-1',
      expectedServerRevision: expectedRevision,
      name: 'Renamed Artist',
      canonicalName: 'renamed artist',
      updatedAt: updatedAt,
    );
  }

  test('sends exact function, revision, values, and UTC timestamp', () async {
    String? invoked;
    Map<String, dynamic>? parameters;
    final gateway = SupabaseArtistNameConditionalWriteGateway.forTesting((
      name,
      args,
    ) async {
      invoked = name;
      parameters = args;
      return [
        <String, dynamic>{'outcome': 'applied', 'server_revision': 8},
      ];
    });

    final result = await gateway.updateArtistName(
      artistId: 'artist-1',
      expectedServerRevision: 7,
      name: 'Renamed Artist',
      canonicalName: 'renamed artist',
      updatedAt: updatedAt.toLocal(),
    );

    expect(invoked, 'update_artist_name_if_revision');
    expect(parameters, {
      'p_artist_id': 'artist-1',
      'p_expected_revision': 7,
      'p_name': 'Renamed Artist',
      'p_canonical_name': 'renamed artist',
      'p_updated_at': updatedAt.toIso8601String(),
    });
    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 8);
  });

  test('conflict preserves the observed server revision', () async {
    final result = await invokeWith([
      {'outcome': 'conflict', 'server_revision': 11},
    ]);
    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 11);
  });

  test('not found has no revision', () async {
    final result = await invokeWith([
      {'outcome': 'not_found', 'server_revision': null},
    ]);
    expect(result.outcome, CloudConditionalWriteOutcome.notFound);
    expect(result.serverRevision, isNull);
  });

  test('rejects unexpected applied revision', () async {
    await expectLater(
      invokeWith([
        {'outcome': 'applied', 'server_revision': 7},
      ]),
      throwsStateError,
    );
    await expectLater(
      invokeWith([
        {'outcome': 'applied', 'server_revision': 9},
      ]),
      throwsStateError,
    );
  });

  test('rejects zero, missing, and multiple response rows', () async {
    for (final response in <Object?>[
      null,
      <Object?>[],
      [
        <String, dynamic>{'outcome': 'applied', 'server_revision': 8},
        <String, dynamic>{'outcome': 'applied', 'server_revision': 8},
      ],
      {'outcome': 'applied', 'server_revision': 8},
      ['unexpected'],
    ]) {
      await expectLater(invokeWith(response), throwsStateError);
    }
  });

  test('rejects invalid outcome and revision combinations', () async {
    for (final row in <Map<String, dynamic>>[
      {'outcome': 'unexpected', 'server_revision': 8},
      {'outcome': 'applied', 'server_revision': '8'},
      {'outcome': 'conflict', 'server_revision': 0},
      {'outcome': 'not_found', 'server_revision': 1},
      {'outcome': null, 'server_revision': 8},
    ]) {
      await expectLater(invokeWith([row]), throwsStateError);
    }
  });

  test('rejects bad parameters without invoking server', () async {
    var calls = 0;
    final gateway = SupabaseArtistNameConditionalWriteGateway.forTesting((
      name,
      args,
    ) async {
      calls++;
      return [
        <String, dynamic>{'outcome': 'applied', 'server_revision': 8},
      ];
    });

    Future<CloudConditionalWriteResult> send({
      String id = 'artist-1',
      int revision = 7,
      String name = 'Artist',
      String canonical = 'artist',
    }) => gateway.updateArtistName(
      artistId: id,
      expectedServerRevision: revision,
      name: name,
      canonicalName: canonical,
      updatedAt: updatedAt,
    );

    await expectLater(send(id: '  '), throwsArgumentError);
    await expectLater(send(revision: 0), throwsArgumentError);
    await expectLater(send(name: '  '), throwsArgumentError);
    await expectLater(send(canonical: ' '), throwsArgumentError);
    expect(calls, 0);
  });

  test('propagates RPC errors; never converts them to success', () async {
    final gateway = SupabaseArtistNameConditionalWriteGateway.forTesting(
      (name, args) async => throw StateError('RPC offline'),
    );
    await expectLater(
      gateway.updateArtistName(
        artistId: 'artist-1',
        expectedServerRevision: 7,
        name: 'Artist',
        canonicalName: 'artist',
        updatedAt: updatedAt,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'RPC offline',
        ),
      ),
    );
  });
}
