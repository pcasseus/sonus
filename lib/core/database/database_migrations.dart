import 'package:sqflite/sqflite.dart';

abstract final class DatabaseMigrations {
  static Future<void> migrate(
    Database db, {
    required int oldVersion,
    required int newVersion,
  }) async {
    if (oldVersion >= newVersion) {
      return;
    }

    for (
      var targetVersion = oldVersion + 1;
      targetVersion <= newVersion;
      targetVersion++
    ) {
      await _migrateTo(db, targetVersion);
    }
  }

  static Future<void> _migrateTo(Database db, int targetVersion) async {
    switch (targetVersion) {
      case 1:
        // Version 1 is the clean Sonus Next baseline and is created
        // through onCreate rather than upgraded into.
        return;

      default:
        throw UnsupportedError(
          'No Sonus database migration exists for version $targetVersion.',
        );
    }
  }
}
