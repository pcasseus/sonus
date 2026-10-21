import 'dart:io';

import 'package:path/path.dart' as path;

/// Removes temporary directories left behind by an interrupted backup or
/// restore (for example, when the process was killed mid-operation).
///
/// Only direct child directories with a Sonus temporary prefix are
/// considered. Files, links, and anything else are never touched, and
/// recent directories are kept because an operation may still own them.
class BackupTemporaryCleaner {
  const BackupTemporaryCleaner({
    this.minimumAge = const Duration(hours: 1),
    this.now,
  });

  static const temporaryPrefixes = [
    '.sonus_backup_stage_',
    '.sonus_verified_',
    '.sonus_backup_write_',
    '.sonus_restore_',
  ];

  final Duration minimumAge;
  final DateTime Function()? now;

  Future<List<String>> clean(Directory directory) async {
    if (!await directory.exists()) {
      return const [];
    }

    final current = (now ?? DateTime.now)();
    final removed = <String>[];

    await for (final entity in directory.list(followLinks: false)) {
      final name = path.basename(entity.path);

      if (entity is! Directory ||
          !temporaryPrefixes.any((prefix) => name.startsWith(prefix))) {
        continue;
      }

      // Re-check without following links before deleting recursively.
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }

      final modified = (await entity.stat()).modified;

      if (current.difference(modified) < minimumAge) {
        continue;
      }

      await entity.delete(recursive: true);
      removed.add(entity.path);
    }

    removed.sort();
    return List.unmodifiable(removed);
  }
}
