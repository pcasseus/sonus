import 'dart:io';

import 'package:path/path.dart' as path;

import 'backup_archive_verifier.dart';
import 'backup_archive_writer.dart';

class VerifiedBackupPublisher {
  const VerifiedBackupPublisher({
    this.writer = const BackupArchiveWriter(),
    this.verifier = const BackupArchiveVerifier(),
  });

  final BackupArchiveWriter writer;
  final BackupArchiveVerifier verifier;

  Future<File> publish({
    required Directory stagingDirectory,
    required File destination,
  }) async {
    if (!destination.path.toLowerCase().endsWith('.sonusbackup')) {
      throw ArgumentError.value(
        destination.path,
        'destination',
        'Backup filename must end with .sonusbackup.',
      );
    }

    if (!await destination.parent.exists()) {
      throw StateError('Backup destination parent does not exist.');
    }

    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Backup destination already exists.');
    }

    final temporaryDirectory = await destination.parent.createTemp(
      '.sonus_verified_',
    );

    try {
      final candidate = File(
        path.join(temporaryDirectory.path, 'candidate.sonusbackup'),
      );

      await writer.write(
        stagingDirectory: stagingDirectory,
        destination: candidate,
      );

      await verifier.verify(candidate);

      // The candidate is already complete and independently verified.
      // Renaming within the same filesystem avoids copying partial
      // data into the final filename.
      //
      // TODO(SN-42): Replace this check-and-rename with platform-specific
      // atomic no-replace publication to eliminate concurrent overwrite.
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Backup destination appeared during verification.');
      }

      return await candidate.rename(destination.path);
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }
}
