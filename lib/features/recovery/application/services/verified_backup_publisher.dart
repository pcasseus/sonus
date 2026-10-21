import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/backup_failure.dart';
import 'backup_archive_verifier.dart';
import 'backup_archive_writer.dart';
import 'backup_publication.dart';

class VerifiedBackupPublisher {
  const VerifiedBackupPublisher({
    this.writer = const BackupArchiveWriter(),
    this.verifier = const BackupArchiveVerifier(),
    this.publication = const PlatformBackupPublication(),
  });

  final BackupArchiveWriter writer;
  final BackupArchiveVerifier verifier;
  final BackupPublication publication;

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

    // Fail early; the publication step remains the authoritative check.
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw BackupDestinationExistsError();
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

      // The candidate is complete and independently verified. Publication
      // either exposes it atomically under the final name or fails without
      // touching an existing destination.
      await publication.publishNoReplace(
        source: candidate,
        destination: destination,
      );

      return destination;
    } finally {
      // Removes the candidate (or its extra hard link) and any partial data.
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }
}
