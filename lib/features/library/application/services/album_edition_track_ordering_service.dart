import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album_edition_track.dart';

class AlbumEditionReorderResult {
  const AlbumEditionReorderResult({
    required this.memberships,
    required this.changed,
  });

  final List<AlbumEditionTrack> memberships;
  final bool changed;
}

class AlbumEditionTrackPlacementResult {
  const AlbumEditionTrackPlacementResult({
    required this.membership,
    required this.changed,
    required this.compatibilitySongChanged,
  });

  final AlbumEditionTrack membership;
  final bool changed;
  final bool compatibilitySongChanged;
}

class AlbumEditionTrackOrderingService {
  const AlbumEditionTrackOrderingService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<AlbumEditionReorderResult> reorderEdition({
    required String albumEditionId,
    required List<String> orderedSongIds,
    String? userId,
    bool autoRenumber = false,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedEditionId = albumEditionId.trim();

    if (normalizedEditionId.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition id must not be blank.',
      );
    }

    final normalizedSongIds = <String>[];

    for (final songId in orderedSongIds) {
      final normalizedSongId = songId.trim();

      if (normalizedSongId.isEmpty) {
        throw ArgumentError.value(
          songId,
          'orderedSongIds',
          'Ordered song ids must not contain blank values.',
        );
      }

      normalizedSongIds.add(normalizedSongId);
    }

    if (normalizedSongIds.toSet().length != normalizedSongIds.length) {
      throw ArgumentError.value(
        orderedSongIds,
        'orderedSongIds',
        'Ordered song ids must not contain duplicates.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await context.albumEditionRepository.getById(
        normalizedEditionId,
      );

      if (edition == null) {
        throw StateError('Album edition not found: $normalizedEditionId');
      }

      final memberships = await context.albumEditionTrackRepository
          .getByEditionId(normalizedEditionId);

      final currentSongIds = memberships
          .map((membership) => membership.songId)
          .toSet();

      final requestedSongIds = normalizedSongIds.toSet();

      if (memberships.length != normalizedSongIds.length ||
          currentSongIds.length != requestedSongIds.length ||
          !currentSongIds.containsAll(requestedSongIds) ||
          !requestedSongIds.containsAll(currentSongIds)) {
        throw StateError(
          'Ordered song ids must exactly match the current edition '
          'membership for $normalizedEditionId.',
        );
      }

      final bySongId = <String, AlbumEditionTrack>{
        for (final membership in memberships) membership.songId: membership,
      };

      var changed = false;
      final reordered = <AlbumEditionTrack>[];
      final nextTrackNumberByDisc = <int, int>{};

      for (var index = 0; index < normalizedSongIds.length; index++) {
        final songId = normalizedSongIds[index];
        final membership = bySongId[songId]!;

        final targetTrackNumber = autoRenumber
            ? nextTrackNumberByDisc.update(
                membership.discNumber,
                (current) => current + 1,
                ifAbsent: () => 1,
              )
            : membership.trackNumber;

        final targetNumberingAuthority = autoRenumber
            ? AlbumEditionTrackAuthority.manual
            : membership.numberingAuthority;

        final membershipChanged =
            membership.sortPosition != index ||
            membership.orderingAuthority != AlbumEditionTrackAuthority.manual ||
            membership.trackNumber != targetTrackNumber ||
            membership.numberingAuthority != targetNumberingAuthority;

        final updatedMembership = membershipChanged
            ? membership.copyWith(
                trackNumber: targetTrackNumber,
                sortPosition: index,
                numberingAuthority: targetNumberingAuthority,
                orderingAuthority: AlbumEditionTrackAuthority.manual,
                updatedAt: timestamp,
              )
            : membership;

        if (membershipChanged) {
          await context.albumEditionTrackRepository.save(updatedMembership);
          changed = true;
        }

        if (autoRenumber) {
          final song = await context.songRepository.getById(songId);

          if (song == null) {
            throw StateError('Song not found: $songId');
          }

          if (song.albumId != edition.albumId) {
            throw StateError(
              'Song $songId does not belong to album ${edition.albumId}.',
            );
          }

          final isCompatibilityEdition =
              song.albumEditionId == normalizedEditionId;

          final compatibilityPlacementChanged =
              isCompatibilityEdition &&
              (song.discNumber != updatedMembership.discNumber ||
                  song.trackNumber != updatedMembership.trackNumber);

          if (compatibilityPlacementChanged) {
            final updatedSong = song.copyWith(
              discNumber: updatedMembership.discNumber,
              trackNumber: updatedMembership.trackNumber,
              updatedAt: timestamp,
            );

            await context.songRepository.save(updatedSong);

            await context.localSyncRepository.recordUpsert(
              userId: normalizedUserId,
              entityType: CloudDataEntity.song,
              entityId: updatedSong.id,
            );

            changed = true;
          }
        }

        reordered.add(updatedMembership);
      }

      return AlbumEditionReorderResult(
        memberships: List<AlbumEditionTrack>.unmodifiable(reordered),
        changed: changed,
      );
    });
  }

  Future<AlbumEditionTrackPlacementResult> updateTrackPlacement({
    required String? userId,
    required String albumEditionId,
    required String songId,
    required int discNumber,
    required int trackNumber,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedEditionId = albumEditionId.trim();
    final normalizedSongId = songId.trim();

    if (normalizedEditionId.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition id must not be blank.',
      );
    }

    if (normalizedSongId.isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Song id must not be blank.');
    }

    if (discNumber < 0) {
      throw ArgumentError.value(
        discNumber,
        'discNumber',
        'Disc number must not be negative.',
      );
    }

    if (trackNumber < 0) {
      throw ArgumentError.value(
        trackNumber,
        'trackNumber',
        'Track number must not be negative.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await context.albumEditionRepository.getById(
        normalizedEditionId,
      );

      if (edition == null) {
        throw StateError('Album edition not found: $normalizedEditionId');
      }

      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      if (song.albumId != edition.albumId) {
        throw StateError(
          'Song $normalizedSongId does not belong to album '
          '${edition.albumId}.',
        );
      }

      final memberships = await context.albumEditionTrackRepository
          .getByEditionId(normalizedEditionId);

      AlbumEditionTrack? membership;

      for (final candidate in memberships) {
        if (candidate.songId == normalizedSongId) {
          membership = candidate;
          break;
        }
      }

      if (membership == null) {
        throw StateError(
          'Song $normalizedSongId is not a member of album edition '
          '$normalizedEditionId.',
        );
      }

      final membershipChanged =
          membership.discNumber != discNumber ||
          membership.trackNumber != trackNumber ||
          membership.numberingAuthority != AlbumEditionTrackAuthority.manual;

      final updatedMembership = membershipChanged
          ? membership.copyWith(
              discNumber: discNumber,
              trackNumber: trackNumber,
              numberingAuthority: AlbumEditionTrackAuthority.manual,
              updatedAt: timestamp,
            )
          : membership;

      if (membershipChanged) {
        await context.albumEditionTrackRepository.save(updatedMembership);
      }

      final isCompatibilityEdition = song.albumEditionId == normalizedEditionId;

      final compatibilitySongChanged =
          isCompatibilityEdition &&
          (song.discNumber != discNumber || song.trackNumber != trackNumber);

      if (compatibilitySongChanged) {
        final updatedSong = song.copyWith(
          discNumber: discNumber,
          trackNumber: trackNumber,
          updatedAt: timestamp,
        );

        await context.songRepository.save(updatedSong);

        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.song,
          entityId: updatedSong.id,
        );
      }

      return AlbumEditionTrackPlacementResult(
        membership: updatedMembership,
        changed: membershipChanged || compatibilitySongChanged,
        compatibilitySongChanged: compatibilitySongChanged,
      );
    });
  }
}
