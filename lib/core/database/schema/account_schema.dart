import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class AccountSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createLocalAccountBinding(db);
  }

  static Future<void> createLocalAccountBinding(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.localAccountBinding} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_id TEXT NOT NULL,
        bound_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
}
