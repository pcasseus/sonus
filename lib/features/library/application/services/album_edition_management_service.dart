import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/repositories/cloud_revision_baseline_repository.dart';
import '../../../sync/application/services/sync_mutation_context.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/album_edition_track.dart';
import '../../domain/entities/entity_factory.dart';
import '../../domain/entities/song.dart';
import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/metadata/metadata_fields.dart';
import '../../domain/repositories/album_edition_repository.dart';
import '../../domain/repositories/album_edition_track_repository.dart';
import '../../domain/services/metadata_field_state_service.dart';
import 'edition_track_numbering.dart';

/// Why an edition operation was refused. Nothing is changed when one is.
enum AlbumEditionRefusal {
  albumNotFound,
  editionNotFound,
  blankTitle,
  duplicateTitle,
  songNotOnAlbum,

  /// Every song stays on at least one edition of its album.
  lastEditionOfSong,

  /// Deleting an edition: songs no other edition lists block it
  /// ([AlbumEditionManagementException.songCount] says how many); the
  /// primary edition needs a replacement, and cannot go once it is in the
  /// cloud; an album's only edition never goes.
  exclusiveSongs,
  primaryEdition,
  primaryInCloud,
  onlyEdition,
}

/// What "Choose songs" changed on an edition
/// ([AlbumEditionManagementService.updateTrackList]).
class AlbumEditionTrackListResult {
  const AlbumEditionTrackListResult({
    required this.added,
    required this.removed,
    required this.keptAsLastListing,
    required this.renumbering,
  });

  final int added;
  final int removed;

  /// Songs asked to be removed that are on no other edition, so they stay.
  final int keptAsLastListing;

  final EditionRenumberResult renumbering;
}

class AlbumEditionManagementException implements Exception {
  const AlbumEditionManagementException(this.refusal, {this.songCount = 0});

  final AlbumEditionRefusal refusal;

  /// For [AlbumEditionRefusal.exclusiveSongs]: the songs to move first.
  final int songCount;

  @override
  String toString() => 'AlbumEditionManagementException(${refusal.name})';
}

/// Album Studio's edition operations: create, rename or retype, choose the
/// primary edition, assign and remove tracks, and delete editions.
///
/// Each operation is one transaction and either completes or changes
/// nothing. Songs, their recordings and listening history are never
/// deleted: removing a track only removes that edition's listing of it.
///
/// Cross-device: edition records sync, but track listings travel only with
/// the song they belong to (as with J2), and other devices keep an edition
/// deleted here until edition deletion is supported on receipt.
class AlbumEditionManagementService {
  const AlbumEditionManagementService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  /// Creates an edition of the album.
  ///
  /// With [includeSongsFrom] (for example the Standard edition, when
  /// creating Deluxe), the new edition starts with every song that edition
  /// lists, in the same order and with the same disc and track numbers.
  /// These are the same songs, not copies: their IDs, listening history
  /// and playlist entries are unchanged. Everything happens in one
  /// transaction.
  ///
  /// The source's release date, artwork and genre are never copied (SN-50
  /// A-Q5D/E): a new edition starts with no date or cover of its own, and
  /// genre is a release-wide setting.
  Future<AlbumEdition> createEdition({
    required String albumId,
    required String title,
    required AlbumEditionType type,
    String? includeSongsFrom,
    DateTime? releaseDate,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final album = await context.albumRepository.getById(albumId.trim());

      if (album == null) {
        throw const AlbumEditionManagementException(
          AlbumEditionRefusal.albumNotFound,
        );
      }

      final editions = await context.albumEditionRepository.getByAlbumId(
        album.id,
      );
      final cleanTitle = _validTitle(title, editions);

      final edition = EntityFactory.createAlbumEdition(
        albumId: album.id,
        title: cleanTitle,
        type: type,
        // An album's first edition is its primary one.
        isPrimary: editions.isEmpty,
        releaseDate: releaseDate,
        now: timestamp,
      );

      await context.albumEditionRepository.create(edition);
      await _recordEdition(context, userId, edition.id);

      final sourceId = includeSongsFrom?.trim();

      if (sourceId != null && sourceId.isNotEmpty) {
        final source = await _edition(context, sourceId);

        if (source.albumId != album.id) {
          throw const AlbumEditionManagementException(
            AlbumEditionRefusal.editionNotFound,
          );
        }

        final memberships = await context.albumEditionTrackRepository
            .getByEditionId(source.id);

        for (final membership in memberships) {
          await context.albumEditionTrackRepository.create(
            AlbumEditionTrack(
              albumEditionId: edition.id,
              songId: membership.songId,
              discNumber: membership.discNumber,
              trackNumber: membership.trackNumber,
              sortPosition: membership.sortPosition,
              numberingAuthority: membership.numberingAuthority,
              orderingAuthority: membership.orderingAuthority,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
          await _recordSong(context, userId, membership.songId);
        }
      }

      return edition;
    });
  }

  /// Renames and/or retypes an edition.
  Future<AlbumEdition> updateEdition({
    required String editionId,
    String? title,
    AlbumEditionType? type,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
      final siblings = (await context.albumEditionRepository.getByAlbumId(
        edition.albumId,
      )).where((other) => other.id != edition.id).toList(growable: false);

      final updated = edition.copyWith(
        title: title == null ? null : _validTitle(title, siblings),
        type: type,
        updatedAt: timestamp,
      );

      if (updated.title == edition.title && updated.type == edition.type) {
        return edition;
      }

      await context.albumEditionRepository.save(updated);
      await _recordEdition(context, userId, updated.id);

      // The user's own name and type are never replaced by a later lookup.
      final metadataRepository = context.metadataFieldStateRepository;
      if (metadataRepository != null) {
        await MetadataFieldStateService(
          repository: metadataRepository,
        ).recordAll(
          entityType: MetadataEntityType.albumEdition,
          entityId: updated.id,
          fieldNames: {
            if (updated.title != edition.title) MetadataFields.editionTitle,
            if (updated.type != edition.type) MetadataFields.editionType,
          },
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: timestamp,
        );
      }

      return updated;
    });
  }

