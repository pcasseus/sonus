import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album_edition_track.dart';
import '../../domain/repositories/album_edition_repository.dart';
import '../../domain/repositories/album_edition_track_repository.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/metadata/metadata_fields.dart';
import '../../domain/services/metadata_field_state_service.dart';
import 'song_artist_credit_service.dart';

class TrackProfileEditResult {
  const TrackProfileEditResult({required this.song, required this.changed});

  final Song song;
  final bool changed;
}

class TrackProfileEditingService {
  const TrackProfileEditingService({
    required this.mutationRunner,
    this.metadataAuthority = MetadataAuthority.manual,
    this.metadataSource = MetadataProvenanceSource.user,
  });

  final SyncMutationRunner mutationRunner;
  final MetadataAuthority metadataAuthority;
  final MetadataProvenanceSource metadataSource;

  TrackProfileEditingService withMetadataProvenance({
    required MetadataAuthority authority,
    required MetadataProvenanceSource source,
  }) {
    return TrackProfileEditingService(
      mutationRunner: mutationRunner,
      metadataAuthority: authority,
      metadataSource: source,
    );
  }

  Future<TrackProfileEditResult> updateTrack({
    required String? userId,
    required String songId,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? placementEditionId,
    DateTime? now,
  }) {
    return updateTrackWithCredits(
      userId: userId,
      songId: songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      additionalCredits: [
        for (final featuredArtist in featuredArtists)
          SongArtistCreditInput(
            creditedName: featuredArtist,
            role: SongArtistCreditRole.featured,
          ),
      ],
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      placementEditionId: placementEditionId,
      now: now,
    );
  }

  /// Saves a track's metadata.
  ///
  /// Edition memberships change only through an explicit [albumEditionId]:
  /// - same album: the song is added to that edition (existing listings are
  ///   kept) and it becomes the song's compatibility edition;
  /// - another album ([albumId] differs): the song moves there, and every
  ///   listing it had in the old album's editions is removed.
  ///
  /// Without [albumEditionId] every membership is kept. [placementEditionId]
  /// names the edition listing the disc and track numbers belong to (the
  /// listing the editor was opened from); it defaults to the song's
  /// compatibility edition. Numbers edited for another listing change only
  /// that listing, never the song's own numbers or the other listings.
  Future<TrackProfileEditResult> updateTrackWithCredits({
    required String? userId,
    required String songId,
    required String title,
    required int trackNumber,
    required int discNumber,
    required Iterable<SongArtistCreditInput> additionalCredits,
    required bool isSingle,
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
    SongReleaseStatus releaseStatus = SongReleaseStatus.released,
    bool isLeak = false,
    bool updateVersionMetadata = false,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? placementEditionId,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedSongId = songId.trim();
    final trimmedTitle = title.trim();

    final normalizedArtistId = artistId?.trim();
    final normalizedAlbumId = albumId?.trim();
    final normalizedAlbumEditionId = albumEditionId?.trim();
    final normalizedPlacementEditionId = placementEditionId?.trim();
    final normalizedVersionLabel = versionLabel?.trim();
    if (normalizedSongId.isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Song id must not be blank.');
    }

    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Song title must not be blank.',
      );
    }

    if (trackNumber < 0) {
      throw ArgumentError.value(
        trackNumber,
        'trackNumber',
        'Track number must not be negative.',
      );
    }

    if (discNumber < 0) {
      throw ArgumentError.value(
        discNumber,
        'discNumber',
        'Disc number must not be negative.',
      );
    }

    if (artistId != null && normalizedArtistId!.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    if (albumId != null && normalizedAlbumId!.isEmpty) {
      throw ArgumentError.value(
        albumId,
        'albumId',
        'Album id must not be blank.',
      );
    }

    if (albumEditionId != null && normalizedAlbumEditionId!.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition id must not be blank.',
      );
    }

