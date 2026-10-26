import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// SN-49: marks release dates that are known to hold only a year.
///
/// Before precision was recorded, an imported file's year tag was saved
/// as January 1 of that year (local midnight), which then showed as an
/// exact day. The import provenance of each date is kept in the metadata
/// field states, so those dates can be told apart from dates someone typed
/// in: a date whose provenance is a file tag or file name, set
/// automatically and never edited, at the start of a year, is year-only.
///
/// Only rows without a precision are touched, and no date value changes,
/// so running it again (for example after restoring an older backup) is
/// safe.
abstract final class ReleaseDatePrecisionBackfill {
  static Future<int> run(DatabaseExecutor db) => db.rawUpdate('''
    UPDATE ${DatabaseTables.albumEditions}
    SET release_date_precision = 'year'
    WHERE release_date IS NOT NULL
      AND release_date_precision IS NULL
      -- January 1 local midnight is December 31 in UTC east of Greenwich.
      AND substr(release_date, 6, 5) IN ('01-01', '12-31')
      AND EXISTS (
        SELECT 1 FROM ${DatabaseTables.metadataFieldStates} m
        WHERE m.entity_type = 'albumEdition'
          AND m.entity_id = ${DatabaseTables.albumEditions}.id
          AND m.field_name = 'releaseDate'
          AND m.source IN ('embeddedTag', 'filename')
          AND m.authority IN ('imported', 'inferred')
      )
  ''');
}
