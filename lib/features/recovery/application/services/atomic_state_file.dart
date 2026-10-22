import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

typedef StateFileRename = Future<void> Function(File source, String target);
typedef StateFileDelete = Future<void> Function(File file);

/// Durable replacement of the small recovery state files (restore journal,
/// sync hold, recovery status).
///
/// A write goes to a temporary file with a name unique to that write, is
/// flushed, and is then renamed over the target. Readers therefore see the
/// complete old content or the complete new content, never a partial file,
/// and two writes (or a temporary left by a crash) never share a temporary.
///
/// On Windows, replacing or deleting a file fails with "access denied"
/// (`ERROR_ACCESS_DENIED`, 5) or a sharing violation (32) while any other
/// process (typically real-time antivirus scanning or search indexing a
/// file that was just written) holds it open without delete sharing. Only
/// those two errors, only on Windows, are retried with a short bounded
/// backoff. The retried operation is the same atomic rename (or delete) of
/// a temporary that is already complete and flushed, so a retry can never
/// expose partial content and repeating it has the same effect as a first
/// success. Any other error, or the same error after the last attempt, is
/// rethrown unchanged; the temporary is then removed and the target keeps
/// its previous complete content.
class AtomicStateFile {
  const AtomicStateFile({
    this.retryDelays = defaultRetryDelays,
    this._isWindows,
    this._rename,
    this._delete,
  });

  /// About 1.3 seconds in total before giving up.
  static const defaultRetryDelays = [
    Duration(milliseconds: 10),
    Duration(milliseconds: 20),
    Duration(milliseconds: 40),
    Duration(milliseconds: 80),
    Duration(milliseconds: 160),
    Duration(milliseconds: 320),
    Duration(milliseconds: 640),
  ];

  /// Windows errors caused by another process holding the file open.
  static const windowsTransientErrors = {5, 32};

  /// Temporaries older than this are leftovers of an interrupted write.
  static const staleTemporaryAge = Duration(hours: 1);

  final List<Duration> retryDelays;
  final bool Function()? _isWindows;
  final StateFileRename? _rename;
  final StateFileDelete? _delete;

  static final _random = Random.secure();

  bool get _windows => (_isWindows ?? () => Platform.isWindows)();

  /// Atomically replaces [target] with [contents].
  Future<void> writeString(File target, String contents) async {
    await target.parent.create(recursive: true);

    final temporary = File(temporaryPathFor(target));

    try {
      await temporary.writeAsString(contents, flush: true);
      await _retrying(
        () => (_rename ?? _defaultRename)(temporary, target.path),
      );
    } catch (_) {
      // The target still holds its previous complete content.
      try {
        if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
            FileSystemEntityType.file) {
          await temporary.delete();
        }
      } catch (_) {
        // A leftover temporary is ignored by readers and swept later.
      }

      rethrow;
    }
  }

  /// Deletes [target] if it exists, and sweeps stale temporaries of it.
  Future<void> delete(File target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await _retrying(() => (_delete ?? _defaultDelete)(target));
    }

    await sweepStaleTemporaries(target);
  }

  /// Removes temporaries of [target] left by interrupted writes. Recent ones
  /// are kept, because a concurrent writer may still own them.
  Future<void> sweepStaleTemporaries(File target, {DateTime? now}) async {
    final directory = target.parent;

    if (!await directory.exists()) return;

    final name = path.basename(target.path);
    final current = now ?? DateTime.now();

    await for (final entity in directory.list(followLinks: false)) {
      final candidate = path.basename(entity.path);

      if (entity is! File || !isTemporaryName(name, candidate)) continue;

      try {
        if (current.difference((await entity.stat()).modified) >=
            staleTemporaryAge) {
          await entity.delete();
        }
      } on FileSystemException {
        // Best effort; readers never consult temporaries.
      }
    }
  }

  /// `<target>.<random>.tmp`, unique per write.
  static String temporaryPathFor(File target) {
    final token = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();

    return '${target.path}.$token.tmp';
  }

  /// Whether [candidate] is a temporary of [targetName], including the
  /// fixed `<target>.tmp` name used by earlier versions.
  static bool isTemporaryName(String targetName, String candidate) =>
      candidate == '$targetName.tmp' ||
      RegExp(
        '^${RegExp.escape(targetName)}\\.[0-9a-f]{16}\\.tmp\$',
      ).hasMatch(candidate);

  Future<void> _retrying(Future<void> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await operation();
        return;
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;

        if (!_windows ||
            !windowsTransientErrors.contains(code) ||
            attempt >= retryDelays.length) {
          rethrow;
        }
      }

      await Future<void>.delayed(retryDelays[attempt]);
    }
  }

  static Future<void> _defaultRename(File source, String target) async {
    await source.rename(target);
  }

  static Future<void> _defaultDelete(File file) async {
    await file.delete();
  }
}
