import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/account/data/repositories/sqlite_local_account_binding_repository.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteLocalAccountBindingRepository repository;

  final now = DateTime.utc(2026, 10, 6, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    repository = SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
      now: () => now,
    );

    await appDatabase.database;
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('returns null when no account is bound', () async {
    expect(await repository.getBinding(), isNull);
  });

  test('binds the first account to the local library', () async {
    await repository.bindToUser('user_1');

    final binding = await repository.getBinding();

    expect(binding, isNotNull);
    expect(binding!.userId, 'user_1');
    expect(binding.boundAt, now);
    expect(binding.updatedAt, now);
  });

  test('trims account id before binding', () async {
    await repository.bindToUser('  user_1  ');

    final binding = await repository.getBinding();

    expect(binding!.userId, 'user_1');
  });

  test('binding the same account again is idempotent', () async {
    await repository.bindToUser('user_1');
    await repository.bindToUser('user_1');

    final binding = await repository.getBinding();

    expect(binding!.userId, 'user_1');
    expect(binding.boundAt, now);
    expect(binding.updatedAt, now);
  });

  test('rejects binding the local library to a different account', () async {
    await repository.bindToUser('user_1');

    expect(
      () => repository.bindToUser('user_2'),
      throwsA(
        isA<LocalAccountBindingConflict>()
            .having((error) => error.boundUserId, 'boundUserId', 'user_1')
            .having(
              (error) => error.requestedUserId,
              'requestedUserId',
              'user_2',
            ),
      ),
    );

    final binding = await repository.getBinding();

    expect(binding!.userId, 'user_1');
  });

  test('rejects blank account ids', () async {
    expect(() => repository.bindToUser('   '), throwsArgumentError);
  });

  test('clearBinding removes the local account binding', () async {
    await repository.bindToUser('user_1');

    await repository.clearBinding();

    expect(await repository.getBinding(), isNull);
  });
}
