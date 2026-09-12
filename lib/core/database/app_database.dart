import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'database_migrations.dart';
import 'schema/import_schema.dart';
import 'schema/library_schema.dart';

class AppDatabase {
  AppDatabase({sqflite.DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
      _databasePathOverride = databasePath;

  static const String databaseName = 'sonus_next.db';
  static const int databaseVersion = 3;

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePathOverride;

  sqflite.Database? _database;

  Future<sqflite.Database> get database async {
    final current = _database;

    if (current != null && current.isOpen) {
      return current;
    }

    final opened = await _open();
    _database = opened;
    return opened;
  }

  Future<sqflite.Database> _open() async {
    final resolvedPath =
        _databasePathOverride ??
        path.join(await _databaseFactory.getDatabasesPath(), databaseName);

    return _databaseFactory.openDatabase(
      resolvedPath,
      options: sqflite.OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onConfigure(sqflite.Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.transaction((transaction) async {
      await LibrarySchema.create(transaction);
      await ImportSchema.create(transaction);
    });
  }

  Future<void> _onUpgrade(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await DatabaseMigrations.migrate(
      db,
      oldVersion: oldVersion,
      newVersion: newVersion,
    );
  }

  Future<T> transaction<T>(
    Future<T> Function(sqflite.Transaction transaction) action,
  ) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<void> close() async {
    final current = _database;

    if (current == null) {
      return;
    }

    await current.close();
    _database = null;
  }
}
