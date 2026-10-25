import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../artwork/application/services/cover_art_candidate_discovery_service.dart';
import '../../../artwork/application/services/cover_art_album_edition_import_service.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../application/services/album_edition_track_ordering_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/album_profile_controller.dart';
import '../models/track_profile_edit_draft.dart';
import 'album_studio_page.dart';
import 'track_studio_page.dart';
import '../widgets/album_profile_edit_dialog.dart';

class AlbumProfilePage extends StatefulWidget {
  const AlbumProfilePage({
    super.key,
    required this.albumId,
    this.initialAlbumTitle,
    this.artworkPalette,
  });

  final String albumId;
  final String? initialAlbumTitle;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? artworkPalette;

  @override
  State<AlbumProfilePage> createState() => _AlbumProfilePageState();
}

class _AlbumProfilePageState extends State<AlbumProfilePage> {
  AlbumProfileController? _controller;
  LibraryQueryRepository? _repository;

  // Artwork atmosphere: theme colours show at once; the artwork's colours
  // arrive asynchronously and replace them once extracted.
  SonusArtworkPalette get _palette =>
      widget.artworkPalette ?? SonusArtworkPalette.shared;
  String? _atmospherePath;
  Brightness? _atmosphereBrightness;
  SonusArtworkColors? _artworkColors;

  /// Asks for the colours of the artwork now on screen. Never sets state
  /// synchronously, so it is safe to call while building.
  void _requestAtmosphere(String? artworkPath, Brightness brightness) {
    if (artworkPath == _atmospherePath && brightness == _atmosphereBrightness) {
      return;
    }
    _atmospherePath = artworkPath;
    _atmosphereBrightness = brightness;

    unawaited(
      _palette.colorsFor(artworkPath, brightness: brightness).then((colors) {
        // A newer artwork (another edition) may have been requested since.
        if (!mounted ||
            artworkPath != _atmospherePath ||
            brightness != _atmosphereBrightness ||
            colors == _artworkColors) {
          return;
        }
        setState(() {
          _artworkColors = colors;
        });
      }),
    );
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    _requestAtmosphere(
      _presentationArtworkPath(controller),
      Theme.of(context).brightness,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();

    _repository = repository;
    _controller = AlbumProfileController(
      repository: repository,
      albumId: widget.albumId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
      albumProfileEditingService: context.read<AlbumProfileEditingService?>(),
      albumEditionTrackOrderingService: context
          .read<AlbumEditionTrackOrderingService?>(),
      songArtistCreditRepository: context.read<SongArtistCreditRepository?>(),
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      songBlockService: context.read<SongBlockService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
    );

    // The artwork can change without this State rebuilding: when the album
    // loads or another edition is selected.
    _controller!.addListener(_onControllerChanged);
    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;
    final tokens = SonusTheme.of(context);

    if (controller != null) {
      _requestAtmosphere(
        _presentationArtworkPath(controller),
        Theme.of(context).brightness,
      );
    }

    final target = SonusArtworkAtmosphere.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: _artworkColors,
    );
    final reduceMotion =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);

