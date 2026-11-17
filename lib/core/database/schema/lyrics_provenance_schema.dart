import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// Where each lyrics text came from (App Update 1.3, database version 48).
///
/// Plain and synchronised lyrics each carry their own provenance: source,
/// the listener's edit stamp, when the text was last written, and a
/// confidence that only generated text may have. The listener's timing
/// correction (`offset_ms`) is applied on read, never baked into the text.
/// Provider details are row-level and describe whichever text came from a
/// provider.
///
/// Rows stored before this version keep their text with every provenance
/// column null: "imported, source not recorded" (legacy). Nothing is
/// inferred to be a user edit.
///
/// The columns are added with `ALTER TABLE` both on upgrade and on a fresh
/// install, so both schemas are identical. Every column is nullable (the
/// offset too: null means no correction), because rows restored from an
/// older backup carry none of them and restore fills them with null.
abstract final class LyricsProvenanceSchema {
  /// Stored source values. `user` is the listener's own edit; `generated`
  /// is never official and ranks lowest.
  static const List<String> sources = [
    'user',
    'provider',
    'embedded',
    'sidecarLrc',
    'sidecarTxt',
    'generated',
  ];

  static String _sourceCheck(String column) =>
      'CHECK ($column IS NULL OR $column IN '
      "(${sources.map((s) => "'$s'").join(', ')}))";

  static List<(String, String)> _textColumns(String kind) => [
    ('${kind}_source', 'TEXT ${_sourceCheck('${kind}_source')}'),
    // Set exactly when the source is the listener's edit.
    (
      '${kind}_user_edited_at',
      'TEXT CHECK ((${kind}_user_edited_at IS NULL) = '
          "(${kind}_source IS NULL OR ${kind}_source <> 'user'))",
    ),
    ('${kind}_updated_at', 'TEXT'),
    // Only generated text has a confidence, between 0 and 1.
    (
      '${kind}_confidence',
      'REAL CHECK (${kind}_confidence IS NULL OR '
          "(${kind}_source = 'generated' AND "
          '${kind}_confidence BETWEEN 0 AND 1))',
    ),
  ];

  /// Every column version 48 adds, in order, with its definition.
  static final List<(String, String)> columns = [
    ..._textColumns('plain'),
    ..._textColumns('synced'),
    (
      'offset_ms',
      'INTEGER CHECK (offset_ms IS NULL OR '
          'offset_ms BETWEEN -600000 AND 600000)',
    ),
    ('offset_user_edited_at', 'TEXT'),
    ('provider', 'TEXT'),
    ('provider_ref', 'TEXT'),
    (
      'provider_licence',
      'TEXT CHECK (provider_licence IS NULL OR '
          "provider_licence IN ('cacheable', 'displayOnly'))",
    ),
    ('language', 'TEXT'),
  ];

  static List<String> get columnNames => [for (final (n, _) in columns) n];

  /// Adds the columns that are missing; running it again changes nothing.
  static Future<void> addColumns(DatabaseExecutor db) async {
    final existing = {
      for (final row in await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.trackLyrics})',
      ))
        row['name']! as String,
    };
    for (final (name, definition) in columns) {
      if (existing.contains(name)) continue;
      await db.execute(
        'ALTER TABLE ${DatabaseTables.trackLyrics} ADD COLUMN $name $definition',
      );
    }
  }
}
