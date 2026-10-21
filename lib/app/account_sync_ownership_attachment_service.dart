import '../core/database/app_database.dart';
import '../core/identity/entity_id.dart';
import '../features/account/data/repositories/sqlite_local_account_binding_repository.dart';
import '../features/sync/data/daos/local_sync_dao.dart';
import '../features/sync/data/repositories/sqlite_local_sync_repository.dart';

class AccountSyncOwnershipAttachmentService {
  const AccountSyncOwnershipAttachmentService({required this.appDatabase});

  final AppDatabase appDatabase;

  Future<int> attachUnownedToUser(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    final bindingRepository = SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
    );

    return appDatabase.transaction((transaction) async {
      await bindingRepository.bindToUserInTransaction(
        transaction,
        normalizedUserId,
      );

      final repository = SqliteLocalSyncRepository(
        dao: LocalSyncDao(transaction),
        generateId: EntityId.syncOutbox,
        now: DateTime.now,
      );

      return repository.claimUnowned(normalizedUserId);
    });
  }
}