    // Eases between theme and artwork colours instead of flashing; jumps
    // straight there with reduced motion.
    return TweenAnimationBuilder<SonusAtmosphereColors>(
      tween: SonusAtmosphereColorsTween(end: SonusAtmosphereColors.of(target)),
      duration: reduceMotion ? Duration.zero : tokens.motion.baseMedium,
      curve: tokens.motion.curve,
      builder: (context, atmosphere, _) =>
          _buildPage(context, controller, userId, atmosphere),
    );
  }

  Widget _buildPage(
    BuildContext context,
    AlbumProfileController? controller,
    String? userId,
    SonusAtmosphereColors atmosphere,
  ) {
    return Scaffold(
      key: const ValueKey<String>('album-profile-page'),
      backgroundColor: atmosphere.background,
      appBar: AppBar(
        backgroundColor: atmosphere.background,
        surfaceTintColor: Colors.transparent,
        title: controller == null
            ? Text(widget.initialAlbumTitle ?? 'Album')
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final album = controller.album;

                  return Text(
                    album == null
                        ? widget.initialAlbumTitle ?? 'Album'
                        : _presentationAlbumTitle(
                            album,
                            controller.selectedEdition,
                          ),
                  );
                },
              ),
        actions: [
          if (controller != null)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return PopupMenuButton<_AlbumMenuAction>(
                  key: const ValueKey<String>('album-profile-artwork-menu'),
                  enabled:
                      controller.canEditArtwork ||
                      controller.canEditAlbumProfile(userId) ||
                      controller.canEditAlbumStudio(userId),
                  tooltip: 'Album actions',
                  onSelected: (action) {
                    unawaited(_handleAlbumAction(controller, action, userId));
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _AlbumMenuAction.studio,
                      enabled:
                          controller.canEditAlbumStudio(userId) ||
                          controller.canEditAlbumProfile(userId) ||
                          controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Album Studio'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: controller == null
          ? const Center(child: Text('Loading album...'))
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isLoading && controller.album == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (controller.hasError && controller.album == null) {
                  return _AlbumProfileLoadError(onRetry: controller.load);
                }

                if (controller.isNotFound) {
                  return const _AlbumNotFound();
                }

                final album = controller.album;

                if (album == null) {
                  return const SizedBox.shrink();
                }

                final gutter = SonusTheme.of(context).metrics.pageGutter;

                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey<String>('album-profile-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    // The bottom inset keeps the last track clear of
                    // anything anchored at the bottom of the app, such as
                    // a persistent mini-player that reserves its space.
                    padding: EdgeInsets.only(
                      bottom: 32 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      _AlbumHero(
                        album: album,
                        controller: controller,
                        artworkPath: _presentationArtworkPath(controller),
                        atmosphere: atmosphere,
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (controller.editions.length > 1) ...[
                              _EditionSelector(
                                controller: controller,
                                atmosphere: atmosphere,
                              ),
                              const SizedBox(height: 18),
                            ],
                            _PlaybackControls(
                              controller: controller,
                              atmosphere: atmosphere,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      _TracksSection(
                        atmosphere: atmosphere,
                        count: controller.tracks
                            .where(_hasAvailableMedia)
                            .length,
                        child: _TracksList(
                          controller: controller,
                          canEditTrack: controller.canEditTrack(userId),
                          canSetBlocked: controller.canSetTrackBlocked(userId),
                          onEditTrack: (track) =>
                              _editTrack(controller, track, userId),
                          onChangeArtwork: (track) =>
                              _changeTrackArtwork(controller, track),
                          onClearArtwork: (track) =>
                              _clearTrackArtwork(controller, track),
                          onSetBlocked: (track, isBlocked) => _setTrackBlocked(
                            controller,
                            track,
                            userId,
                            isBlocked,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _handleAlbumAction(
    AlbumProfileController controller,
    _AlbumMenuAction action,
    String? userId,
  ) async {
    if (action == _AlbumMenuAction.studio) {
      await _openAlbumStudio(controller, userId);
      return;
    }
    if (action == _AlbumMenuAction.editProfile) {
      await _editAlbumProfile(controller, userId);
      return;
    }

    await _handleArtworkAction(controller, action);
  }

  Future<void> _openAlbumStudio(
    AlbumProfileController controller,
    String? userId,
  ) async {
    if (!controller.canEditAlbumStudio(userId) &&
        !controller.canEditAlbumProfile(userId) &&
        !controller.canEditArtwork) {
      return;
    }

    final coverArtCandidateDiscoveryService = context
        .read<CoverArtCandidateDiscoveryService?>();
    final coverArtAlbumEditionImportService = context
        .read<CoverArtAlbumEditionImportService?>();
    final metadataProvider = context.read<MetadataProvider?>();
    final externalMetadataApplicationService = context
        .read<ExternalMetadataApplicationService?>();
    final externalMetadataProposalService = context
        .read<ExternalMetadataProposalService?>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) {
          return AlbumStudioPage(
            controller: controller,
            userId: userId,
            metadataProvider: metadataProvider,
            coverArtAlbumEditionImportService:
                coverArtAlbumEditionImportService,
            coverArtCandidateDiscoveryService:
                coverArtCandidateDiscoveryService,
            externalMetadataApplicationService:
                externalMetadataApplicationService,
            externalMetadataProposalService: externalMetadataProposalService,
            onEditDetails: controller.canEditAlbumProfile(userId)
                ? () => _editAlbumProfile(controller, userId)
                : null,
            onChangeArtwork: controller.canEditArtwork
                ? () => _handleArtworkAction(
                    controller,
                    _AlbumMenuAction.changeArtwork,
                  )
                : null,
            onClearArtwork: controller.canEditArtwork
                ? () => _handleArtworkAction(
                    controller,
                    _AlbumMenuAction.clearArtwork,
                  )
                : null,
          );
        },
      ),
    );
  }

  Future<void> _editAlbumProfile(
    AlbumProfileController controller,
    String? userId,
  ) async {
    final album = controller.album;
    final repository = _repository;

    if (album == null ||
        repository == null ||
        !controller.canEditAlbumProfile(userId)) {
      return;
    }

    try {
      final artists = await repository.getArtists();

      if (!mounted) {
        return;
      }

      final draft = await showDialog<AlbumProfileEditDraft>(
        context: context,
        builder: (dialogContext) {
          return AlbumProfileEditDialog(album: album, artists: artists);
        },
      );

      if (!mounted || draft == null) {
        return;
      }

      final changed = await controller.updateProfile(
        userId: userId,
        title: draft.title,
        editionTitle: draft.editionTitle,
        editionType: draft.editionType,
        releaseDate: draft.releaseDate,
        genre: draft.genre,
        artistId: draft.artistId,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Album details updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album details.')),
      );
    }
  }

  Future<void> _handleArtworkAction(
    AlbumProfileController controller,
    _AlbumMenuAction action,
  ) async {
    try {
      final changed = switch (action) {
        _AlbumMenuAction.studio => false,
        _AlbumMenuAction.editProfile => false,
        _AlbumMenuAction.changeArtwork => await controller.changeArtwork(),
        _AlbumMenuAction.clearArtwork => await controller.clearArtwork(),
      };

      if (!mounted || !changed) {
        return;
      }

      final message = switch (action) {
        _AlbumMenuAction.studio => '',
        _AlbumMenuAction.editProfile => '',
        _AlbumMenuAction.changeArtwork => 'Album artwork updated.',
        _AlbumMenuAction.clearArtwork => 'Album artwork cleared.',
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album artwork.')),
      );
    }
  }

  Future<void> _editTrack(
    AlbumProfileController controller,
    LibraryTrack track,
    String? userId,
  ) async {
    try {
      final repository = _repository;

      if (repository == null) {
        return;
      }

      final artists = await repository.getArtists();
      final albums = await repository.getAlbums();
      final structuredCredits = await controller.getTrackAdditionalCredits(
        track.songId,
      );

      if (!mounted) {
        return;
      }

      final initialAdditionalCredits = structuredCredits
          .map(
            (credit) => TrackProfileCreditDraft(
              creditedName: credit.creditedName,
              role: credit.role,
              artistId: credit.artistId,
            ),
          )
          .toList(growable: false);
      final metadataProvider = context.read<MetadataProvider?>();
      final externalMetadataApplicationService = context
          .read<ExternalMetadataApplicationService?>();
      final externalMetadataProposalService = context
          .read<ExternalMetadataProposalService?>();

      final draft = await Navigator.of(context).push<TrackProfileEditDraft>(
        MaterialPageRoute<TrackProfileEditDraft>(
          builder: (routeContext) {
            return TrackStudioPage(
              track: track,
              userId: userId,
              metadataProvider: metadataProvider,
              externalMetadataApplicationService:
                  externalMetadataApplicationService,
              externalMetadataProposalService: externalMetadataProposalService,
              onMetadataApplied: controller.refresh,
              artists: artists,
              albums: albums,
              initialAdditionalCredits: initialAdditionalCredits,
              canEditDetails: controller.canEditTrack(userId),
              onChangeArtwork: controller.canEditTrackArtwork
                  ? () => _changeTrackArtwork(controller, track)
                  : null,
              onClearArtwork: controller.canEditTrackArtwork
                  ? () => _clearTrackArtwork(controller, track)
                  : null,
            );
          },
        ),
      );

      if (!mounted || draft == null) {
        return;
      }

      final changed = await controller.updateTrackWithCredits(
        userId: userId,
        track: track,
        title: draft.title,
        trackNumber: draft.trackNumber,
        discNumber: draft.discNumber,
        additionalCredits: draft.additionalCredits.map(
          (credit) => SongArtistCreditInput(
            creditedName: credit.creditedName,
            role: credit.role,
            artistId: credit.artistId,
          ),
        ),
        isSingle: draft.isSingle,
        versionLabel: draft.versionLabel,
        versionCharacteristics: draft.versionCharacteristics,
        releaseStatus: draft.releaseStatus,
        isLeak: draft.isLeak,
        artistId: draft.artistId,
        albumId: draft.albumId,
        albumEditionId: draft.albumEditionId,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song details updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song details.')),
      );
    }
  }

  Future<void> _setTrackBlocked(
    AlbumProfileController controller,
    LibraryTrack track,
    String? userId,
    bool isBlocked,
  ) async {
    if (!controller.canSetTrackBlocked(userId)) {
      return;
    }

    try {
      final changed = await controller.setTrackBlocked(
        userId: userId,
        track: track,
        isBlocked: isBlocked,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBlocked ? 'Song blacklisted.' : 'Removed from blacklist.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update blacklist.')),
      );
    }
  }

  Future<void> _changeTrackArtwork(
    AlbumProfileController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.changeTrackArtwork(track);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  Future<void> _clearTrackArtwork(
    AlbumProfileController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.clearTrackArtwork(track);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork cleared.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }
}

/// Text scale above which rows and controls switch to their large-text
/// layout, as in the shared Sonus data components.
const double _largeTextScale = 1.3;

bool _hasAvailableMedia(LibraryTrack track) {
  return track.isAvailable &&
      track.filePath != null &&
      track.filePath!.trim().isNotEmpty;
}

/// Artwork, title, artist, edition and release details, on a background
/// that flows from the artwork's tint into the page.
class _AlbumHero extends StatelessWidget {
  const _AlbumHero({
    required this.album,
    required this.controller,
    required this.artworkPath,
    required this.atmosphere,
  });

  final LibraryAlbum album;
  final AlbumProfileController controller;
  final String? artworkPath;
  final SonusAtmosphereColors atmosphere;

  /// Page width from which the artwork sits beside the details
  /// (landscape and tablets), keeping the track list in view.
  static const double wideLayoutWidth = 560;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        // Both ends keep text readable (the atmosphere guarantees it), so
        // every blend between them does too.
        gradient: atmosphere.isTinted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [atmosphere.surface, atmosphere.background],
              )
            : null,
        color: atmosphere.isTinted ? null : atmosphere.background,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.metrics.pageGutter,
          12,
          tokens.metrics.pageGutter,
          20,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final glow = atmosphere.isTinted && tokens.decoration.allowGlow
                ? atmosphere.accent
                : null;

            if (constraints.maxWidth >= wideLayoutWidth) {
              final size = (constraints.maxWidth * 0.3).clamp(140.0, 220.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _AlbumArtwork(
                    album: album,
                    artworkPath: artworkPath,
                    size: size,
                    glow: glow,
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: _details(context, centered: false)),
                ],
              );
            }

            final size = (constraints.maxWidth * 0.66).clamp(140.0, 264.0);
            return Column(
              children: [
                _AlbumArtwork(
                  album: album,
                  artworkPath: artworkPath,
                  size: size,
                  glow: glow,
                ),
                const SizedBox(height: 20),
                _details(context, centered: true),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _details(BuildContext context, {required bool centered}) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final metadata = _metadata(album);
    final edition = controller.selectedEdition;
    const tabular = [FontFeature.tabularFigures()];
    final align = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          _presentationAlbumTitle(album, edition),
          key: ValueKey<String>('album-profile-title-${album.albumId}'),
          textAlign: align,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          album.artistName,
          key: ValueKey<String>('album-profile-artist-${album.artistId}'),
          textAlign: align,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (edition != null) ...[
          const SizedBox(height: 10),
          _EditionBadge(
            label: _editionDisplayLabel(edition),
            atmosphere: atmosphere,
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _summary(),
          key: const ValueKey<String>('album-profile-summary'),
          textAlign: align,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontFeatures: tabular,
          ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            metadata,
            key: const ValueKey<String>('album-profile-metadata'),
            textAlign: align,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontFeatures: tabular,
            ),
          ),
        ],
      ],
    );
  }

  String _summary() {
    final visibleTracks = controller.tracks
        .where(_hasAvailableMedia)
        .toList(growable: false);

    final trackCount = visibleTracks.length;
    final trackLabel = trackCount == 1 ? 'track' : 'tracks';

    final totalDuration = Duration(
      seconds: visibleTracks.fold<int>(
        0,
        (total, track) => total + track.durationSeconds,
      ),
    );

    final runtime = _formatRuntime(totalDuration);

    if (runtime.isEmpty) {
      return '$trackCount $trackLabel';
    }

    return '$trackCount $trackLabel • $runtime';
  }

  String _metadata(LibraryAlbum album) {
    final parts = <String>[];
    final selectedEdition = controller.selectedEdition;

    final releaseDate = selectedEdition?.releaseDate ?? album.releaseDate;

    if (releaseDate != null) {
      parts.add(_formatDate(releaseDate));
    }

    final genre = (selectedEdition?.genre ?? album.genre)?.trim();

    if (genre != null && genre.isNotEmpty) {
      parts.add(genre);
    }

    if (selectedEdition == null) {
      if (controller.hasMultipleEditions) {
        parts.add('${controller.editionCount} editions');
      } else {
        final editionTitle = album.primaryEditionTitle?.trim();

        if (editionTitle != null &&
            editionTitle.isNotEmpty &&
            editionTitle.toLowerCase() != 'standard') {
          parts.add(editionTitle);
        }
      }
    }

    return parts.join(' • ');
  }

  String _formatRuntime(Duration duration) {
    final totalMinutes = duration.inMinutes;

    if (totalMinutes <= 0) {
      return '';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours == 0) {
      return '$minutes min';
    }

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }
}

/// The selected edition's name, outlined in the album's accent.
class _EditionBadge extends StatelessWidget {
  const _EditionBadge({required this.label, required this.atmosphere});

  final String label;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: atmosphere.accent),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          label,
          key: const ValueKey<String>('album-profile-selected-edition-label'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: tokens.colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({
    required this.album,
    required this.artworkPath,
    required this.size,
    this.glow,
  });

  final LibraryAlbum album;
  final String? artworkPath;
  final double size;

  /// A soft glow in the artwork's accent, only with decoration effects on.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath;
    final glow = this.glow;
    // Decoded at its display size, never at the cover's full resolution.
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          SonusTheme.of(context).metrics.artworkRadius,
        ),
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow.withValues(alpha: 0.32),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
              ],
      ),
      child: SonusArtworkFrame(
        key: ValueKey<String>('album-profile-artwork-${album.albumId}'),
        size: size,
        child: path == null
            ? const _ArtworkFallback()
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: cacheSize,
                // Keeps the previous edition's cover until the next one is
                // ready, so switching editions never flashes empty.
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return const _ArtworkFallback();
                },
              ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return ColoredBox(
      key: const ValueKey<String>('album-profile-artwork-fallback'),
      color: colors.artworkPlaceholder,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.5,
          heightFactor: 0.5,
          child: FittedBox(
            child: Icon(
              Icons.album_rounded,
              color: colors.onArtworkPlaceholder,
            ),
          ),
        ),
      ),
    );
  }
}

