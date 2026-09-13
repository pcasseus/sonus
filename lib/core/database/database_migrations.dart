import 'package:sqflite/sqflite.dart';

import 'database_tables.dart';
import 'schema/import_schema.dart';
import 'schema/library_schema.dart';
import 'schema/sync_schema.dart';

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

      case 2:
        await ImportSchema.createImportBatches(db);
        return;

      case 3:
        await LibrarySchema.createArtworkAssets(db);

        await db.execute(
          'ALTER TABLE ${DatabaseTables.artists} '
          'ADD COLUMN header_artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute(
          'ALTER TABLE ${DatabaseTables.artists} '
          'ADD COLUMN top_artists_artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute(
          'ALTER TABLE ${DatabaseTables.albumEditions} '
          'ADD COLUMN artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute(
          'ALTER TABLE ${DatabaseTables.songs} '
          'ADD COLUMN artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute('''
    CREATE INDEX idx_artists_header_artwork_id
    ON ${DatabaseTables.artists}(header_artwork_id)
  ''');

        await db.execute('''
    CREATE INDEX idx_artists_top_artists_artwork_id
    ON ${DatabaseTables.artists}(top_artists_artwork_id)
  ''');

        await db.execute('''
    CREATE INDEX idx_album_editions_artwork_id
    ON ${DatabaseTables.albumEditions}(artwork_id)
  ''');

        await db.execute('''
    CREATE INDEX idx_songs_artwork_id
    ON ${DatabaseTables.songs}(artwork_id)
  ''');

        return;

      case 4:
        await SyncSchema.create(db);
        return;

      default:
        throw UnsupportedError(
          'No Sonus database migration exists for version $targetVersion.',
        );
    }
  }
}
