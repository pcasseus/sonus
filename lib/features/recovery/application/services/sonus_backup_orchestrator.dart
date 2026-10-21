import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'backup_artwork_inventory_service.dart';
import 'backup_artwork_staging_service.dart';
import 'backup_integrity_codec.dart';
import 'sqlite_backup_exporter.dart';
import 'verified_backup_publisher.dart';

class SonusBackupOrchestrator {
  const SonusBackupOrchestrator({
    required this.exporter,
    this.artworkInventory = const BackupArtworkInventoryService(),
    this.artworkStaging = const BackupArtworkStagingService(),
    this.integrityCodec = const BackupIntegrityCodec(),
    this.publisher = const VerifiedBackupPublisher(),
  });

  final SqliteBackupExporter exporter;
  final BackupArtworkInventoryService artworkInventory;
  final BackupArtworkStagingService artworkStaging;
  final BackupIntegrityCodec integrityCodec;
  final VerifiedBackupPublisher publisher;

  Future<File> createBackup({required File destination}) async {
    if (!await destination.parent.exists()) {
      throw StateError('Backup destination parent does not exist.');
    }

    final temporaryRoot = await destination.parent.createTemp(
      '.sonus_backup_stage_',
    );

    try {
      // Export a validated SQLite snapshot.
      final exported = await exporter.export();

      // Collect all artwork associated with the exported database.
      final inventory = await artworkInventory.build(exported.payload);

      // The artwork staging service requires a nonexistent directory.
      final stagingDirectory = Directory(
        path.join(temporaryRoot.path, 'staging'),
      );

      await artworkStaging.stage(
        inventory: inventory,
        stagingDirectory: stagingDirectory,
      );

      // Serialize only portable artwork metadata.
      final manifestDocument = jsonEncode({
        'manifest': exported.manifest.toJson(),
        'artwork': [for (final item in inventory) item.toPortableJson()],
      });

      final libraryDocument = integrityCodec.encode(
        manifest: exported.manifest,
        payload: exported.payload,
      );

      await File(
        path.join(stagingDirectory.path, 'manifest.json'),
      ).writeAsString(manifestDocument, flush: true);

      await File(
        path.join(stagingDirectory.path, 'library.json'),
      ).writeAsString(libraryDocument, flush: true);

      // Package, independently verify, and publish.
      return await publisher.publish(
        stagingDirectory: stagingDirectory,
        destination: destination,
      );
    } finally {
      if (await temporaryRoot.exists()) {
        await temporaryRoot.delete(recursive: true);
      }
    }
  }
}