/// Switches between the album's real editions. Only shown when two or more
/// exist; the options come from the album's data and nothing else.
///
/// A segmented control when every edition fits on one line, otherwise
/// wrapping choices, so long edition titles are never clipped or hidden off
/// screen.
class _EditionSelector extends StatelessWidget {
  const _EditionSelector({required this.controller, required this.atmosphere});

  final AlbumProfileController controller;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final selectedEdition = controller.selectedEdition;
    final editions = controller.editions;

    if (selectedEdition == null || editions.length < 2) {
      return const SizedBox.shrink();
    }

    final labels = [
      for (final edition in editions) _editionDisplayLabel(edition),
    ];

    return Semantics(
      container: true,
      label: 'Album edition',
      child: LayoutBuilder(
        key: const ValueKey<String>('album-profile-edition-selector'),
        builder: (context, constraints) {
          if (_fitsOnOneLine(context, labels, constraints.maxWidth)) {
            return Center(
              // Its own scroll storage: without it, this horizontal
              // scroller shares the page list's slot and reopens at the
              // page's vertical offset.
              child: KeyedSubtree(
                key: const PageStorageKey<String>(
                  'album-profile-edition-selector-scroll',
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SonusSegmentedSelector<String>(
                    key: const ValueKey<String>(
                      'album-profile-edition-segmented-button',
                    ),
                    segments: [
                      for (final (index, edition) in editions.indexed)
                        SonusSegment<String>(
                          value: edition.editionId,
                          label: labels[index],
                        ),
                    ],
                    selected: selectedEdition.editionId,
                    selectedBackgroundColor: atmosphere.accent,
                    selectedForegroundColor: atmosphere.onAccent,
                    onChanged: _select,
                  ),
                ),
              ),
            );
          }

          return _EditionChoices(
            editions: editions,
            labels: labels,
            selectedId: selectedEdition.editionId,
            maxWidth: constraints.maxWidth,
            atmosphere: atmosphere,
            onSelected: _select,
          );
        },
      ),
    );
  }

  void _select(String editionId) {
    if (editionId == controller.selectedEdition?.editionId) return;
    unawaited(controller.selectEdition(editionId));
  }

  /// Whether a segmented control holding [labels] fits in [maxWidth]. Its
  /// segments share the widest label's width, plus padding and the
  /// selected checkmark.
  static bool _fitsOnOneLine(
    BuildContext context,
    List<String> labels,
    double maxWidth,
  ) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    const segmentChrome = 24 + 26 + 2; // padding, checkmark, border
    return (widest + segmentChrome) * labels.length <= maxWidth;
  }
}

