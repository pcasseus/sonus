import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'library_mutation_coordinator.dart';
import 'database_migrations.dart';
import 'schema/account_schema.dart';
import 'schema/analytics_schema.dart';
import 'schema/chart_schema.dart';
import 'schema/import_schema.dart';
import 'schema/library_schema.dart';
import 'schema/lyrics_schema.dart';
import 'schema/organization_schema.dart';
import 'schema/playlist_schema.dart';
import 'schema/sync_schema.dart';

class AppDatabase {
  AppDatabase({
    sqflite.DatabaseFactory? databaseFactory,
    String? databasePath,
    LibraryMutationCoordinator? mutationCoordinator,
  }) : mutationCoordinator =
           mutationCoordinator ?? LibraryMutationCoordinator(),
       _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _databasePathOverride = databasePath;

  static const String databaseName = 'sonus_next.db';
  static const int databaseVersion = 34;

  /// Coordinates normal database transactions with recovery.
  final LibraryMutationCoordinator mutationCoordinator;

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePathOverride;

  sqflite.Database? _database;
  Future<sqflite.Database>? _openingDatabase;

  Future<sqflite.Database> get database async {
    final current = _database;

    if (current != null && current.isOpen) {
      return current;
    }

    final opening = _openingDatabase;

    if (opening != null) {
      return opening;
    }

    final future = _open();
    _openingDatabase = future;

    try {
      final opened = await future;
      _database = opened;
      return opened;
    } finally {
      if (identical(_openingDatabase, future)) {
        _openingDatabase = null;
      }
    }
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
    await ImportSchema.create(db);
    await LibrarySchema.create(db);
    await ImportSchema.createSongImportReviews(db);
    await LyricsSchema.create(db);
    await AnalyticsSchema.create(db);
    await ChartSchema.create(db);
    await PlaylistSchema.create(db);
    await SyncSchema.create(db);
    await AccountSchema.create(db);
    await OrganizationSchema.create(db);
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
  ) {
    return mutationCoordinator.runMutation(() async {
      final db = await database;
      return db.transaction(action);
    });
  }

  Future<void> close() async {
    final opening = _openingDatabase;

    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // Opening already failed, so there is nothing to close.
      }
    }

    final current = _database;
    _database = null;
    _openingDatabase = null;

    if (current != null && current.isOpen) {
      await current.close();
    }
  }
}
