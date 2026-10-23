import '../../../../core/database/app_database.dart';
import '../../data/daos/import_source_dao.dart';
import '../../data/daos/media_file_binding_dao.dart';
import '../../data/repositories/sqlite_import_source_repository.dart';
import '../../data/repositories/sqlite_media_file_binding_repository.dart';

/// Reconciles the database portion of a completed source scan atomically.
class ImportSourceReconciliationService {
  const ImportSourceReconciliationService({required this.appDatabase});

  final AppDatabase appDatabase;

  /// [seenPaths] is the file snapshot taken at [discoveredAt]; [scannedAt]
  /// is when the scan completed.
  Future<void> reconcile({
    required String sourceId,
    required Set<String> seenPaths,
    required DateTime discoveredAt,
    required DateTime scannedAt,
    Future<void> Function(Set<String>)? onSongsBecameUnavailable,
  }) async {
    final unavailable = await appDatabase.transaction((transaction) async {
      final sources = SqliteImportSourceRepository(
        ImportSourceDao(transaction),
      );
      final bindings = SqliteMediaFileBindingRepository(
        MediaFileBindingDao(transaction),
      );

      final currentSource = await sources.getById(sourceId);
      if (currentSource == null) {
        throw StateError('Import source not found: $sourceId');
      }

      final previousScan = currentSource.lastScannedAt;
      if (previousScan != null && previousScan.isAfter(scannedAt)) {
        return <String>{};
      }

      // Read fresh rows inside the transaction, not a snapshot captured
      // before admission. This preserves concurrent import changes.
      final currentBindings = await bindings.getBySourceId(sourceId);
      final affectedSongIds = <String>{};

      for (final binding in currentBindings) {
        if (!binding.isAvailable ||
            seenPaths.contains(binding.normalizedPath)) {
          continue;
        }

        // Created or refreshed after this scan's file snapshot, for example
        // by an overlapping newer scan. The snapshot cannot speak for it.
        if (binding.updatedAt.isAfter(discoveredAt)) {
          continue;
        }

        await bindings.save(
          binding.copyWith(isAvailable: false, updatedAt: scannedAt),
        );
        affectedSongIds.add(binding.songId);
      }

      await sources.save(
        currentSource.copyWith(lastScannedAt: scannedAt, updatedAt: scannedAt),
      );

      final unavailableSongIds = <String>{};

      for (final songId in affectedSongIds) {
        final songBindings = await bindings.getBySongId(songId);
        final usable = songBindings.any(
          (binding) =>
              binding.isAvailable && binding.filePath.trim().isNotEmpty,
        );

        if (!usable) {
          unavailableSongIds.add(songId);
        }
      }

      return unavailableSongIds;
    });

    // Database admission has ended before any playback operation.
    if (unavailable.isNotEmpty && onSongsBecameUnavailable != null) {
      await onSongsBecameUnavailable(Set<String>.unmodifiable(unavailable));
    }
  }
}