class _EditionChoices extends StatelessWidget {
  const _EditionChoices({
    required this.editions,
    required this.labels,
    required this.selectedId,
    required this.maxWidth,
    required this.atmosphere,
    required this.onSelected,
  });

  final List<LibraryAlbumEdition> editions;
  final List<String> labels;
  final String selectedId;
  final double maxWidth;
  final SonusAtmosphereColors atmosphere;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    return Wrap(
      key: const ValueKey<String>('album-profile-edition-choices'),
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, edition) in editions.indexed)
          () {
            final selected = edition.editionId == selectedId;
            return ChoiceChip(
              key: ValueKey<String>(
                'album-profile-edition-choice-${edition.editionId}',
              ),
              label: ConstrainedBox(
                // Long titles wrap inside the chip instead of clipping.
                constraints: BoxConstraints(maxWidth: maxWidth - 64),
                // Chips force their label onto one line; a fresh text
                // style without a line limit lets long titles wrap fully.
                child: Builder(
                  builder: (context) => DefaultTextStyle(
                    style: DefaultTextStyle.of(context).style,
                    child: Text(labels[index]),
                  ),
                ),
              ),
              selected: selected,
              showCheckmark: true,
              checkmarkColor: selected
                  ? atmosphere.onAccent
                  : colors.textPrimary,
              selectedColor: atmosphere.accent,
              backgroundColor: Colors.transparent,
              labelStyle: TextStyle(
                color: selected ? atmosphere.onAccent : colors.textPrimary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
              side: BorderSide(
                color: selected ? atmosphere.accent : colors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  tokens.metrics.controlRadius,
                ),
              ),
              onSelected: (_) => onSelected(edition.editionId),
            );
          }(),
      ],
    );
  }
}