  /// Makes [editionId] the album's only primary edition.
  Future<void> setPrimary({
    required String editionId,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final target = await _edition(context, editionId);
      final editions = await context.albumEditionRepository.getByAlbumId(
        target.albumId,
      );

      await _makePrimary(context, editions, target.id, userId, timestamp);
    });
  }

  static Future<void> _makePrimary(
    SyncMutationContext context,
    List<AlbumEdition> editions,
    String primaryId,
    String? userId,
    DateTime timestamp,
  ) async {
    for (final edition in editions) {
      final shouldBePrimary = edition.id == primaryId;

      if (edition.isPrimary != shouldBePrimary) {
        await context.albumEditionRepository.save(
          edition.copyWith(isPrimary: shouldBePrimary, updatedAt: timestamp),
        );
        await _recordEdition(context, userId, edition.id);
      }
    }
  }

  /// Lists [songIds] on the edition. A song already listed is left as it
  /// is; a song listed on another edition starts with its disc and track
  /// number there and is listed after the edition's other songs. Returns
  /// how many songs were added.
  ///
  /// With [renumber] (the default), the edition's inferred track numbers
  /// are then made consecutive on each disc (see [renumberEdition]).
  Future<int> assignTracks({
    required String editionId,
    required List<String> songIds,
    bool renumber = true,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
      final added = await _assign(context, edition, songIds, userId, timestamp);

      if (renumber && added > 0) {
        await renumberEditionTracks(
          context,
          editionId: edition.id,
          userId: userId,
          timestamp: timestamp,
        );
      }

      return added;
    });
  }

  /// Removes the edition's listing of [songId]. The song stays in the
  /// library. If this was the song's home edition, its home moves to
  /// another edition that lists it, preferring the primary one. The
  /// edition's other inferred track numbers are then made consecutive on
  /// each disc; hand-set numbers are only counted.
  Future<EditionRenumberResult> removeTrack({
    required String editionId,
    required String songId,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);

      if (!await _remove(context, edition, songId, userId, timestamp)) {
        return EditionRenumberResult.none;
      }

      return renumberEditionTracks(
        context,
        editionId: edition.id,
        userId: userId,
        timestamp: timestamp,
      );
    });
  }

  /// "Choose songs": adds [add] and removes [remove] in one transaction,
  /// then renumbers the edition once, never overwriting hand-set numbers.
  /// A song in [remove] that is on no other edition is kept and counted
  /// rather than refusing the whole change.
  Future<AlbumEditionTrackListResult> updateTrackList({
    required String editionId,
    List<String> add = const [],
    List<String> remove = const [],
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
      final added = add.isEmpty
          ? 0
          : await _assign(context, edition, add, userId, timestamp);
      var removed = 0;
      var kept = 0;

      for (final songId in remove.map((id) => id.trim()).toSet()) {
        try {
          if (await _remove(context, edition, songId, userId, timestamp)) {
            removed++;
          }
        } on AlbumEditionManagementException catch (error) {
          // Refused before anything was written for this song.
          if (error.refusal != AlbumEditionRefusal.lastEditionOfSong) rethrow;
          kept++;
        }
      }

      final renumbering = added + removed == 0
          ? EditionRenumberResult.none
          : await renumberEditionTracks(
              context,
              editionId: edition.id,
              userId: userId,
              timestamp: timestamp,
            );

      return AlbumEditionTrackListResult(
        added: added,
        removed: removed,
        keptAsLastListing: kept,
        renumbering: renumbering,
      );
    });
  }

  /// Numbers the edition's tracks 1, 2, 3… on each disc, in the order they
  /// are shown (SN-50 A3). Numbers set by hand change only with
  /// [overwriteManual], which the user must have approved (A-Q7A).
  Future<EditionRenumberResult> renumberEdition({
    required String editionId,
    bool overwriteManual = false,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);

      return renumberEditionTracks(
        context,
        editionId: edition.id,
        userId: userId,
        timestamp: timestamp,
        overwriteManual: overwriteManual,
      );
    });
  }

  static Future<int> _assign(
    SyncMutationContext context,
    AlbumEdition edition,
    List<String> songIds,
    String? userId,
    DateTime timestamp,
  ) async {
    final memberships = await context.albumEditionTrackRepository
        .getByEditionId(edition.id);
    final listed = {for (final m in memberships) m.songId};
    var nextPosition = memberships.isEmpty
        ? 0
        : memberships
                  .map((m) => m.sortPosition)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    var added = 0;

    for (final songId in songIds.map((id) => id.trim()).toSet()) {
      final song = await _songOnAlbum(context, songId, edition.albumId);

      if (listed.contains(song.id)) {
        continue;
      }

      final elsewhere = await context.albumEditionTrackRepository.getBySongId(
        song.id,
      );
      final placement = elsewhere.isEmpty ? null : elsewhere.first;

      await context.albumEditionTrackRepository.create(
        AlbumEditionTrack(
          albumEditionId: edition.id,
          songId: song.id,
          discNumber: placement?.discNumber ?? song.discNumber,
          trackNumber: placement?.trackNumber ?? song.trackNumber,
          sortPosition: nextPosition++,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await _recordSong(context, userId, song.id);
      added++;
    }

    return added;
  }

  /// Removes [edition]'s listing of [songId] inside [context]'s
  /// transaction, as [removeTrack] does but without renumbering: for
  /// deleting a disc in Release Studio (PATCH-02), which numbers the discs
  /// itself. The song stays in the library; its home moves when needed.
  /// Refused ([AlbumEditionRefusal.lastEditionOfSong]) for a song listed
  /// on no other edition.
  static Future<bool> removeListing(
    SyncMutationContext context,
    AlbumEdition edition,
    String songId,
    String? userId,
    DateTime timestamp,
  ) => _remove(context, edition, songId, userId, timestamp);

  /// Removes one listing; false when the edition does not list the song.
  static Future<bool> _remove(
    SyncMutationContext context,
    AlbumEdition edition,
    String songId,
    String? userId,
    DateTime timestamp,
  ) async {
    final song = await _songOnAlbum(context, songId, edition.albumId);
    final memberships = await context.albumEditionTrackRepository.getBySongId(
      song.id,
    );
    final others = memberships
        .where((m) => m.albumEditionId != edition.id)
        .toList(growable: false);

    if (others.isEmpty) {
      throw const AlbumEditionManagementException(
        AlbumEditionRefusal.lastEditionOfSong,
      );
    }

    if (others.length == memberships.length) {
      return false;
    }

    if (song.albumEditionId == edition.id) {
      await _rehome(context, song, others, userId, timestamp);
    }

    await context.albumEditionTrackRepository.delete(
      editionId: edition.id,
      songId: song.id,
    );
    await _recordSong(context, userId, song.id);
    return true;
  }

  /// Moves the song's home to one of [others], its listings on other
  /// editions, preferring the primary edition.
  static Future<void> _rehome(
    SyncMutationContext context,
    Song song,
    List<AlbumEditionTrack> others,
    String? userId,
    DateTime timestamp,
  ) async {
    final editions = await context.albumEditionRepository.getByAlbumId(
      song.albumId,
    );
    final primaryId = editions
        .where((e) => e.isPrimary)
        .map((e) => e.id)
        .firstOrNull;
    final newHome = others.firstWhere(
      (m) => m.albumEditionId == primaryId,
      orElse: () => others.first,
    );

    await context.songRepository.save(
      song.copyWith(
        albumEditionId: newHome.albumEditionId,
        discNumber: newHome.discNumber,
        trackNumber: newHome.trackNumber,
        updatedAt: timestamp,
      ),
    );
    await _recordSong(context, userId, song.id);
  }

  /// Whether the edition has reached [userId]'s cloud. Without a way to
  /// tell, it is treated as there.
  ///
  /// Signed out, it counts as there when any account on this device has a
  /// baseline for it (SN-50 A-Q16): the delete would otherwise reach no
  /// cloud, and that account's other devices would keep it as primary.
  static Future<bool> _inCloud(
    SyncMutationContext context,
    String? userId,
    String editionId,
  ) async {
    final owner = userId?.trim();
    final baselines = context.cloudRevisionBaselineRepository;
    if (owner == null || owner.isEmpty) {
      if (baselines is! CloudBaselinePresence) return false;
      return (baselines as CloudBaselinePresence).hasAnyRevision(
        entityType: CloudDataEntity.albumEdition,
        entityId: editionId,
      );
    }
    if (baselines == null) return true;
    return await baselines.getRevision(
          userId: owner,
          entityType: CloudDataEntity.albumEdition,
          entityId: editionId,
        ) !=
        null;
  }

  /// Queues every song listed on an edition other than its home edition
  /// for the next sync, in one transaction, and returns how many (SN-50
  /// BLOCKED #4, decided 2026-10-31).
  ///
  /// Placements travel with the song's cloud record. Ones edited before
  /// Track Studio queued them were never sent, so an inbound copy could
  /// put the old placement back; re-sending makes the cloud match this
  /// device. Only the outbox changes: no song, listing or number is
  /// written. The user starts it; it never runs by itself.
  Future<int> resendPlacements({required String userId}) async {
    final owner = userId.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    return mutationRunner.run((context) async {
      final listings = context.albumEditionTrackRepository;
      if (listings is! AwayFromHomeListings) {
        throw StateError('Placement re-send is not available here.');
      }

      final songIds = await (listings as AwayFromHomeListings)
          .songIdsListedAwayFromHome();
      for (final songId in songIds) {
        await context.localSyncRepository.recordUpsert(
          userId: owner,
          entityType: CloudDataEntity.song,
          entityId: songId,
        );
      }
      return songIds.length;
    });
  }

  /// Deletes an edition (SN-50 A5), never the album's last one (A-Q24).
  ///
  /// The primary edition goes only with [replacementPrimaryId], which
  /// becomes primary in the same transaction (A-Q23). Songs no other
  /// edition lists block the delete until they are added to one (A-Q15,
  /// A-Q25, A-Q26). Other listings go with the edition; a song whose home
  /// it was moves to another edition that lists it, preferring the primary.
  ///
  /// A primary edition already in the cloud is refused: other devices keep
  /// a deleted edition (A-Q16), so they would end up with two primaries.
  Future<void> deleteEdition({
    required String editionId,
    String? replacementPrimaryId,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
      final repository = context.albumEditionRepository;
      final editions = await repository.getByAlbumId(edition.albumId);

      if (editions.length <= 1) {
        throw const AlbumEditionManagementException(
          AlbumEditionRefusal.onlyEdition,
        );
      }

      if (edition.isPrimary) {
        final replacementId = replacementPrimaryId?.trim();
        if (!editions.any((e) => e.id == replacementId && e.id != edition.id)) {
          throw const AlbumEditionManagementException(
            AlbumEditionRefusal.primaryEdition,
          );
        }
        if (await _inCloud(context, userId, edition.id)) {
          throw const AlbumEditionManagementException(
            AlbumEditionRefusal.primaryInCloud,
          );
        }
      }

      final tracks = context.albumEditionTrackRepository;
      final memberships = await tracks.getByEditionId(edition.id);
      final listed = {for (final m in memberships) m.songId};
      final homedOnly = [
        for (final song in await context.songRepository.getByEditionId(
          edition.id,
        ))
          if (!listed.contains(song.id)) song,
      ];
      final elsewhere = <String, List<AlbumEditionTrack>>{
        for (final songId in {...listed, for (final s in homedOnly) s.id})
          songId: [
            for (final m in await tracks.getBySongId(songId))
              if (m.albumEditionId != edition.id) m,
          ],
      };
      final exclusive = elsewhere.values.where((m) => m.isEmpty).length;

      if (exclusive > 0) {
        throw AlbumEditionManagementException(
          AlbumEditionRefusal.exclusiveSongs,
          songCount: exclusive,
        );
      }

      if (repository is! AlbumEditionDeletionRepository) {
        throw StateError('Edition deletion is not available here.');
      }

      if (edition.isPrimary) {
        await _makePrimary(
          context,
          editions,
          replacementPrimaryId!.trim(),
          userId,
          timestamp,
        );
      }
      for (final songId in listed) {
        await _remove(context, edition, songId, userId, timestamp);
      }
      for (final song in homedOnly) {
        await _rehome(context, song, elsewhere[song.id]!, userId, timestamp);
      }

      await (repository as AlbumEditionDeletionRepository).delete(edition.id);
      await context.localSyncRepository.recordDelete(
        userId: userId?.trim(),
        entityType: CloudDataEntity.albumEdition,
        entityId: edition.id,
      );
    });
  }

  static String _validTitle(String title, List<AlbumEdition> others) {
    final clean = title.trim();

    if (clean.isEmpty) {
      throw const AlbumEditionManagementException(
        AlbumEditionRefusal.blankTitle,
      );
    }

    final canonical = TextNormalizer.canonicalize(clean);

    if (others.any((e) => TextNormalizer.canonicalize(e.title) == canonical)) {
      throw const AlbumEditionManagementException(
        AlbumEditionRefusal.duplicateTitle,
      );
    }

    return clean;
  }

  static Future<AlbumEdition> _edition(
    SyncMutationContext context,
    String editionId,
  ) async {
    final edition = await context.albumEditionRepository.getById(
      editionId.trim(),
    );

    if (edition == null) {
      throw const AlbumEditionManagementException(
        AlbumEditionRefusal.editionNotFound,
      );
    }

    return edition;
  }

  static Future<Song> _songOnAlbum(
    SyncMutationContext context,
    String songId,
    String albumId,
  ) async {
    final song = await context.songRepository.getById(songId.trim());

    if (song == null || song.albumId != albumId) {
      throw const AlbumEditionManagementException(
        AlbumEditionRefusal.songNotOnAlbum,
      );
    }

    return song;
  }

  /// A song's edition listings travel with the song to the cloud, so any
  /// change to them queues the song.
  static Future<void> _recordSong(
    SyncMutationContext context,
    String? userId,
    String songId,
  ) {
    return context.localSyncRepository.recordUpsert(
      userId: userId?.trim(),
      entityType: CloudDataEntity.song,
      entityId: songId,
    );
  }

  static Future<void> _recordEdition(
    SyncMutationContext context,
    String? userId,
    String editionId,
  ) {
    return context.localSyncRepository.recordUpsert(
      userId: userId?.trim(),
      entityType: CloudDataEntity.albumEdition,
      entityId: editionId,
    );
  }
}
