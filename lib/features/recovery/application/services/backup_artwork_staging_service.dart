import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'backup_artwork_inventory_service.dart';

class BackupArtworkStagingService {
  const BackupArtworkStagingService();

  Future<void> stage({
    required List<BackupArtworkItem> inventory,
    required Directory stagingDirectory,
  }) async {
    if (await stagingDirectory.exists()) {
      throw StateError('Artwork staging directory must not exist.');
    }

    final seenPaths = <String>{};

    for (final item in inventory) {
      if (!RegExp(
        r'^artwork/[0-9a-f]{64}(\.[a-z0-9]{1,10})?$',
      ).hasMatch(item.archivePath)) {
        throw FormatException(
          'Invalid artwork archive path: ${item.artworkId}',
        );
      }

      if (!seenPaths.add(item.archivePath)) {
        throw FormatException('Duplicate artwork archive path.');
      }

      if (item.byteLength <= 0 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(item.sha256Digest)) {
        throw FormatException('Invalid artwork inventory metadata.');
      }
    }

    await stagingDirectory.create(recursive: true);

    try {
      for (final item in inventory) {
        final source = File(item.sourcePath);
        final destination = File(
          path.joinAll([stagingDirectory.path, ...item.archivePath.split('/')]),
        );

        await destination.parent.create(recursive: true);
        await destination.create(exclusive: true);

        final output = await destination.open(mode: FileMode.append);

        try {
          await for (final chunk in source.openRead()) {
            await output.writeFrom(chunk);
          }

          await output.flush();
        } finally {
          await output.close();
        }

        final copiedLength = await destination.length();
        final copiedDigest = await sha256.bind(destination.openRead()).first;

        if (copiedLength != item.byteLength ||
            copiedDigest.toString() != item.sha256Digest) {
          throw FormatException(
            'Artwork changed during backup: ${item.artworkId}',
          );
        }
      }
    } catch (_) {
      await stagingDirectory.delete(recursive: true);
      rethrow;
    }
  }
}