String? _presentationArtworkPath(AlbumProfileController controller) {
  final editionPath = controller.selectedEdition?.artworkPath?.trim();

  if (editionPath != null && editionPath.isNotEmpty) {
    return editionPath;
  }

  return controller.artworkPath;
}

String _presentationAlbumTitle(
  LibraryAlbum album,
  LibraryAlbumEdition? edition,
) {
  if (edition == null) {
    return album.title;
  }

  final editionTitle = edition.title.trim();

  if (editionTitle.isEmpty || _isGenericEditionTitle(editionTitle)) {
    return album.title;
  }

  return editionTitle;
}

String _editionDisplayLabel(LibraryAlbumEdition edition) {
  final title = edition.title.trim();

  if (title.isNotEmpty && _isGenericEditionTitle(title)) {
    return title;
  }

  return switch (edition.type) {
    AlbumEditionType.standard => 'Standard',
    AlbumEditionType.deluxe => 'Deluxe',
    AlbumEditionType.expanded => 'Expanded',
    AlbumEditionType.anniversary => 'Anniversary',
    AlbumEditionType.remaster => 'Remaster',
    AlbumEditionType.other => title.isEmpty ? 'Other' : title,
  };
}

bool _isGenericEditionTitle(String title) {
  return switch (title.trim().toLowerCase()) {
    'standard' ||
    'deluxe' ||
    'expanded' ||
    'anniversary' ||
    'remaster' ||
    'other' => true,
    _ => false,
  };
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller, required this.atmosphere});

  final AlbumProfileController controller;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          key: const ValueKey<String>('album-profile-shuffle-button'),
          tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
          isSelected: controller.isShuffleEnabled,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            foregroundColor: colors.textPrimary,
            side: BorderSide(
              color: controller.isShuffleEnabled
                  ? atmosphere.accent
                  : colors.border,
            ),
            shape: shape,
          ),
          onPressed: controller.hasPlayableTracks
              ? () {
                  unawaited(controller.toggleShuffle());
                }
              : null,
          icon: Icon(
            controller.isShuffleEnabled
                ? Icons.shuffle_on_rounded
                : Icons.shuffle_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FilledButton.icon(
            key: const ValueKey<String>('album-profile-play-all-button'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(132, 48),
              backgroundColor: atmosphere.accent,
              foregroundColor: atmosphere.onAccent,
              shape: shape,
            ),
            onPressed: controller.hasPlayableTracks
                ? () {
                    unawaited(controller.playAll());
                  }
                : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
          ),
        ),
      ],
    );
  }
}

