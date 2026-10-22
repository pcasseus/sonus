import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../../../core/identity/text_normalizer.dart';
import 'atomic_state_file.dart';
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

/// Persists the restore journal through [AtomicStateFile], so a crash
/// leaves the previous or the new journal, never a partial one.
class RestoreJournalStore {
  const RestoreJournalStore({
    required this.directory,
    this.stateFile = const AtomicStateFile(),
  });

  static const fileName = 'restore_journal.json';

  final RecoveryDirectoryProvider directory;
  final AtomicStateFile stateFile;

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
    await stateFile.writeString(await _file(), jsonEncode(journal.toJson()));
  }

  Future<void> clear() async {
    await stateFile.delete(await _file());
  }
}

/// Outcome of discarding a restore session's files.
class RestoreJournalCleanup {
  const RestoreJournalCleanup({
    required this.deletedFiles,
    required this.keptReferencedFiles,
    this.rejectedEntries = const [],
  });

  final List<String> deletedFiles;

  /// Journal files the database references; a committed restore owns them.
  final List<String> keptReferencedFiles;

  /// Journal entries that were not provably owned by the session (outside
  /// managed storage, traversal, links, foreign names or tokens). They are
  /// never deleted.
  final List<String> rejectedEntries;
}

/// Removes files left by an interrupted or failed restore session.
///
/// The journal is app-private, but it is still treated as untrusted
/// input: a path is deleted only when it is provably one this session
/// created, never merely because the journal lists it.
///
/// * Artwork: a regular file (not a link) directly inside the managed
///   artwork directory, whose name carries one of the session's reserved
///   tokens, and which the database does not reference (a committed
///   restore owns referenced files).
/// * Extraction: exactly `<recovery directory>/.sonus_restore_<session>`,
///   a real directory and not a link.
class RestoreJournalRecovery {
  const RestoreJournalRecovery({
    required this.journalStore,
    required this.artworkDirectory,
  });

  final RestoreJournalStore journalStore;
  final RecoveryDirectoryProvider artworkDirectory;

  /// Session identifiers are generated without separators.
  static final _sessionIdPattern = RegExp(r'^[A-Za-z0-9]{1,64}$');

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

    final rejected = <String>[];
    final sessionId = journal.sessionId;
    final validSession = _sessionIdPattern.hasMatch(sessionId);

    // Tokens are the installer's `restore<session>n<index>`; anything else
    // (an empty or broad token would match unrelated files) is refused.
    final tokenPattern = RegExp('^restore${RegExp.escape(sessionId)}n[0-9]+\$');
    final tokens = <String>[];

    for (final token in journal.reservedTokens) {
      if (validSession && tokenPattern.hasMatch(token)) {
        tokens.add(token);
      } else {
        rejected.add('token:$token');
      }
    }

    // Listed through the configured path, so listed paths have the same
    // form as the database's; the resolved form is only for containment.
    final managedArtwork = await artworkDirectory();
    final artworkRoot = await _resolvedDirectory(managedArtwork);
    final candidates = <String>{...journal.createdFiles};

    // A crash between reserving a name and recording the file leaves only
    // the token; it is unique to this session, so matching is safe.
    if (tokens.isNotEmpty && artworkRoot != null) {
      await for (final entity in managedArtwork.list(followLinks: false)) {
        if (entity is File &&
            _carriesToken(path.basename(entity.path), tokens)) {
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

      if (artworkRoot == null ||
          !await _isOwnedArtworkFile(
            candidate,
            artworkRoot,
            managedArtwork.path,
            tokens,
          )) {
        rejected.add(candidate);
        continue;
      }

      await File(candidate).delete();
      deleted.add(candidate);
    }

    final extraction = journal.extractionDirectory;

    if (await _isOwnedExtraction(extraction, sessionId, validSession)) {
      await Directory(extraction).delete(recursive: true);
    } else if (await FileSystemEntity.type(extraction, followLinks: false) !=
        FileSystemEntityType.notFound) {
      rejected.add(extraction);
    }

    deleted.sort();
    kept.sort();
    rejected.sort();

    return RestoreJournalCleanup(
      deletedFiles: deleted,
      keptReferencedFiles: kept,
      rejectedEntries: rejected,
    );
  }

  static bool _carriesToken(String name, List<String> tokens) => tokens.any(
    (token) => name == 'artwork_$token' || name.startsWith('artwork_$token.'),
  );

  /// True only for an existing regular file, reached without links,
  /// directly inside [artworkRoot], named with one of [tokens].
  Future<bool> _isOwnedArtworkFile(
    String candidate,
    String artworkRoot,
    String managedArtworkPath,
    List<String> tokens,
  ) async {
    if (!_isPlainAbsolute(candidate) ||
        !_carriesToken(path.basename(candidate), tokens)) {
      return false;
    }

    if (await FileSystemEntity.type(candidate, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }

    // A path through a linked directory must not be accepted merely
    // because its resolved parent points back into managed artwork.
    final lexicalParent = path.normalize(path.dirname(candidate));
    final expectedParent = path.normalize(managedArtworkPath);

    if (!path.equals(lexicalParent, expectedParent)) {
      return false;
    }

    final parent = await _resolvedDirectory(Directory(lexicalParent));
    return parent != null && path.equals(parent, artworkRoot);
  }

  /// True only for `<recovery directory>/.sonus_restore_<session>` as a
  /// real directory (not a link) inside the real recovery directory.
  Future<bool> _isOwnedExtraction(
    String extraction,
    String sessionId,
    bool validSession,
  ) async {
    if (!validSession || !_isPlainAbsolute(extraction)) {
      return false;
    }

    final recoveryRoot = await _resolvedDirectory(
      await journalStore.directory(),
    );

    if (recoveryRoot == null ||
        path.basename(extraction) != '.sonus_restore_$sessionId') {
      return false;
    }

    if (await FileSystemEntity.type(extraction, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }

    final parent = await _resolvedDirectory(
      Directory(path.dirname(extraction)),
    );
    return parent != null && path.equals(parent, recoveryRoot);
  }

  /// Absolute, with no `.` or `..` segments to reinterpret.
  static bool _isPlainAbsolute(String candidate) =>
      path.isAbsolute(candidate) &&
      !path.split(candidate).any((part) => part == '.' || part == '..');

  /// The directory's real path, or null if it is not an existing directory.
  static Future<String?> _resolvedDirectory(Directory directory) async {
    try {
      if (!await directory.exists()) return null;
      return path.canonicalize(await directory.resolveSymbolicLinks());
    } on FileSystemException {
      return null;
    }
  }
}
