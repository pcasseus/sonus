import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/media_file_binding.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/repositories/media_file_binding_repository.dart';
import '../../domain/services/audio_metadata_reader.dart';

class ImportDurationRepairSummary {
  const ImportDurationRepairSummary({
    required this.examined,
    required this.repaired,
    required this.skipped,
    required this.failed,
  });

  final int examined;
  final int repaired;
  final int skipped;
  final int failed;
}

class ImportDurationRepairService {
  const ImportDurationRepairService({
    required this.mediaFileBindingRepository,
    required this.metadataReader,
    required this.mutationRunner,
  });

  final MediaFileBindingRepository mediaFileBindingRepository;
  final AudioMetadataReader metadataReader;
  final SyncMutationRunner mutationRunner;

  Future<ImportDurationRepairSummary> repair({
    required String? userId,
    DateTime? now,
  }) async {
    final normalizedUserId = userId?.trim();
    final timestamp = now ?? DateTime.now();

    final candidateSongIds = await mutationRunner.run((context) async {
      final songs = await context.songRepository.getAll();

      return [
        for (final song in songs)
          if (song.durationSeconds <= 0) song.id,
      ];
    });

    var examined = 0;
    var repaired = 0;
    var skipped = 0;
    var failed = 0;

    for (final songId in candidateSongIds) {
      examined++;

      try {
        final bindings = await mediaFileBindingRepository.getBySongId(songId);
        final binding = _preferredAvailableBinding(bindings);

        if (binding == null) {
          skipped++;
          continue;
        }

        final metadata = await metadataReader.read(
          ImportCandidate(
            filePath: binding.filePath,
            normalizedPath: binding.normalizedPath,
            discoveredAt: timestamp,
            sourceId: binding.sourceId,
          ),
        );

        if (metadata.durationSeconds <= 0) {
          skipped++;
          continue;
        }

        final changed = await mutationRunner.run((context) async {
          final song = await context.songRepository.getById(songId);

          if (song == null || song.durationSeconds > 0) {
            return false;
          }

          final updated = song.copyWith(
            durationSeconds: metadata.durationSeconds,
            updatedAt: timestamp,
          );

          await context.songRepository.save(updated);

          if (normalizedUserId != null && normalizedUserId.isNotEmpty) {
            await context.localSyncRepository.recordUpsert(
              userId: normalizedUserId,
              entityType: CloudDataEntity.song,
              entityId: updated.id,
            );
          }

          return true;
        });

        if (changed) {
          repaired++;
        } else {
          skipped++;
        }
      } on LibraryMutationUnavailable {
        // A restore refused the write: stop the pass instead of reading
        // more files whose repairs would be refused as well.
        rethrow;
      } catch (_) {
        // One unreadable file must not stop the others; the caller reports
        // the failed count.
        failed++;
      }
    }

    return ImportDurationRepairSummary(
      examined: examined,
      repaired: repaired,
      skipped: skipped,
      failed: failed,
    );
  }

  MediaFileBinding? _preferredAvailableBinding(
    List<MediaFileBinding> bindings,
  ) {
    for (final binding in bindings) {
      if (binding.isAvailable && binding.filePath.trim().isNotEmpty) {
        return binding;
      }
    }

    return null;
  }
}