    if (placementEditionId != null && normalizedPlacementEditionId!.isEmpty) {
      throw ArgumentError.value(
        placementEditionId,
        'placementEditionId',
        'Placement edition id must not be blank.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final targetArtistId = normalizedArtistId ?? song.artistId;
      final targetAlbumId = normalizedAlbumId ?? song.albumId;
      final targetEditionId = normalizedAlbumEditionId ?? song.albumEditionId;
      final targetVersionLabel = updateVersionMetadata
          ? (normalizedVersionLabel == null || normalizedVersionLabel.isEmpty
                ? null
                : normalizedVersionLabel)
          : song.versionLabel;
      final targetVersionCharacteristics = updateVersionMetadata
          ? List<SongVersionCharacteristic>.unmodifiable(versionCharacteristics)
          : song.versionCharacteristics;
      final targetReleaseStatus = updateVersionMetadata
          ? releaseStatus
          : song.releaseStatus;
      final targetIsLeak = updateVersionMetadata ? isLeak : song.isLeak;
      final targetArtist = await context.artistRepository.getById(
        targetArtistId,
      );

      if (targetArtist == null) {
        throw StateError('Artist not found: $targetArtistId');
      }

      final normalizedAdditionalCredits = _normalizeAdditionalCredits(
        additionalCredits,
        primaryCanonicalName: targetArtist.canonicalName,
      );

      final projectedFeaturedArtists = [
        for (final credit in normalizedAdditionalCredits)
          if (credit.role == SongArtistCreditRole.featured) credit.creditedName,
      ];
      final targetAlbum = await context.albumRepository.getById(targetAlbumId);

      if (targetAlbum == null) {
        throw StateError('Album not found: $targetAlbumId');
      }

      final targetEdition = await context.albumEditionRepository.getById(
        targetEditionId,
      );

      if (targetEdition == null) {
        throw StateError('Album edition not found: $targetEditionId');
      }

      if (targetEdition.albumId != targetAlbum.id) {
        throw StateError(
          'Album edition $targetEditionId does not belong to '
          'album $targetAlbumId',
        );
      }

      // Which listing the edited disc and track numbers belong to. An
      // explicit edition operation places the song in its target edition;
      // otherwise the numbers belong to the listing the editor showed.
      final explicitEditionOperation =
          targetEditionId != song.albumEditionId ||
          targetAlbumId != song.albumId;
      final placementEdition = explicitEditionOperation
          ? targetEditionId
          : normalizedPlacementEditionId ?? song.albumEditionId;
      final numbersFollowSong = placementEdition == targetEditionId;

      AlbumEditionTrack? placementMembership;

      if (!numbersFollowSong) {
        for (final membership
            in await context.albumEditionTrackRepository.getBySongId(song.id)) {
          if (membership.albumEditionId == placementEdition) {
            placementMembership = membership;
            break;
          }
        }

        if (placementMembership == null) {
          throw StateError(
            'Song ${song.id} is not listed in album edition '
            '$placementEdition',
          );
        }
      }

      // The song's own numbers follow its compatibility listing only.
      final songTrackNumber = numbersFollowSong
          ? trackNumber
          : song.trackNumber;
      final songDiscNumber = numbersFollowSong ? discNumber : song.discNumber;
      final placementChanged =
          placementMembership != null &&
          (placementMembership.trackNumber != trackNumber ||
              placementMembership.discNumber != discNumber);

      final canonicalTitle = TextNormalizer.canonicalize(trimmedTitle);

      final existingStructuredCredits = await context.songArtistCreditRepository
          .getBySongId(song.id);

      final structuredCreditsChanged = _structuredCreditsChanged(
        existingCredits: existingStructuredCredits,
        song: song,
        primaryArtistId: targetArtistId,
        primaryCanonicalName: targetArtist.canonicalName,
        desiredAdditionalCredits: normalizedAdditionalCredits,
      );

      final changedMetadataFields = <String>{
        if (song.artistId != targetArtistId) MetadataFields.songArtist,
        if (song.albumId != targetAlbumId) MetadataFields.songAlbum,
        if (song.albumEditionId != targetEditionId)
          MetadataFields.songAlbumEdition,
        if (song.title != trimmedTitle) MetadataFields.songTitle,
        if (song.trackNumber != songTrackNumber) MetadataFields.songTrackNumber,
        if (song.discNumber != songDiscNumber) MetadataFields.songDiscNumber,
        if (song.isSingle != isSingle) MetadataFields.songIsSingle,
        if (song.versionLabel != targetVersionLabel)
          MetadataFields.songVersionLabel,
        if (!(song.versionCharacteristics.length ==
                targetVersionCharacteristics.length &&
            song.versionCharacteristics.asMap().entries.every(
              (entry) => entry.value == targetVersionCharacteristics[entry.key],
            )))
          MetadataFields.songVersionCharacteristics,
        if (song.releaseStatus != targetReleaseStatus)
          MetadataFields.songReleaseStatus,
        if (song.isLeak != targetIsLeak) MetadataFields.songIsLeak,
        if (structuredCreditsChanged) MetadataFields.songArtistCredits,
      };
      final changed =
          song.artistId != targetArtistId ||
          song.albumId != targetAlbumId ||
          song.albumEditionId != targetEditionId ||
          song.title != trimmedTitle ||
          song.canonicalTitle != canonicalTitle ||
          song.trackNumber != songTrackNumber ||
          song.discNumber != songDiscNumber ||
          song.isSingle != isSingle ||
          song.versionLabel != targetVersionLabel ||
          !(song.versionCharacteristics.length ==
                  targetVersionCharacteristics.length &&
              song.versionCharacteristics.asMap().entries.every(
                (entry) =>
                    entry.value == targetVersionCharacteristics[entry.key],
              )) ||
          song.releaseStatus != targetReleaseStatus ||
          song.isLeak != targetIsLeak ||
          !_listsEqual(song.featuredArtists, projectedFeaturedArtists) ||
          structuredCreditsChanged;

      if (!changed && !placementChanged) {
        return TrackProfileEditResult(song: song, changed: false);
      }

      if (placementChanged) {
        await _savePlacement(
          membershipRepository: context.albumEditionTrackRepository,
          membership: placementMembership,
          discNumber: discNumber,
          trackNumber: trackNumber,
          now: timestamp,
        );
      }

      if (!changed) {
        // Only another edition's listing changed. Listings are local data
        // (not synced), so there is no song mutation to record.
        return TrackProfileEditResult(song: song, changed: true);
      }

      final updated = song.copyWith(
        artistId: targetArtistId,
        albumId: targetAlbumId,
        albumEditionId: targetEditionId,
        title: trimmedTitle,
        canonicalTitle: canonicalTitle,
        trackNumber: songTrackNumber,
        discNumber: songDiscNumber,
        isSingle: isSingle,
        versionLabel: targetVersionLabel,
        versionCharacteristics: targetVersionCharacteristics,
        releaseStatus: targetReleaseStatus,
        isLeak: targetIsLeak,
        featuredArtists: List<String>.unmodifiable(projectedFeaturedArtists),
        updatedAt: timestamp,
      );
      final structuredCredits =
          await SongArtistCreditService.replaceCreditsInContext(
            context: context,
            userId: normalizedUserId,
            songId: updated.id,
            primaryArtistId: targetArtistId,
            additionalCredits: normalizedAdditionalCredits,
            now: timestamp,
          );

      final authoritativeFeaturedArtists = [
        for (final credit in structuredCredits)
          if (credit.role == SongArtistCreditRole.featured) credit.creditedName,
      ];

      final persisted = updated.copyWith(
        featuredArtists: List<String>.unmodifiable(
          authoritativeFeaturedArtists,
        ),
      );

      final membershipRepository = context.albumEditionTrackRepository;
      await _persistCompatibilityMembership(
        membershipRepository: membershipRepository,
        editionRepository: context.albumEditionRepository,
        originalSong: song,
        persistedSong: persisted,
        now: timestamp,
      );

      await context.songRepository.save(persisted);

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null && changedMetadataFields.isNotEmpty) {
        final metadataService = MetadataFieldStateService(
          repository: metadataRepository,
        );

        await metadataService.recordAll(
          entityType: MetadataEntityType.song,
          entityId: persisted.id,
          fieldNames: changedMetadataFields,
          authority: metadataAuthority,
          source: metadataSource,
          updatedAt: timestamp,
        );
      }

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.song,
        entityId: persisted.id,
      );

