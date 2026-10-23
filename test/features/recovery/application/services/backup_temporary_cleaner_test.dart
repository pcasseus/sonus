import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/services/backup_temporary_cleaner.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_cleaner_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  // Treat everything on disk as stale unless a test says otherwise.
  BackupTemporaryCleaner staleCleaner() => BackupTemporaryCleaner(
    now: () => DateTime.now().add(const Duration(days: 1)),
  );

  test('removes stale Sonus temporary directories', () async {
    for (final prefix in BackupTemporaryCleaner.temporaryPrefixes) {
      final directory = Directory(path.join(root.path, '${prefix}abc'));
      await directory.create();
      await File(path.join(directory.path, 'partial.bin')).writeAsBytes([1]);
    }

    final removed = await staleCleaner().clean(root);

    expect(removed, hasLength(BackupTemporaryCleaner.temporaryPrefixes.length));
    expect(await root.list().isEmpty, isTrue);
  });

  test('never touches backups, user files, or unrelated folders', () async {
    final backup = File(path.join(root.path, 'mine.sonusbackup'));
    await backup.writeAsBytes([1, 2, 3]);

    final prefixedFile = File(path.join(root.path, '.sonus_verified_file'));
    await prefixedFile.writeAsBytes([4]);

    final unrelated = Directory(path.join(root.path, 'sonus_backup_stage_x'));
    await unrelated.create();

    final removed = await staleCleaner().clean(root);

    expect(removed, isEmpty);
    expect(await backup.readAsBytes(), [1, 2, 3]);
    expect(await prefixedFile.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test('keeps recent directories an operation may still own', () async {
    final active = Directory(path.join(root.path, '.sonus_backup_stage_now'));
    await active.create();

    final removed = await const BackupTemporaryCleaner().clean(root);

    expect(removed, isEmpty);
    expect(await active.exists(), isTrue);
  });

  test('does not follow a link into another directory', () async {
    final outside = await Directory.systemTemp.createTemp('sonus_outside_');

    try {
      final precious = File(path.join(outside.path, 'precious.txt'));
      await precious.writeAsString('keep');

      final link = Link(path.join(root.path, '.sonus_restore_link'));

      try {
        await link.create(outside.path);
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable on this host.');
        return;
      }

      await staleCleaner().clean(root);

      expect(await precious.readAsString(), 'keep');
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test('accepts a missing directory', () async {
    final missing = Directory(path.join(root.path, 'missing'));

    expect(await staleCleaner().clean(missing), isEmpty);
  });
}
