import 'dart:math';

import '../../../sync/application/services/sync_mutation_context.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album_edition_disc_label.dart';
import '../../domain/entities/album_edition_track.dart';
import '../../domain/services/album_edition_track_order.dart';
import 'edition_track_numbering.dart';

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
    this.manualNumbersKept = 0,
  });

  final AlbumEditionTrack membership;
  final bool changed;
  final bool compatibilitySongChanged;

  /// Hand-set numbers that renumbering after a disc move left unchanged.
  final int manualNumbersKept;
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
          await context.localSyncRepository.recordUpsert(
            userId: normalizedUserId,
            entityType: CloudDataEntity.song,
            entityId: songId,
          );
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

      final movesDisc =
          shownDiscOf(membership) != (discNumber <= 0 ? 1 : discNumber);
      var manualNumbersKept = 0;
      final AlbumEditionTrack updatedMembership;
      final bool membershipChanged;

      if (movesDisc) {
        final moved = await _moveToEndOfDisc(
          context,
          memberships: memberships,
          membership: membership,
          discNumber: discNumber,
          userId: normalizedUserId,
          timestamp: timestamp,
        );
        updatedMembership = moved.membership;
        manualNumbersKept = moved.manualNumbersKept;
        membershipChanged = true;
      } else {
        membershipChanged =
            membership.discNumber != discNumber ||
            membership.trackNumber != trackNumber ||
            membership.numberingAuthority != AlbumEditionTrackAuthority.manual;

        updatedMembership = membershipChanged
            ? membership.copyWith(
                discNumber: discNumber,
                trackNumber: trackNumber,
                numberingAuthority: AlbumEditionTrackAuthority.manual,
                updatedAt: timestamp,
              )
            : membership;

        if (membershipChanged) {
          await context.albumEditionTrackRepository.save(updatedMembership);
          await context.localSyncRepository.recordUpsert(
            userId: normalizedUserId,
            entityType: CloudDataEntity.song,
            entityId: normalizedSongId,
          );
        }
      }

      final isCompatibilityEdition = song.albumEditionId == normalizedEditionId;

      final compatibilitySongChanged =
          isCompatibilityEdition &&
          (song.discNumber != updatedMembership.discNumber ||
              song.trackNumber != updatedMembership.trackNumber);

      if (compatibilitySongChanged) {
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
      }

      return AlbumEditionTrackPlacementResult(
        membership: updatedMembership,
        changed: membershipChanged || compatibilitySongChanged,
        compatibilitySongChanged: compatibilitySongChanged,
        manualNumbersKept: manualNumbersKept,
      );
    });
  }

  /// SN-50 A-Q9: a song moved to another disc goes to the end of that disc,
  /// and both discs are renumbered (inferred numbers only). The track
  /// number the caller asked for is not used.
  static Future<({AlbumEditionTrack membership, int manualNumbersKept})>
  _moveToEndOfDisc(
    SyncMutationContext context, {
    required List<AlbumEditionTrack> memberships,
    required AlbumEditionTrack membership,
    required int discNumber,
    required String? userId,
    required DateTime timestamp,
  }) async {
    final editionId = membership.albumEditionId;
    final songId = membership.songId;
    final destination = discNumber <= 0 ? 1 : discNumber;
    final others = editionTracksInShownOrder(
      memberships.where((m) => m.songId != songId),
    );

    int lastNumberOnDestination(Iterable<AlbumEditionTrack> listings) =>
        listings
            .where((m) => m.songId != songId && shownDiscOf(m) == destination)
            .fold(0, (last, m) => max(last, m.trackNumber));

    var moved = membership.copyWith(
      discNumber: discNumber,
      trackNumber: lastNumberOnDestination(others) + 1,
      numberingAuthority: AlbumEditionTrackAuthority.manual,
      updatedAt: timestamp,
    );
    await context.albumEditionTrackRepository.save(moved);
    await context.localSyncRepository.recordUpsert(
      userId: userId,
      entityType: CloudDataEntity.song,
      entityId: songId,
    );

    // A hand-ordered edition lists by position, so the song's position
    // moves too: after the destination disc's last song, or before the
    // first later disc when the destination disc is new.
    if (memberships.any(
      (m) => m.orderingAuthority == AlbumEditionTrackAuthority.manual,
    )) {
      var insertAt =
          others.lastIndexWhere((m) => shownDiscOf(m) == destination) + 1;
      if (insertAt == 0) {
        final later = others.indexWhere((m) => shownDiscOf(m) > destination);
        insertAt = later < 0 ? others.length : later;
      }
      final order = [...others]..insert(insertAt, moved);

      for (var index = 0; index < order.length; index++) {
        final listing = order[index];
        if (listing.sortPosition == index) continue;
        final repositioned = listing.copyWith(
          sortPosition: index,
          updatedAt: timestamp,
        );
        await context.albumEditionTrackRepository.save(repositioned);
        await context.localSyncRepository.recordUpsert(
          userId: userId,
          entityType: CloudDataEntity.song,
          entityId: listing.songId,
        );
        if (listing.songId == songId) moved = repositioned;
      }
    }

    final renumbering = await renumberEditionTracks(
      context,
      editionId: editionId,
      userId: userId,
      timestamp: timestamp,
      exclude: {songId},
    );

    // Last on its new disc, after any hand-set number already there.
    final after = await context.albumEditionTrackRepository.getByEditionId(
      editionId,
    );
    final numberedBefore = after
        .where(
          (m) =>
              m.songId != songId &&
              shownDiscOf(m) == destination &&
              m.trackNumber > 0,
        )
        .length;
    final finalNumber = max(numberedBefore, lastNumberOnDestination(after)) + 1;

    if (finalNumber != moved.trackNumber) {
      moved = moved.copyWith(trackNumber: finalNumber, updatedAt: timestamp);
      await context.albumEditionTrackRepository.save(moved);
    }

    return (
      membership: moved,
      manualNumbersKept: renumbering.manualNumbersKept,
    );
  }

  /// "Sort by disc & track": returns the edition to automatic order, by disc
  /// then track number, and clears any manual ordering so later renumbering
  /// moves tracks again. Track numbers are untouched. Running it on an edition
  /// already in automatic order changes nothing.
  Future<AlbumEditionReorderResult> sortByDiscAndTrack({
    required String albumEditionId,
    String? userId,
    DateTime? now,
  }) {
    final normalizedEditionId = albumEditionId.trim();

    if (normalizedEditionId.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition id must not be blank.',
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

      final memberships = [
        ...await context.albumEditionTrackRepository.getByEditionId(
          normalizedEditionId,
        ),
      ]..sort(compareByDiscAndTrack);

      var changed = false;
      final sorted = <AlbumEditionTrack>[];

      for (var index = 0; index < memberships.length; index++) {
        final membership = memberships[index];
        final membershipChanged =
            membership.sortPosition != index ||
            membership.orderingAuthority != AlbumEditionTrackAuthority.inferred;

        final updated = membershipChanged
            ? membership.copyWith(
                sortPosition: index,
                orderingAuthority: AlbumEditionTrackAuthority.inferred,
                updatedAt: timestamp,
              )
            : membership;

        if (membershipChanged) {
          await context.albumEditionTrackRepository.save(updated);
          await context.localSyncRepository.recordUpsert(
            userId: userId?.trim(),
            entityType: CloudDataEntity.song,
            entityId: updated.songId,
          );
          changed = true;
        }

        sorted.add(updated);
      }

      return AlbumEditionReorderResult(
        memberships: List<AlbumEditionTrack>.unmodifiable(sorted),
        changed: changed,
      );
    });
  }

  /// Arranges an edition as the listener laid it out in Release Studio
  /// (App Update 1.2, REF-13): [placements] lists every listing once, in
  /// the new order, each with the disc it is on.
  ///
  /// - The order is kept as given, and each song moves to its disc.
  /// - Each disc is numbered 1, 2, 3... in that order. These numbers are
  ///   automatic, so a later rearrangement renumbers them again.
  /// - A number set by hand is kept unless the listener agrees to change it
  ///   (SN-50 A-Q7A): it is counted in
  ///   [AlbumEditionArrangeResult.manualNumbersKept], and Release Studio
  ///   offers to renumber.
  /// - On a song's home edition, the song's own disc and number follow.
  /// - A disc left with no songs loses its name (REF-13c), so a new disc
  ///   with that number starts unnamed; other discs keep theirs.
  ///
  /// Every changed song is queued for sync, as any reorder is.
  Future<AlbumEditionArrangeResult> arrangeEdition({
    required String albumEditionId,
    required List<EditionPlacement> placements,
    String? userId,
    DateTime? now,
  }) {
    final editionId = albumEditionId.trim();
    if (editionId.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition id must not be blank.',
      );
    }
    final songIds = [for (final p in placements) p.songId.trim()];
    if (songIds.any((id) => id.isEmpty) ||
        songIds.toSet().length != songIds.length) {
      throw ArgumentError.value(
        placements,
        'placements',
        'Each listing must appear exactly once.',
      );
    }
    if (placements.any((p) => p.discNumber < 1)) {
      throw ArgumentError.value(
        placements,
        'placements',
        'Disc numbers start at 1.',
      );
    }

    final timestamp = now ?? DateTime.now();
    final normalizedUserId = userId?.trim();

    return mutationRunner.run((context) async {
      final edition = await context.albumEditionRepository.getById(editionId);
      if (edition == null) {
        throw StateError('Album edition not found: $editionId');
      }

      final memberships = {
        for (final m
            in await context.albumEditionTrackRepository.getByEditionId(
              editionId,
            ))
          m.songId: m,
      };
      if (memberships.length != songIds.length ||
          !memberships.keys.toSet().containsAll(songIds)) {
        throw StateError(
          'The arrangement must list exactly the songs of $editionId.',
        );
      }

      final nextByDisc = <int, int>{};
      final arranged = <AlbumEditionTrack>[];
      var changed = false;
      var manualNumbersKept = 0;

      for (final (index, placement) in placements.indexed) {
        final membership = memberships[songIds[index]]!;
        final disc = placement.discNumber;
        final target = nextByDisc.update(
          disc,
          (number) => number + 1,
          ifAbsent: () => 1,
        );
        final keepsManualNumber =
            membership.numberingAuthority ==
                AlbumEditionTrackAuthority.manual &&
            membership.trackNumber != target;
        if (keepsManualNumber) manualNumbersKept++;

        final updated = membership.copyWith(
          discNumber: disc,
          trackNumber: keepsManualNumber ? membership.trackNumber : target,
          sortPosition: index,
          orderingAuthority: AlbumEditionTrackAuthority.manual,
          updatedAt: timestamp,
        );
        final membershipChanged =
            updated.discNumber != membership.discNumber ||
            updated.trackNumber != membership.trackNumber ||
            updated.sortPosition != membership.sortPosition ||
            updated.orderingAuthority != membership.orderingAuthority;

        if (membershipChanged) {
          await context.albumEditionTrackRepository.save(updated);
          changed = true;
        }

        var songChanged = false;
        final song = await context.songRepository.getById(updated.songId);
        if (song != null &&
            song.albumEditionId == editionId &&
            (song.discNumber != updated.discNumber ||
                song.trackNumber != updated.trackNumber)) {
          await context.songRepository.save(
            song.copyWith(
              discNumber: updated.discNumber,
              trackNumber: updated.trackNumber,
              updatedAt: timestamp,
            ),
          );
          songChanged = true;
          changed = true;
        }

        if (membershipChanged || songChanged) {
          await context.localSyncRepository.recordUpsert(
            userId: normalizedUserId,
            entityType: CloudDataEntity.song,
            entityId: updated.songId,
          );
        }
        arranged.add(updated);
      }

      await context.albumEditionDiscLabelRepository?.keepOnly(
        editionId: editionId,
        discs: nextByDisc.keys.toSet(),
      );

      return AlbumEditionArrangeResult(
        memberships: List<AlbumEditionTrack>.unmodifiable(arranged),
        changed: changed,
        manualNumbersKept: manualNumbersKept,
      );
    });
  }

  /// Names [discNumber] of an edition, or clears its name when [label] is
  /// blank (REF-13c). The name stays with that disc number whatever songs
  /// move. Disc names are kept on this device and in its backups; they are
  /// not synced to the cloud yet.
  Future<void> setDiscLabel({
    required String albumEditionId,
    required int discNumber,
    required String? label,
    DateTime? now,
  }) {
    if (discNumber < 1) {
      throw ArgumentError.value(discNumber, 'discNumber', 'Discs start at 1.');
    }
    final timestamp = now ?? DateTime.now();
    final text = label?.trim() ?? '';

    return mutationRunner.run((context) async {
      final labels = context.albumEditionDiscLabelRepository;
      if (labels == null) {
        throw StateError('Disc names are not available here.');
      }
      if (text.isEmpty) {
        await labels.delete(editionId: albumEditionId, discNumber: discNumber);
        return;
      }
      final existing = await labels.getByEditionId(albumEditionId);
      final created = existing
          .where((l) => l.discNumber == discNumber)
          .firstOrNull
          ?.createdAt;
      await labels.save(
        AlbumEditionDiscLabel(
          albumEditionId: albumEditionId,
          discNumber: discNumber,
          label: text,
          createdAt: created ?? timestamp,
          updatedAt: timestamp,
        ),
      );
    });
  }
}

/// One listing's place in an arrangement: the song and its disc
/// ([AlbumEditionTrackOrderingService.arrangeEdition]).
class EditionPlacement {
  const EditionPlacement({required this.songId, required this.discNumber});

  final String songId;
  final int discNumber;
}

/// What arranging an edition did.
class AlbumEditionArrangeResult {
  const AlbumEditionArrangeResult({
    required this.memberships,
    required this.changed,
    required this.manualNumbersKept,
  });

  final List<AlbumEditionTrack> memberships;
  final bool changed;

  /// Hand-set numbers left as they were; renumbering them needs the
  /// listener's approval.
  final int manualNumbersKept;
}