      return TrackProfileEditResult(song: persisted, changed: true);
    });
  }

  /// Writes edited numbers to one edition listing, marking them manual.
  Future<void> _savePlacement({
    required AlbumEditionTrackRepository membershipRepository,
    required AlbumEditionTrack membership,
    required int discNumber,
    required int trackNumber,
    required DateTime now,
  }) {
    return membershipRepository.save(
      membership.copyWith(
        discNumber: discNumber,
        trackNumber: trackNumber,
        numberingAuthority: AlbumEditionTrackAuthority.manual,
        updatedAt: now,
      ),
    );
  }

  Future<void> _persistCompatibilityMembership({
    required AlbumEditionTrackRepository membershipRepository,
    required AlbumEditionRepository editionRepository,
    required Song originalSong,
    required Song persistedSong,
    required DateTime now,
  }) async {
    final numberingChanged =
        originalSong.discNumber != persistedSong.discNumber ||
        originalSong.trackNumber != persistedSong.trackNumber;

    final existingMemberships = await membershipRepository.getBySongId(
      persistedSong.id,
    );

    AlbumEditionTrack? originalCompatibilityMembership;

    for (final membership in existingMemberships) {
      if (membership.albumEditionId == originalSong.albumEditionId) {
        originalCompatibilityMembership = membership;
        break;
      }
    }

    final editionChanged =
        originalSong.albumEditionId != persistedSong.albumEditionId;

    if (!editionChanged) {
      if (originalCompatibilityMembership == null) {
        final targetMemberships = await membershipRepository.getByEditionId(
          persistedSong.albumEditionId,
        );

        final nextSortPosition = targetMemberships.isEmpty
            ? 0
            : targetMemberships
                      .map((membership) => membership.sortPosition)
                      .reduce((left, right) => left > right ? left : right) +
                  1;

        await membershipRepository.create(
          AlbumEditionTrack(
            albumEditionId: persistedSong.albumEditionId,
            songId: persistedSong.id,
            discNumber: persistedSong.discNumber,
            trackNumber: persistedSong.trackNumber,
            sortPosition: nextSortPosition,
            numberingAuthority: numberingChanged
                ? AlbumEditionTrackAuthority.manual
                : AlbumEditionTrackAuthority.inferred,
            createdAt: persistedSong.createdAt,
            updatedAt: now,
          ),
        );

        return;
      }

      final membershipChanged =
          originalCompatibilityMembership.discNumber !=
              persistedSong.discNumber ||
          originalCompatibilityMembership.trackNumber !=
              persistedSong.trackNumber;

      if (membershipChanged) {
        await membershipRepository.save(
          originalCompatibilityMembership.copyWith(
            discNumber: persistedSong.discNumber,
            trackNumber: persistedSong.trackNumber,
            numberingAuthority: numberingChanged
                ? AlbumEditionTrackAuthority.manual
                : originalCompatibilityMembership.numberingAuthority,
            updatedAt: now,
          ),
        );
      }

      return;
    }

    final targetMemberships = await membershipRepository.getByEditionId(
      persistedSong.albumEditionId,
    );

    AlbumEditionTrack? existingTargetMembership;

    for (final membership in targetMemberships) {
      if (membership.songId == persistedSong.id) {
        existingTargetMembership = membership;
        break;
      }
    }

    if (existingTargetMembership == null) {
      final nextSortPosition = targetMemberships.isEmpty
          ? 0
          : targetMemberships
                    .map((membership) => membership.sortPosition)
                    .reduce((left, right) => left > right ? left : right) +
                1;

      await membershipRepository.create(
        AlbumEditionTrack(
          albumEditionId: persistedSong.albumEditionId,
          songId: persistedSong.id,
          discNumber: persistedSong.discNumber,
          trackNumber: persistedSong.trackNumber,
          sortPosition: nextSortPosition,
          numberingAuthority: numberingChanged
              ? AlbumEditionTrackAuthority.manual
              : AlbumEditionTrackAuthority.inferred,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await membershipRepository.save(
        existingTargetMembership.copyWith(
          discNumber: persistedSong.discNumber,
          trackNumber: persistedSong.trackNumber,
          numberingAuthority: numberingChanged
              ? AlbumEditionTrackAuthority.manual
              : existingTargetMembership.numberingAuthority,
          updatedAt: now,
        ),
      );
    }
    final albumChanged = originalSong.albumId != persistedSong.albumId;

    if (!albumChanged) {
      return;
    }

    // A song moved to another album leaves every listing it had in the old
    // album's editions, not only its compatibility listing.
    final oldEditionIds = {
      for (final edition in await editionRepository.getByAlbumId(
        originalSong.albumId,
      ))
        edition.id,
    };

    for (final membership in existingMemberships) {
      if (oldEditionIds.contains(membership.albumEditionId)) {
        await membershipRepository.delete(
          editionId: membership.albumEditionId,
          songId: persistedSong.id,
        );
      }
    }
  }

  List<SongArtistCreditInput> _normalizeAdditionalCredits(
    Iterable<SongArtistCreditInput> credits, {
    required String primaryCanonicalName,
  }) {
    final seenCanonicalNames = <String>{primaryCanonicalName};
    final normalized = <SongArtistCreditInput>[];

    for (final credit in credits) {
      if (credit.role == SongArtistCreditRole.primary) {
        throw ArgumentError('Additional credits may not use the primary role.');
      }

      final creditedName = credit.creditedName.trim();

      if (creditedName.isEmpty) {
        continue;
      }

      final canonicalName = TextNormalizer.canonicalize(creditedName);

      if (canonicalName.isEmpty || !seenCanonicalNames.add(canonicalName)) {
        continue;
      }

      final normalizedArtistId = credit.artistId?.trim();

      normalized.add(
        SongArtistCreditInput(
          creditedName: creditedName,
          role: credit.role,
          artistId: normalizedArtistId == null || normalizedArtistId.isEmpty
              ? null
              : normalizedArtistId,
        ),
      );
    }

    return List<SongArtistCreditInput>.unmodifiable(normalized);
  }

  bool _structuredCreditsChanged({
    required List<SongArtistCredit> existingCredits,
    required Song song,
    required String primaryArtistId,
    required String primaryCanonicalName,
    required List<SongArtistCreditInput> desiredAdditionalCredits,
  }) {
    if (existingCredits.isEmpty) {
      final legacyAdditionalCredits = _normalizeAdditionalCredits([
        for (final featuredArtist in song.featuredArtists)
          SongArtistCreditInput(
            creditedName: featuredArtist,
            role: SongArtistCreditRole.featured,
          ),
      ], primaryCanonicalName: primaryCanonicalName);

      return !_additionalCreditInputsEqual(
        legacyAdditionalCredits,
        desiredAdditionalCredits,
      );
    }

    final orderedCredits = List<SongArtistCredit>.from(existingCredits)
      ..sort((left, right) => left.position.compareTo(right.position));

    final primaryCredits = [
      for (final credit in orderedCredits)
        if (credit.role == SongArtistCreditRole.primary) credit,
    ];

    if (primaryCredits.length != 1 ||
        primaryCredits.single.artistId != primaryArtistId) {
      return true;
    }

    final currentAdditionalCredits = [
      for (final credit in orderedCredits)
        if (credit.role != SongArtistCreditRole.primary) credit,
    ];

    if (currentAdditionalCredits.length != desiredAdditionalCredits.length) {
      return true;
    }

    for (var index = 0; index < desiredAdditionalCredits.length; index++) {
      final current = currentAdditionalCredits[index];
      final desired = desiredAdditionalCredits[index];

      if (current.creditedName != desired.creditedName ||
          current.role != desired.role) {
        return true;
      }

      final explicitDesiredArtistId = desired.artistId?.trim();

      if (explicitDesiredArtistId != null &&
          explicitDesiredArtistId.isNotEmpty &&
          current.artistId != explicitDesiredArtistId) {
        return true;
      }
    }

    return false;
  }

  bool _additionalCreditInputsEqual(
    List<SongArtistCreditInput> first,
    List<SongArtistCreditInput> second,
  ) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      final left = first[index];
      final right = second[index];

      if (left.creditedName != right.creditedName || left.role != right.role) {
        return false;
      }

      final leftArtistId = left.artistId?.trim();
      final rightArtistId = right.artistId?.trim();

      if ((leftArtistId?.isNotEmpty ?? false) ||
          (rightArtistId?.isNotEmpty ?? false)) {
        if (leftArtistId != rightArtistId) {
          return false;
        }
      }
    }

    return true;
  }

  bool _listsEqual(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }
}
