import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

class BackupArchiveWriter {
  const BackupArchiveWriter();

  Future<File> write({
    required Directory stagingDirectory,
    required File destination,
  }) async {
    if (!await stagingDirectory.exists()) {
      throw StateError('Backup staging directory does not exist.');
    }

    if (!destination.path.toLowerCase().endsWith('.sonusbackup')) {
      throw ArgumentError.value(
        destination.path,
        'destination',
        'Backup filename must end with .sonusbackup.',
      );
    }

    final manifest = File(path.join(stagingDirectory.path, 'manifest.json'));

    final library = File(path.join(stagingDirectory.path, 'library.json'));

    if (!await manifest.exists() || !await library.exists()) {
      throw const FormatException(
        'Backup staging requires manifest.json and library.json.',
      );
    }

    if (await destination.exists()) {
      throw StateError('Backup destination already exists.');
    }

    if (!await destination.parent.exists()) {
      throw StateError('Backup destination parent does not exist.');
    }

    final temporaryDirectory = await destination.parent.createTemp(
      '.sonus_backup_write_',
    );

    try {
      final temporaryFile = File(
        path.join(temporaryDirectory.path, 'candidate.zip'),
      );

      await ZipFileEncoder().zipDirectory(
        stagingDirectory,
        filename: temporaryFile.path,
        followLinks: false,
      );

      if (!await temporaryFile.exists() || await temporaryFile.length() == 0) {
        throw StateError('Backup archive creation failed.');
      }

      if (await destination.exists()) {
        throw StateError('Backup destination appeared during creation.');
      }

      await temporaryFile.rename(destination.path);

      return destination;
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }
}
