import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/data/services/sync_status_store.dart';

void main() {
  test('returns null when no last successful sync exists', () async {
    final store = SyncStatusStore.forTesting(
      getString: (_) async => null,
      setString: (_, _) async {},
    );

    expect(await store.getLastSuccessfulSync('user-1'), isNull);
  });

  test('restores stored timestamp as UTC', () async {
    final store = SyncStatusStore.forTesting(
      getString: (_) async => '2026-10-06T18:30:00.000Z',
      setString: (_, _) async {},
    );

    expect(
      await store.getLastSuccessfulSync('user-1'),
      DateTime.utc(2026, 10, 6, 18, 30),
    );
  });

  test('stores timestamp separately by user id', () async {
    final values = <String, String>{};

    final store = SyncStatusStore.forTesting(
      getString: (key) async => values[key],
      setString: (key, value) async {
        values[key] = value;
      },
    );

    await store.saveLastSuccessfulSync('user-1', DateTime.utc(2026, 10, 6, 18));

    await store.saveLastSuccessfulSync('user-2', DateTime.utc(2026, 10, 7, 19));

    expect(
      await store.getLastSuccessfulSync('user-1'),
      DateTime.utc(2026, 10, 6, 18),
    );

    expect(
      await store.getLastSuccessfulSync('user-2'),
      DateTime.utc(2026, 10, 7, 19),
    );
  });

  test('rejects blank user id', () async {
    final store = SyncStatusStore.forTesting(
      getString: (_) async => null,
      setString: (_, _) async {},
    );

    await expectLater(store.getLastSuccessfulSync('   '), throwsArgumentError);
  });
}
