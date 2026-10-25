import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_context.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/album_edition_track.dart';
import '../../domain/entities/entity_factory.dart';
import '../../domain/entities/song.dart';
import '../../domain/repositories/album_edition_repository.dart';

/// Why an edition operation was refused. Nothing is changed when one is.
enum AlbumEditionRefusal {
  albumNotFound,
  editionNotFound,
  blankTitle,
  duplicateTitle,
  songNotOnAlbum,

  /// Every song stays on at least one edition of its album.
  lastEditionOfSong,

  /// Only an empty, non-primary edition can be deleted, and never an
  /// album's only edition.
  editionNotEmpty,
  primaryEdition,
  onlyEdition,
}

class AlbumEditionManagementException implements Exception {
  const AlbumEditionManagementException(this.refusal);

  final AlbumEditionRefusal refusal;

  @override
  String toString() => 'AlbumEditionManagementException(${refusal.name})';
}

/// Album Studio's edition operations: create, rename or retype, choose the
/// primary edition, assign and remove tracks, and delete empty editions.
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

      for (final edition in editions) {
        final shouldBePrimary = edition.id == target.id;

        if (edition.isPrimary != shouldBePrimary) {
          await context.albumEditionRepository.save(
            edition.copyWith(isPrimary: shouldBePrimary, updatedAt: timestamp),
          );
          await _recordEdition(context, userId, edition.id);
        }
      }
    });
  }

  /// Lists [songIds] on the edition. A song already listed is left as it
  /// is; a song listed on another edition keeps its disc and track number
  /// there. Returns how many songs were added.
  Future<int> assignTracks({
    required String editionId,
    required List<String> songIds,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
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
    });
  }

  /// Removes the edition's listing of [songId]. The song stays in the
  /// library. If this was the song's home edition, its home moves to
  /// another edition that lists it, preferring the primary one.
  Future<void> removeTrack({
    required String editionId,
    required String songId,
    String? userId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
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
        return; // Not listed on this edition.
      }

      if (song.albumEditionId == edition.id) {
        final editions = await context.albumEditionRepository.getByAlbumId(
          edition.albumId,
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
        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.song,
          entityId: song.id,
        );
      }

      await context.albumEditionTrackRepository.delete(
        editionId: edition.id,
        songId: song.id,
      );
      await _recordSong(context, userId, song.id);
    });
  }

  /// Deletes an edition that lists no tracks, is not primary and is not
  /// the album's only edition.
  Future<void> deleteEdition({required String editionId, String? userId}) {
    return mutationRunner.run((context) async {
      final edition = await _edition(context, editionId);
      final repository = context.albumEditionRepository;

      if (edition.isPrimary) {
        throw const AlbumEditionManagementException(
          AlbumEditionRefusal.primaryEdition,
        );
      }

      final editions = await repository.getByAlbumId(edition.albumId);

      if (editions.length <= 1) {
        throw const AlbumEditionManagementException(
          AlbumEditionRefusal.onlyEdition,
        );
      }

      final memberships = await context.albumEditionTrackRepository
          .getByEditionId(edition.id);
      final homeSongs = (await context.songRepository.getByEditionId(
        edition.id,
      ));

      if (memberships.isNotEmpty || homeSongs.isNotEmpty) {
        throw const AlbumEditionManagementException(
          AlbumEditionRefusal.editionNotEmpty,
        );
      }

      if (repository is! AlbumEditionDeletionRepository) {
        throw StateError('Edition deletion is not available here.');
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
