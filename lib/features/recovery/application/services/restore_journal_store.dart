import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../../../core/identity/text_normalizer.dart';
import 'recovery_sync_hold_store.dart';

/// Files one restore session created, recorded before each one exists.
class RestoreJournal {
  RestoreJournal({
    required this.sessionId,
    required this.extractionDirectory,
    required List<String> reservedTokens,
    required List<String> createdFiles,
  }) : reservedTokens = List.unmodifiable(reservedTokens),
       createdFiles = List.unmodifiable(createdFiles);

  final String sessionId;
  final String extractionDirectory;

  /// Unique tokens embedded in the names of files about to be created.
  final List<String> reservedTokens;

  /// Paths of files this session created.
  final List<String> createdFiles;

  RestoreJournal reserve(String token) => RestoreJournal(
    sessionId: sessionId,
    extractionDirectory: extractionDirectory,
    reservedTokens: [...reservedTokens, token],
    createdFiles: createdFiles,
  );

  RestoreJournal created(String filePath) => RestoreJournal(
    sessionId: sessionId,
    extractionDirectory: extractionDirectory,
    reservedTokens: reservedTokens,
    createdFiles: [...createdFiles, filePath],
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'sessionId': sessionId,
    'extractionDirectory': extractionDirectory,
    'reservedTokens': reservedTokens,
    'createdFiles': createdFiles,
  };

  static RestoreJournal fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['sessionId'] is! String ||
        json['extractionDirectory'] is! String ||
        json['reservedTokens'] is! List ||
        json['createdFiles'] is! List) {
      throw const FormatException('Invalid restore journal.');
    }

    return RestoreJournal(
      sessionId: json['sessionId'] as String,
      extractionDirectory: json['extractionDirectory'] as String,
      reservedTokens: (json['reservedTokens'] as List).cast<String>(),
      createdFiles: (json['createdFiles'] as List).cast<String>(),
    );
  }
}

class RestoreJournalStore {
  const RestoreJournalStore({required this.directory});

  static const fileName = 'restore_journal.json';

  final RecoveryDirectoryProvider directory;

  Future<File> _file() async =>
      File(path.join((await directory()).path, fileName));

  Future<RestoreJournal?> read() async {
    final file = await _file();

    if (!await file.exists()) {
      return null;
    }

    return RestoreJournal.fromJson(jsonDecode(await file.readAsString()));
  }

  Future<void> write(RestoreJournal journal) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(journal.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();

    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Outcome of discarding a restore session's files.
class RestoreJournalCleanup {
  const RestoreJournalCleanup({
    required this.deletedFiles,
    required this.keptReferencedFiles,
  });

  final List<String> deletedFiles;

  /// Journal files the database references; a committed restore owns them.
  final List<String> keptReferencedFiles;
}

/// Removes files left by an interrupted or failed restore session.
///
/// Only files recorded in the journal are considered, and any file the
/// database references is kept, because it belongs to a committed restore.
class RestoreJournalRecovery {
  const RestoreJournalRecovery({
    required this.journalStore,
    required this.artworkDirectory,
  });

  final RestoreJournalStore journalStore;
  final RecoveryDirectoryProvider artworkDirectory;

  Future<RestoreJournalCleanup?> recover(DatabaseExecutor executor) async {
    final journal = await journalStore.read();

    if (journal == null) {
      return null;
    }

    final cleanup = await discard(journal, executor);
    await journalStore.clear();
    return cleanup;
  }

  /// Deletes the unreferenced files of [journal] and its extraction folder.
  /// The journal itself is left for the caller to clear.
  Future<RestoreJournalCleanup> discard(
    RestoreJournal journal,
    DatabaseExecutor executor,
  ) async {
    final referenced = {
      for (final row in await executor.query(
        DatabaseTables.artworkAssets,
        columns: ['file_path'],
      ))
        TextNormalizer.normalizePath(row['file_path'] as String),
    };

    final candidates = <String>{...journal.createdFiles};
    final artworkRoot = await artworkDirectory();

    // A crash between reserving a name and recording the file leaves only
    // the token; it is unique to this session, so matching is safe.
    if (journal.reservedTokens.isNotEmpty && await artworkRoot.exists()) {
      await for (final entity in artworkRoot.list(followLinks: false)) {
        final name = path.basename(entity.path);

        if (entity is File &&
            journal.reservedTokens.any((token) => name.contains(token))) {
          candidates.add(entity.path);
        }
      }
    }

    final deleted = <String>[];
    final kept = <String>[];

    for (final candidate in candidates) {
      if (referenced.contains(TextNormalizer.normalizePath(candidate))) {
        kept.add(candidate);
        continue;
      }

      if (await FileSystemEntity.type(candidate, followLinks: false) ==
          FileSystemEntityType.file) {
        await File(candidate).delete();
        deleted.add(candidate);
      }
    }

    final extraction = Directory(journal.extractionDirectory);

    if (path.basename(extraction.path).startsWith('.sonus_restore_') &&
        await FileSystemEntity.type(extraction.path, followLinks: false) ==
            FileSystemEntityType.directory) {
      await extraction.delete(recursive: true);
    }

    deleted.sort();
    kept.sort();

    return RestoreJournalCleanup(deletedFiles: deleted, keptReferencedFiles: kept);
  }
}
