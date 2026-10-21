import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../artwork/application/services/owned_artwork_managed_storage.dart';
import '../../../artwork/data/services/file_system_artwork_managed_storage.dart';
import 'backup_archive_verifier.dart';
import 'restore_journal_store.dart';
import 'restore_planner.dart';

typedef OwnedArtworkStorageFactory =
    OwnedArtworkManagedStorage Function(String Function() fileIdGenerator);

class RestoredArtworkInstallation {
  RestoredArtworkInstallation({
    required Map<String, String> pathsByArtworkId,
    required this.installed,
    required this.reused,
  }) : pathsByArtworkId = Map.unmodifiable(pathsByArtworkId);

  /// Device-local path for every restored artwork identity.
  final Map<String, String> pathsByArtworkId;

  final int installed;
  final int reused;
}

/// Places restored artwork into this device's managed artwork storage.
///
/// Every new file name is reserved in the restore journal before the file
/// is created, so a crash at any point leaves files that recovery can find.
class RestoredArtworkInstaller {
  const RestoredArtworkInstaller({
    this.storageFactory = _defaultStorage,
    this.beforeInstall,
  });

  final OwnedArtworkStorageFactory storageFactory;

  /// Test seam invoked before each new file is installed.
  final Future<void> Function(ExtractedBackupArtwork artwork)? beforeInstall;

  static OwnedArtworkManagedStorage _defaultStorage(
    String Function() fileIdGenerator,
  ) => FileSystemArtworkManagedStorage(fileIdGenerator: fileIdGenerator);

  Future<RestoredArtworkInstallation> install({
    required List<ExtractedBackupArtwork> artwork,
    required Map<String, String> localPathsById,
    required RestoreJournal journal,
    required RestoreJournalStore journalStore,
  }) async {
    final paths = <String, String>{};
    var current = journal;
    var installed = 0;
    var reused = 0;

    for (final item in artwork) {
      final localPath = localPathsById[item.artworkId];

      if (localPath != null &&
          await RestorePlanner.isIdenticalLocalArtwork(
            localPath,
            byteLength: item.byteLength,
            sha256Digest: item.sha256Digest,
          )) {
        paths[item.artworkId] = localPath;
        reused++;
        continue;
      }

      final token = 'restore${current.sessionId}n$installed';

      current = current.reserve(token);
      await journalStore.write(current);

      await beforeInstall?.call(item);

      final import = await storageFactory(
        () => token,
      ).importOwnedArtwork(item.file.path);

      current = current.created(import.filePath);
      await journalStore.write(current);

      final installedFile = File(import.filePath);

      if (await installedFile.length() != item.byteLength ||
          (await sha256.bind(installedFile.openRead()).first).toString() !=
              item.sha256Digest) {
        throw FormatException(
          'Installed artwork failed verification: ${item.artworkId}',
        );
      }

      paths[item.artworkId] = import.filePath;
      installed++;
    }

    return RestoredArtworkInstallation(
      pathsByArtworkId: paths,
      installed: installed,
      reused: reused,
    );
  }
}
