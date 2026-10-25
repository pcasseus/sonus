import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/metadata/metadata_fields.dart';
import '../../domain/entities/library_organization.dart';
import '../../domain/repositories/library_organization_repository.dart';
import '../../domain/repositories/metadata_field_state_repository.dart';
import '../../domain/services/metadata_authority_policy.dart';
import '../../domain/services/metadata_field_state_service.dart';
import '../models/external_metadata_candidate.dart';
import '../models/external_metadata_search_query.dart';

class ExternalMetadataIdentityCollisionException implements Exception {
  const ExternalMetadataIdentityCollisionException({
    required this.entityId,
    required this.conflictingEntityId,
    required this.value,
  });

  final String entityId;
  final String conflictingEntityId;
  final String value;

  @override
  String toString() {
    return 'ExternalMetadataIdentityCollisionException('
        'entityId: $entityId, '
        'conflictingEntityId: $conflictingEntityId, '
        'value: $value)';
  }
}

class ExternalMetadataApplicationResult {
  const ExternalMetadataApplicationResult({
    this.changedFields = const {},
    this.provenanceUpdatedFields = const {},
    this.protectedFields = const {},
    this.reviewRequiredFields = const {},
  });

  final Set<String> changedFields;
  final Set<String> provenanceUpdatedFields;
  final Set<String> protectedFields;
  final Set<String> reviewRequiredFields;

  bool get entityChanged => changedFields.isNotEmpty;

  bool get hasProtectedFields => protectedFields.isNotEmpty;

  bool get requiresReview => reviewRequiredFields.isNotEmpty;
}

class ExternalMetadataApplicationService {
  const ExternalMetadataApplicationService({
    required this.mutationRunner,
    this.organization,
  });

  final SyncMutationRunner mutationRunner;

  /// Where an applied release group's type (Soundtrack, Compilation) is
  /// recorded as the album's release classification.
  final LibraryOrganizationRepository? organization;

  /// After an album candidate is applied, its MusicBrainz release-group
  /// type becomes the album's classification, unless the user classified
  /// the album themselves. Runs after the apply has committed.
  Future<ExternalMetadataApplicationResult> _thenRecordReleaseKind(
    Future<ExternalMetadataApplicationResult> applying, {
    required String albumId,
    required ExternalMetadataCandidate candidate,
    required DateTime timestamp,
  }) async {
    final result = await applying;
    final repository = organization;
    final kind = ReleaseKind.fromMusicBrainz(candidate.secondaryTypes);

    if (repository == null || kind == null) {
      return result;
    }

    final existing = (await repository.getClassifications())
        .where((classification) => classification.albumId == albumId)
        .firstOrNull;

    if (existing?.authority != ReleaseClassificationAuthority.manual) {
      await repository.saveClassification(
        AlbumReleaseClassification(
          albumId: albumId,
          kind: kind,
          authority: ReleaseClassificationAuthority.external,
          sourceReference: candidate.sourceReference,
          createdAt: existing?.createdAt ?? timestamp,
          updatedAt: timestamp,
        ),
      );
    }

    return result;
  }

