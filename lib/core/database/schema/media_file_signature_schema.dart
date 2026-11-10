import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// App Update 1.2 (version 43), BUG-09: the identity of a file's audio,
/// read from its bytes, beside each file binding.
///
/// A tag editor rewrites only a file's tags, so the audio, and with it the
/// signature, survives retagging, renaming, moving and rewriting. That lets
/// a scan recognise the file it already knows instead of importing it
/// again as a new song.
///
/// - `audio_signature`: `v1:<audio bytes>:<SHA-256 of the first and last
///   64 KiB of the audio>`; a quick, sampled identity. Never enough alone
///   to rebind a file.
/// - `audio_full_hash`: SHA-256 of all the audio bytes; the proof required
///   before a file is rebound to a song automatically.
/// - `signature_version`: which signature rules produced both, so a later
///   change of rules can tell old values apart.
///
/// All three are null until a scan reads the file, and stay null for a
/// file whose audio cannot be read with confidence. Bindings are
/// device-local: none of this leaves the device.
abstract final class MediaFileSignatureColumns {
  static const String audioSignature = 'audio_signature';
  static const String audioFullHash = 'audio_full_hash';
  static const String signatureVersion = 'signature_version';

  static const String indexName = 'idx_media_file_bindings_audio_signature';

  /// Column, definition: the same for a fresh database and an upgrade.
  static const List<(String, String)> columns = [
    (audioSignature, 'TEXT'),
    (audioFullHash, 'TEXT'),
    (
      signatureVersion,
      'INTEGER CHECK (signature_version IS NULL OR signature_version >= 1)',
    ),
  ];

  /// The columns as they appear in `CREATE TABLE`.
  static String get definitions => [
    for (final (name, definition) in columns) '$name $definition',
  ].join(',\n        ');

  static Future<void> createIndex(DatabaseExecutor db) => db.execute('''
    CREATE INDEX IF NOT EXISTS $indexName
    ON ${DatabaseTables.mediaFileBindings}($audioSignature)
  ''');
}

/// App Update 1.2 (version 43), BUG-09: the audio of every file this device
/// permanently deleted, so a renamed or moved copy of a deleted song is not
/// imported again.
///
/// Written only from a signature that was read from the deleted file's own
/// bytes; a deleted file that was never read has no row here, and none is
/// ever made up for it.
///
/// Device-local, like the deletion ledger: never backed up or restored.
abstract final class DeletedAudioSignatureSchema {
  static Future<void> create(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.deletedAudioSignatures} (
      audio_signature TEXT PRIMARY KEY NOT NULL
        CHECK (length(audio_signature) > 0),
      audio_full_hash TEXT,
      song_id TEXT NOT NULL CHECK (length(song_id) > 0),
      operation_id TEXT NOT NULL,
      recorded_at TEXT NOT NULL
    )
  ''');
}
