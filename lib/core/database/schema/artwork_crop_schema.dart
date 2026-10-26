import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// How a cover, artist banner or artist portrait was cropped (SN-45).
///
/// The cropped image is an ordinary artwork asset assigned to the album
/// edition or artist, so every screen, Android Auto, sync and backups use
/// it unchanged. This table only remembers the untouched original and the
/// crop rectangle, so the crop can be moved again or reset later.
///
/// Kept in backups and in the cloud archive. Without a row, the
/// assigned artwork simply shows as it is. The rectangle is normalized to
/// the original image (0 to 1 on each axis). A row whose output is no
/// longer the assigned artwork (replaced elsewhere) is ignored.
abstract final class ArtworkCropSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.artworkCrops} (
        target_type TEXT NOT NULL
          CHECK (target_type IN ('albumEdition', 'artistBanner', 'artistPortrait')),
        target_id TEXT NOT NULL,
        source_artwork_id TEXT NOT NULL
          REFERENCES ${DatabaseTables.artworkAssets}(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        output_artwork_id TEXT NOT NULL
          REFERENCES ${DatabaseTables.artworkAssets}(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        crop_left REAL NOT NULL CHECK (crop_left >= 0 AND crop_left < 1),
        crop_top REAL NOT NULL CHECK (crop_top >= 0 AND crop_top < 1),
        crop_width REAL NOT NULL
          CHECK (crop_width > 0 AND crop_left + crop_width <= 1.000001),
        crop_height REAL NOT NULL
          CHECK (crop_height > 0 AND crop_top + crop_height <= 1.000001),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (target_type, target_id)
      )
    ''');
  }
}