  Future<ExternalMetadataApplicationResult> applyArtistCandidate({
    required String? userId,
    required String artistId,
    required ExternalMetadataCandidate candidate,
    DateTime? now,
  }) {
    _requireKind(candidate, ExternalMetadataEntityKind.artist);

    final normalizedArtistId = _requiredId(artistId, 'artistId');
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final artist = await context.artistRepository.getById(normalizedArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $normalizedArtistId');
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError(
          'Metadata field state repository is required for external metadata.',
        );
      }

      final targetName = candidate.displayName.trim();

      if (targetName.isEmpty) {
        return const ExternalMetadataApplicationResult();
      }

      final evaluation = await _evaluate(
        repository: metadataRepository,
        entityType: MetadataEntityType.artist,
        entityId: artist.id,
        fieldName: MetadataFields.artistName,
        existingValuePresent: artist.name.trim().isNotEmpty,
      );

      if (evaluation != MetadataReplacementDecision.accept) {
        return _rejectedResult(MetadataFields.artistName, evaluation);
      }

      final changed = artist.name != targetName;

      if (changed) {
        final canonicalName = TextNormalizer.canonicalize(targetName);

        final collisions = (await context.artistRepository.getAll())
            .where(
              (other) =>
                  other.id != artist.id && other.canonicalName == canonicalName,
            )
            .toList(growable: false);

        if (collisions.isNotEmpty) {
          throw ExternalMetadataIdentityCollisionException(
            entityId: artist.id,
            conflictingEntityId: collisions.first.id,
            value: targetName,
          );
        }

        await context.artistRepository.save(
          artist.copyWith(
            name: targetName,
            canonicalName: canonicalName,
            updatedAt: timestamp,
          ),
        );
      }

      final provenanceChanged =
          !changed &&
          await _needsMusicBrainzProvenanceUpdate(
            repository: metadataRepository,
            entityType: MetadataEntityType.artist,
            entityId: artist.id,
            fieldName: MetadataFields.artistName,
            sourceReference: candidate.sourceReference,
          );

      if (changed || provenanceChanged) {
        await MetadataFieldStateService(repository: metadataRepository).record(
          entityType: MetadataEntityType.artist,
          entityId: artist.id,
          fieldName: MetadataFields.artistName,
          authority: MetadataAuthority.external,
          source: MetadataProvenanceSource.musicBrainz,
          sourceReference: candidate.sourceReference,
          updatedAt: timestamp,
        );

        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.artist,
          entityId: artist.id,
        );
      }