/// The track list's tinted surface, continuing the artwork's atmosphere
/// below the controls.
class _TracksSection extends StatelessWidget {
  const _TracksSection({
    required this.atmosphere,
    required this.count,
    required this.child,
  });

  final SonusAtmosphereColors atmosphere;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final gutter = tokens.metrics.pageGutter;

    return Material(
      key: const ValueKey<String>('album-profile-tracks-section'),
      // A Material, so row ripples show on the tinted surface.
      color: atmosphere.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.metrics.cardRadius + 8),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Tracks',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _TracksList extends StatelessWidget {
  const _TracksList({
    required this.controller,
    required this.canEditTrack,
    required this.canSetBlocked,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final AlbumProfileController controller;
  final bool canEditTrack;
  final bool canSetBlocked;
  final Future<void> Function(LibraryTrack track) onEditTrack;
  final Future<void> Function(LibraryTrack track) onChangeArtwork;
  final Future<void> Function(LibraryTrack track) onClearArtwork;
  final Future<void> Function(LibraryTrack track, bool isBlocked) onSetBlocked;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks
        .where(
          (track) =>
              track.isAvailable &&
              track.filePath != null &&
              track.filePath!.trim().isNotEmpty,
        )
        .toList(growable: false);

    if (tracks.isEmpty) {
      return const _EmptySection(message: 'No tracks yet');
    }

    // Disc headings only when the edition really spans several discs. They
    // follow the list's existing order; nothing is re-sorted here.
    final multiDisc =
        tracks.map((track) => track.discNumber).toSet().length > 1;

    return Column(
      key: const ValueKey<String>('album-profile-tracks-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, track) in tracks.indexed) ...[
          if (multiDisc &&
              (index == 0 || tracks[index - 1].discNumber != track.discNumber))
            _DiscHeading(disc: track.discNumber, index: index),
          _TrackTile(
            track: track,
            selectedEditionTitle: controller.selectedEdition?.title,
            isPlayable: controller.isTrackPlayable(track),
            canEditArtwork: controller.canEditTrackArtwork,
            canEditTrack: canEditTrack,
            canSetBlocked: canSetBlocked,
            onPlay: () => controller.playTrack(track),
            onPlayNext: () => controller.playNext(track),
            onAddToQueue: () => controller.addToQueue(track),
            onAddToPlaylist: () => showAddToPlaylistFlow(context, track),
            onEditTrack: () => onEditTrack(track),
            onChangeArtwork: () => onChangeArtwork(track),
            onClearArtwork: () => onClearArtwork(track),
            onSetBlocked: (isBlocked) => onSetBlocked(track, isBlocked),
          ),
        ],
      ],
    );
  }
}

