import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../application/repositories/local_account_binding_repository.dart';
import '../../domain/entities/local_account_binding.dart';

class SqliteLocalAccountBindingRepository
    implements LocalAccountBindingRepository {
  const SqliteLocalAccountBindingRepository({
    required this.appDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase appDatabase;
  final DateTime Function() _now;

  @override
  Future<LocalAccountBinding?> getBinding() async {
    final db = await appDatabase.database;

    final rows = await db.query(
      DatabaseTables.localAccountBinding,
      where: 'id = ?',
      whereArgs: const [1],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _fromRow(rows.single);
  }

  @override
  Future<void> bindToUser(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    await appDatabase.transaction((transaction) async {
      final rows = await transaction.query(
        DatabaseTables.localAccountBinding,
        where: 'id = ?',
        whereArgs: const [1],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final existing = _fromRow(rows.single);

        if (existing.userId != normalizedUserId) {
          throw LocalAccountBindingConflict(
            boundUserId: existing.userId,
            requestedUserId: normalizedUserId,
          );
        }

        return;
      }

      final timestamp = _now().toUtc();

      await transaction.insert(DatabaseTables.localAccountBinding, {
        'id': 1,
        'user_id': normalizedUserId,
        'bound_at': timestamp.toIso8601String(),
        'updated_at': timestamp.toIso8601String(),
      });
    });
  }

  @override
  Future<void> clearBinding() async {
    final db = await appDatabase.database;

    await db.delete(
      DatabaseTables.localAccountBinding,
      where: 'id = ?',
      whereArgs: const [1],
    );
  }

  LocalAccountBinding _fromRow(Map<String, Object?> row) {
    return LocalAccountBinding(
      userId: row['user_id'] as String,
      boundAt: DateTime.parse(row['bound_at'] as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
    );
  }
}