      return ExternalMetadataApplicationResult(
        changedFields: changed ? const {MetadataFields.artistName} : const {},
        provenanceUpdatedFields: provenanceChanged
            ? const {MetadataFields.artistName}
            : const {},
      );
    });
  }

  Future<ExternalMetadataApplicationResult> applyAlbumCandidate({
    required String? userId,
    required String albumId,
    required ExternalMetadataCandidate candidate,
    DateTime? now,
  }) {
    _requireKind(candidate, ExternalMetadataEntityKind.album);

    final normalizedAlbumId = _requiredId(albumId, 'albumId');
    final timestamp = now ?? DateTime.now();

    return _thenRecordReleaseKind(
      albumId: normalizedAlbumId,
      candidate: candidate,
      timestamp: timestamp,
      mutationRunner.run((context) async {
        final album = await context.albumRepository.getById(normalizedAlbumId);

        if (album == null) {
          throw StateError('Album not found: $normalizedAlbumId');
        }

        final metadataRepository = context.metadataFieldStateRepository;

        if (metadataRepository == null) {
          throw StateError(
            'Metadata field state repository is required for external metadata.',
          );
        }

        final changedFields = <String>{};
        final provenanceFields = <String>{};
        final protectedFields = <String>{};
        final reviewFields = <String>{};

        var updatedAlbum = album;

        final targetTitle = candidate.displayName.trim();

        if (targetTitle.isNotEmpty) {
          final titleDecision = await _evaluate(
            repository: metadataRepository,
            entityType: MetadataEntityType.album,
            entityId: album.id,
            fieldName: MetadataFields.albumTitle,
            existingValuePresent: album.title.trim().isNotEmpty,
          );

          if (titleDecision == MetadataReplacementDecision.accept) {
            final changed = album.title != targetTitle;

            if (changed) {
              updatedAlbum = updatedAlbum.copyWith(
                title: targetTitle,
                canonicalTitle: TextNormalizer.canonicalize(targetTitle),
                updatedAt: timestamp,
              );

              changedFields.add(MetadataFields.albumTitle);
            } else if (await _needsMusicBrainzProvenanceUpdate(
              repository: metadataRepository,
              entityType: MetadataEntityType.album,
              entityId: album.id,
              fieldName: MetadataFields.albumTitle,
              sourceReference: candidate.sourceReference,
            )) {
              provenanceFields.add(MetadataFields.albumTitle);
            }

            if (changed ||
                provenanceFields.contains(MetadataFields.albumTitle)) {
              await MetadataFieldStateService(
                repository: metadataRepository,
              ).record(
                entityType: MetadataEntityType.album,
                entityId: album.id,
                fieldName: MetadataFields.albumTitle,
                authority: MetadataAuthority.external,
                source: MetadataProvenanceSource.musicBrainz,
                sourceReference: candidate.sourceReference,
                updatedAt: timestamp,
              );
            }
          } else {
            _collectRejection(
              fieldName: MetadataFields.albumTitle,
              decision: titleDecision,
              protectedFields: protectedFields,
              reviewFields: reviewFields,
            );
          }
        }

        final albumChanged = changedFields.contains(MetadataFields.albumTitle);

        if (albumChanged) {
          await context.albumRepository.save(updatedAlbum);
        }

        if (albumChanged || provenanceFields.isNotEmpty) {
          await context.localSyncRepository.recordUpsert(
            userId: userId?.trim(),
            entityType: CloudDataEntity.album,
            entityId: album.id,
          );
        }

        return ExternalMetadataApplicationResult(
          changedFields: Set.unmodifiable(changedFields),
          provenanceUpdatedFields: Set.unmodifiable(provenanceFields),
          protectedFields: Set.unmodifiable(protectedFields),
          reviewRequiredFields: Set.unmodifiable(reviewFields),
        );
      }),
    );
  }

  Future<ExternalMetadataApplicationResult> applyTrackCandidate({
    required String? userId,
    required String songId,
    required ExternalMetadataCandidate candidate,
    DateTime? now,
  }) {
    _requireKind(candidate, ExternalMetadataEntityKind.track);

    final normalizedSongId = _requiredId(songId, 'songId');
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError(
          'Metadata field state repository is required for external metadata.',
        );
      }

      final changedFields = <String>{};
      final provenanceFields = <String>{};
      final protectedFields = <String>{};
      final reviewFields = <String>{};

      var updatedSong = song;

      final targetTitle = candidate.displayName.trim();

      if (targetTitle.isNotEmpty) {
        final titleDecision = await _evaluate(
          repository: metadataRepository,
          entityType: MetadataEntityType.song,
          entityId: song.id,
          fieldName: MetadataFields.songTitle,
          existingValuePresent: song.title.trim().isNotEmpty,
        );

        if (titleDecision == MetadataReplacementDecision.accept) {
          final changed = song.title != targetTitle;

          if (changed) {
            updatedSong = updatedSong.copyWith(
              title: targetTitle,
              canonicalTitle: TextNormalizer.canonicalize(targetTitle),
              updatedAt: timestamp,
            );

            changedFields.add(MetadataFields.songTitle);
          } else if (await _needsMusicBrainzProvenanceUpdate(
            repository: metadataRepository,
            entityType: MetadataEntityType.song,
            entityId: song.id,
            fieldName: MetadataFields.songTitle,
            sourceReference: candidate.sourceReference,
          )) {
            provenanceFields.add(MetadataFields.songTitle);
          }

          if (changed || provenanceFields.contains(MetadataFields.songTitle)) {
            await MetadataFieldStateService(
              repository: metadataRepository,
            ).record(
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songTitle,
              authority: MetadataAuthority.external,
              source: MetadataProvenanceSource.musicBrainz,
              sourceReference: candidate.sourceReference,
              updatedAt: timestamp,
            );
          }
        } else {
          _collectRejection(
            fieldName: MetadataFields.songTitle,
            decision: titleDecision,
            protectedFields: protectedFields,
            reviewFields: reviewFields,
          );
        }
      }

      final targetDuration = candidate.durationSeconds;

      if (targetDuration != null && targetDuration > 0) {
        final durationDecision = await _evaluate(
          repository: metadataRepository,
          entityType: MetadataEntityType.song,
          entityId: song.id,
          fieldName: MetadataFields.songDuration,
          existingValuePresent: song.durationSeconds > 0,
        );

        if (durationDecision == MetadataReplacementDecision.accept) {
          final changed = song.durationSeconds != targetDuration;

          if (changed) {
            updatedSong = updatedSong.copyWith(
              durationSeconds: targetDuration,
              updatedAt: timestamp,
            );

            changedFields.add(MetadataFields.songDuration);
          } else if (await _needsMusicBrainzProvenanceUpdate(
            repository: metadataRepository,
            entityType: MetadataEntityType.song,
            entityId: song.id,
            fieldName: MetadataFields.songDuration,
            sourceReference: candidate.sourceReference,
          )) {
            provenanceFields.add(MetadataFields.songDuration);
          }

          if (changed ||
              provenanceFields.contains(MetadataFields.songDuration)) {
            await MetadataFieldStateService(
              repository: metadataRepository,
            ).record(
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songDuration,
              authority: MetadataAuthority.external,
              source: MetadataProvenanceSource.musicBrainz,
              sourceReference: candidate.sourceReference,
              updatedAt: timestamp,
            );
          }
        } else {
          _collectRejection(
            fieldName: MetadataFields.songDuration,
            decision: durationDecision,
            protectedFields: protectedFields,
            reviewFields: reviewFields,
          );
        }
      }

      if (changedFields.isNotEmpty) {
        await context.songRepository.save(updatedSong);
      }

      if (changedFields.isNotEmpty || provenanceFields.isNotEmpty) {
        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.song,
          entityId: song.id,
        );
      }

      return ExternalMetadataApplicationResult(
        changedFields: Set.unmodifiable(changedFields),
        provenanceUpdatedFields: Set.unmodifiable(provenanceFields),
        protectedFields: Set.unmodifiable(protectedFields),
        reviewRequiredFields: Set.unmodifiable(reviewFields),
      );
    });
  }

  Future<ExternalMetadataApplicationResult> confirmReviewedArtistCandidate({
    required String? userId,
    required String artistId,
    required ExternalMetadataCandidate candidate,
    required Set<String> confirmedFields,
    DateTime? now,
  }) {
    _requireKind(candidate, ExternalMetadataEntityKind.artist);

    final normalizedArtistId = _requiredId(artistId, 'artistId');
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final artist = await context.artistRepository.getById(normalizedArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $normalizedArtistId');
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError(
          'Metadata field state repository is required for external metadata.',
        );
      }

      if (!confirmedFields.contains(MetadataFields.artistName)) {
        return const ExternalMetadataApplicationResult();
      }

      final existingState = await metadataRepository.get(
        entityType: MetadataEntityType.artist,
        entityId: artist.id,
        fieldName: MetadataFields.artistName,
      );

      if (existingState != null) {
        throw StateError(
          'Artist name no longer has unknown metadata authority.',
        );
      }

      final targetName = candidate.displayName.trim();

      if (targetName.isEmpty) {
        return const ExternalMetadataApplicationResult();
      }

      final changed = artist.name != targetName;

      if (changed) {
        final canonicalName = TextNormalizer.canonicalize(targetName);

        final collisions = (await context.artistRepository.getAll())
            .where(
              (other) =>
                  other.id != artist.id && other.canonicalName == canonicalName,
            )
            .toList(growable: false);

        if (collisions.isNotEmpty) {
          throw ExternalMetadataIdentityCollisionException(
            entityId: artist.id,
            conflictingEntityId: collisions.first.id,
            value: targetName,
          );
        }

        await context.artistRepository.save(
          artist.copyWith(
            name: targetName,
            canonicalName: canonicalName,
            updatedAt: timestamp,
          ),
        );
      }

      await MetadataFieldStateService(repository: metadataRepository).record(
        entityType: MetadataEntityType.artist,
        entityId: artist.id,
        fieldName: MetadataFields.artistName,
        authority: MetadataAuthority.confirmed,
        source: MetadataProvenanceSource.review,
        sourceReference: candidate.sourceReference,
        updatedAt: timestamp,
      );

      await context.localSyncRepository.recordUpsert(
        userId: userId?.trim(),
        entityType: CloudDataEntity.artist,
        entityId: artist.id,
      );

      return ExternalMetadataApplicationResult(
        changedFields: changed ? const {MetadataFields.artistName} : const {},
        provenanceUpdatedFields: changed
            ? const {}
            : const {MetadataFields.artistName},
      );
    });
  }

  Future<ExternalMetadataApplicationResult> confirmReviewedAlbumCandidate({
    required String? userId,
    required String albumId,
    required ExternalMetadataCandidate candidate,
    required Set<String> confirmedFields,
    DateTime? now,
  }) {
    _requireKind(candidate, ExternalMetadataEntityKind.album);

    final normalizedAlbumId = _requiredId(albumId, 'albumId');
    final timestamp = now ?? DateTime.now();

    return _thenRecordReleaseKind(
      albumId: normalizedAlbumId,
      candidate: candidate,
      timestamp: timestamp,
      mutationRunner.run((context) async {
        final album = await context.albumRepository.getById(normalizedAlbumId);

        if (album == null) {
          throw StateError('Album not found: $normalizedAlbumId');
        }

        final metadataRepository = context.metadataFieldStateRepository;

        if (metadataRepository == null) {
          throw StateError(
            'Metadata field state repository is required for external metadata.',
          );
        }

        if (!confirmedFields.contains(MetadataFields.albumTitle)) {
          return const ExternalMetadataApplicationResult();
        }

        final existingState = await metadataRepository.get(
          entityType: MetadataEntityType.album,
          entityId: album.id,
          fieldName: MetadataFields.albumTitle,
        );

        if (existingState != null) {
          throw StateError(
            'Album title no longer has unknown metadata authority.',
          );
        }

        final targetTitle = candidate.displayName.trim();

        if (targetTitle.isEmpty) {
          return const ExternalMetadataApplicationResult();
        }

        final changed = album.title != targetTitle;

        if (changed) {
          await context.albumRepository.save(
            album.copyWith(
              title: targetTitle,
              canonicalTitle: TextNormalizer.canonicalize(targetTitle),
              updatedAt: timestamp,
            ),
          );
        }

        await MetadataFieldStateService(repository: metadataRepository).record(
          entityType: MetadataEntityType.album,
          entityId: album.id,
          fieldName: MetadataFields.albumTitle,
          authority: MetadataAuthority.confirmed,
          source: MetadataProvenanceSource.review,
          sourceReference: candidate.sourceReference,
          updatedAt: timestamp,
        );

        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.album,
          entityId: album.id,
        );

        return ExternalMetadataApplicationResult(
          changedFields: changed ? const {MetadataFields.albumTitle} : const {},
          provenanceUpdatedFields: changed
              ? const {}
              : const {MetadataFields.albumTitle},
        );
      }),
    );
  }

  Future<ExternalMetadataApplicationResult> confirmReviewedTrackCandidate({
    required String? userId,
    required String songId,
    required ExternalMetadataCandidate candidate,
    required Set<String> confirmedFields,
    DateTime? now,
  }) {
    _requireKind(candidate, ExternalMetadataEntityKind.track);

    final normalizedSongId = _requiredId(songId, 'songId');
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError(
          'Metadata field state repository is required for external metadata.',
        );
      }

      final changedFields = <String>{};
      final provenanceFields = <String>{};

      var updatedSong = song;

      if (confirmedFields.contains(MetadataFields.songTitle)) {
        final existingState = await metadataRepository.get(
          entityType: MetadataEntityType.song,
          entityId: song.id,
          fieldName: MetadataFields.songTitle,
        );

        if (existingState != null) {
          throw StateError(
            'Song title no longer has unknown metadata authority.',
          );
        }

        final targetTitle = candidate.displayName.trim();

        if (targetTitle.isNotEmpty) {
          if (song.title != targetTitle) {
            updatedSong = updatedSong.copyWith(
              title: targetTitle,
              canonicalTitle: TextNormalizer.canonicalize(targetTitle),
              updatedAt: timestamp,
            );

            changedFields.add(MetadataFields.songTitle);
          } else {
            provenanceFields.add(MetadataFields.songTitle);
          }

          await MetadataFieldStateService(
            repository: metadataRepository,
          ).record(
            entityType: MetadataEntityType.song,
            entityId: song.id,
            fieldName: MetadataFields.songTitle,
            authority: MetadataAuthority.confirmed,
            source: MetadataProvenanceSource.review,
            sourceReference: candidate.sourceReference,
            updatedAt: timestamp,
          );
        }
      }

      if (confirmedFields.contains(MetadataFields.songDuration)) {
        final existingState = await metadataRepository.get(
          entityType: MetadataEntityType.song,
          entityId: song.id,
          fieldName: MetadataFields.songDuration,
        );

        if (existingState != null) {
          throw StateError(
            'Song duration no longer has unknown metadata authority.',
          );
        }

        final targetDuration = candidate.durationSeconds;

        if (targetDuration != null && targetDuration > 0) {
          if (song.durationSeconds != targetDuration) {
            updatedSong = updatedSong.copyWith(
              durationSeconds: targetDuration,
              updatedAt: timestamp,
            );

            changedFields.add(MetadataFields.songDuration);
          } else {
            provenanceFields.add(MetadataFields.songDuration);
          }

          await MetadataFieldStateService(
            repository: metadataRepository,
          ).record(
            entityType: MetadataEntityType.song,
            entityId: song.id,
            fieldName: MetadataFields.songDuration,
            authority: MetadataAuthority.confirmed,
            source: MetadataProvenanceSource.review,
            sourceReference: candidate.sourceReference,
            updatedAt: timestamp,
          );
        }
      }

      if (changedFields.isNotEmpty) {
        await context.songRepository.save(updatedSong);
      }

      if (changedFields.isNotEmpty || provenanceFields.isNotEmpty) {
        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.song,
          entityId: song.id,
        );
      }

      return ExternalMetadataApplicationResult(
        changedFields: Set.unmodifiable(changedFields),
        provenanceUpdatedFields: Set.unmodifiable(provenanceFields),
      );
    });
  }

  static Future<bool> _needsMusicBrainzProvenanceUpdate({
    required MetadataFieldStateRepository repository,
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required String sourceReference,
  }) async {
    final existing = await repository.get(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
    );

    return existing == null ||
        existing.authority != MetadataAuthority.external ||
        existing.source != MetadataProvenanceSource.musicBrainz ||
        existing.sourceReference != sourceReference;
  }

  static Future<MetadataReplacementDecision> _evaluate({
    required MetadataFieldStateRepository repository,
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required bool existingValuePresent,
  }) async {
    final existing = await repository.get(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
    );

    return MetadataAuthorityPolicy.evaluateAutomaticReplacement(
      existingValuePresent: existingValuePresent,
      existing: existing,
      incomingAuthority: MetadataAuthority.external,
    );
  }

  static ExternalMetadataApplicationResult _rejectedResult(
    String fieldName,
    MetadataReplacementDecision decision,
  ) {
    return switch (decision) {
      MetadataReplacementDecision.rejectLowerAuthority =>
        ExternalMetadataApplicationResult(protectedFields: {fieldName}),
      MetadataReplacementDecision.requireReviewUnknownAuthority =>
        ExternalMetadataApplicationResult(reviewRequiredFields: {fieldName}),
      MetadataReplacementDecision.accept =>
        const ExternalMetadataApplicationResult(),
    };
  }

  static void _collectRejection({
    required String fieldName,
    required MetadataReplacementDecision decision,
    required Set<String> protectedFields,
    required Set<String> reviewFields,
  }) {
    switch (decision) {
      case MetadataReplacementDecision.rejectLowerAuthority:
        protectedFields.add(fieldName);
      case MetadataReplacementDecision.requireReviewUnknownAuthority:
        reviewFields.add(fieldName);
      case MetadataReplacementDecision.accept:
        break;
    }
  }

  static String _requiredId(String value, String argumentName) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        argumentName,
        '$argumentName must not be blank.',
      );
    }

    return normalized;
  }

  static void _requireKind(
    ExternalMetadataCandidate candidate,
    ExternalMetadataEntityKind expected,
  ) {
    if (candidate.provider != ExternalMetadataProviderKind.musicBrainz) {
      throw ArgumentError.value(
        candidate.provider,
        'candidate',
        'Only MusicBrainz candidates are supported.',
      );
    }

    if (candidate.entityKind != expected) {
      throw ArgumentError.value(
        candidate.entityKind,
        'candidate',
        'Expected $expected candidate.',
      );
    }
  }
}
