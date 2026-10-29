import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../models/track_profile_edit_draft.dart';
import '../pages/track_studio_page.dart';

/// Whether Track Studio can save from a surface that has no library
/// controller of its own, such as Search or a playlist.
bool canOpenTrackStudio(BuildContext context) {
  return context.read<TrackProfileEditingService?>() != null &&
      context.read<LibraryQueryRepository?>() != null;
}

/// Opens Track Studio for [track] and saves its draft the way the Tracks and
/// Album pages do (SN-50 C-Q12), then calls [onSaved] so the surface can
/// reload. Says so when saving fails.
Future<void> openTrackStudio(
  BuildContext context, {
  required LibraryTrack track,
  String? userId,
  Future<void> Function()? onSaved,
}) async {
  final service = context.read<TrackProfileEditingService?>();
  final repository = context.read<LibraryQueryRepository?>();

  if (service == null || repository == null) {
    return;
  }

  final creditRepository = context.read<SongArtistCreditRepository?>();
  final artistCreationService = context.read<ArtistCreationService?>();
  final metadataProvider = context.read<MetadataProvider?>();
  final applicationService = context
      .read<ExternalMetadataApplicationService?>();
  final proposalService = context.read<ExternalMetadataProposalService?>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  try {
    final artists = await repository.getArtists();
    final albums = await repository.getAlbums();
    final credits = creditRepository == null
        ? null
        : await creditRepository.getBySongId(track.songId);

    if (!context.mounted) {
      return;
    }

    final draft = await navigator.push<TrackProfileEditDraft>(
      MaterialPageRoute<TrackProfileEditDraft>(
        builder: (routeContext) {
          return TrackStudioPage(
            track: track,
            userId: userId,
            metadataProvider: metadataProvider,
            externalMetadataApplicationService: applicationService,
            externalMetadataProposalService: proposalService,
            onMetadataApplied: onSaved,
            artists: artists,
            albums: albums,
            initialAdditionalCredits: trackStudioInitialCredits(
              credits: credits ?? const [],
              legacyFeaturedArtists: track.featuredArtists,
              primaryArtistId: track.artistId,
              primaryArtistName: track.artistName,
            ),
            onCreateArtist: artistCreationService == null
                ? null
                : (name) async {
                    final artist = await artistCreationService.createOrReuse(
                      userId: userId,
                      name: name,
                    );

                    return LibraryArtist(
                      artistId: artist.id,
                      name: artist.name,
                      albumCount: 0,
                      songCount: 0,
                      dateAdded: artist.createdAt,
                    );
                  },
          );
        },
      ),
    );

    if (draft == null) {
      return;
    }

    final result = await service.updateTrackWithCredits(
      userId: userId,
      songId: track.songId,
      title: draft.title,
      trackNumber: draft.trackNumber,
      discNumber: draft.discNumber,
      additionalCredits: draft.additionalCredits.map(
        (credit) => credit.toInput(),
      ),
      isSingle: draft.isSingle,
      versionLabel: draft.versionLabel,
      versionCharacteristics: draft.versionCharacteristics,
      releaseStatus: draft.releaseStatus,
      isLeak: draft.isLeak,
      updateVersionMetadata: true,
      artistId: draft.artistId,
      albumId: draft.albumId,
      albumEditionId: draft.moveToEditionId,
      placementEditionId: draft.placementEditionId,
    );

    await onSaved?.call();

    if (result.changed) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Song details updated.')),
      );
    }
  } catch (error, stackTrace) {
    developer.log(
      'Track Studio could not save a song (${error.runtimeType})',
      name: 'sonus.library',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not update song details.')),
    );
  }
}