class _DiscHeading extends StatelessWidget {
  const _DiscHeading({required this.disc, required this.index});

  final int disc;

  /// Position in the list, so a disc that appears twice keeps unique keys.
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          'Disc $disc',
          key: ValueKey<String>('album-profile-disc-heading-$index'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    this.selectedEditionTitle,
    required this.isPlayable,
    required this.canEditArtwork,
    required this.canEditTrack,
    required this.canSetBlocked,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final LibraryTrack track;

  /// The edition on screen; a row names its edition only when it differs.
  final String? selectedEditionTitle;
  final bool isPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;
  final bool canSetBlocked;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onAddToPlaylist;
  final Future<void> Function() onEditTrack;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;
  final Future<void> Function(bool isBlocked) onSetBlocked;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    // Above 1.3x text the duration moves onto the credit line, so the title
    // keeps enough width to wrap between words, not inside them.
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > _largeTextScale;
    final duration = _formatDuration(track.durationSeconds);

    return ListTile(
      key: ValueKey<String>('album-track-${track.songId}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      enabled: isPlayable,
      textColor: colors.textPrimary,
      iconColor: colors.textSecondary,
      // At least 28px, growing with the text, so "10" never wraps.
      leading: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.textScalerOf(context).scale(28),
        ),
        child: Text(
          '${track.trackNumber}',
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
            fontFeatures: tabular,
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: largeText ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: _subtitle(track, colors, duration: largeText ? duration : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!largeText)
            Text(
              duration,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontFeatures: tabular,
              ),
            ),
          PopupMenuButton<_TrackMenuAction>(
            key: ValueKey<String>('album-track-menu-${track.songId}'),
            enabled:
                isPlayable || canEditArtwork || canEditTrack || canSetBlocked,
            onSelected: (action) {
              switch (action) {
                case _TrackMenuAction.playNext:
                  unawaited(onPlayNext());
                case _TrackMenuAction.addToQueue:
                  unawaited(onAddToQueue());
                case _TrackMenuAction.addToPlaylist:
                  unawaited(onAddToPlaylist());
                case _TrackMenuAction.trackStudio:
                  unawaited(onEditTrack());
                case _TrackMenuAction.toggleBlocked:
                  unawaited(onSetBlocked(!track.isSongBlocked));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _TrackMenuAction.playNext,
                enabled: isPlayable,
                child: const ListTile(
                  leading: Icon(Icons.skip_next_rounded),
                  title: Text('Play next'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.addToQueue,
                enabled: isPlayable,
                child: const ListTile(
                  leading: Icon(Icons.queue_music_rounded),
                  title: Text('Add to queue'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.addToPlaylist,
                child: const ListTile(
                  leading: Icon(Icons.playlist_add_rounded),
                  title: Text('Add to playlist'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.trackStudio,
                enabled: canEditTrack || canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Track Studio'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.toggleBlocked,
                enabled: canSetBlocked,
                child: ListTile(
                  leading: Icon(
                    track.isSongBlocked
                        ? Icons.lock_open_rounded
                        : Icons.block_rounded,
                  ),
                  title: Text(
                    track.isSongBlocked
                        ? 'Remove from blacklist'
                        : 'Blacklist song',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
            ],
          ),
        ],
      ),
      onTap: isPlayable
          ? () {
              unawaited(onPlay());
            }
          : null,
    );
  }

  Widget? _subtitle(
    LibraryTrack track,
    SonusColors colors, {
    String? duration,
  }) {
    final parts = <String>[?duration];

    if (track.isBlocked) {
      parts.add('Blacklisted');
    } else if (!track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty) {
      parts.add('Unavailable');
    }

    if (track.featuredArtists.isNotEmpty) {
      parts.add('feat. ${track.featuredArtists.join(', ')}');
    }

    final editionTitle = track.albumEditionTitle.trim();
    final onScreen = selectedEditionTitle?.trim().toLowerCase();

    if (editionTitle.isNotEmpty &&
        editionTitle.toLowerCase() != 'standard' &&
        editionTitle.toLowerCase() != onScreen) {
      parts.add(editionTitle);
    }

    if (parts.isEmpty) {
      return null;
    }

    return Text(
      parts.join(' \u2022 '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:'
        '${remainder.toString().padLeft(2, '0')}';
  }
}

enum _AlbumMenuAction { studio, editProfile, changeArtwork, clearArtwork }

enum _TrackMenuAction {
  playNext,
  addToQueue,
  addToPlaylist,
  trackStudio,
  toggleBlocked,
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SonusTheme.of(context).colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AlbumProfileLoadError extends StatelessWidget {
  const _AlbumProfileLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: SonusTheme.of(context).colors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load this album.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumNotFound extends StatelessWidget {
  const _AlbumNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.album_outlined,
              size: 48,
              color: SonusTheme.of(context).colors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text('Album not found', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
