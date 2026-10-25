import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/sonus_count_label.dart';
import '../../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../domain/entities/song_artist_credit.dart';
import '../../models/artist_profile_sections.dart';
import 'artist_profile_header.dart';

/// Everyone credited on this artist's albums, such as a soundtrack or cast
/// album, each once with their role: open their profile, or play the songs
/// they lead here.
class ArtistProfileCollaborators extends StatelessWidget {
  const ArtistProfileCollaborators({
    super.key,
    required this.collaborators,
    required this.isPlayable,
    required this.onOpen,
    required this.onPlay,
    this.tileColor,
  });

  final List<ArtistProfileCollaborator> collaborators;
  final bool Function(ArtistProfileCollaborator collaborator) isPlayable;
  final ValueChanged<ArtistProfileCollaborator> onOpen;
  final Future<void> Function(ArtistProfileCollaborator collaborator) onPlay;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('artist-profile-collaborators-list'),
      children: [
        for (final collaborator in collaborators)
          _CollaboratorTile(
            collaborator: collaborator,
            playable: isPlayable(collaborator),
            tileColor: tileColor,
            onOpen: () => onOpen(collaborator),
            onPlay: () => onPlay(collaborator),
          ),
      ],
    );
  }
}

class _CollaboratorTile extends StatelessWidget {
  const _CollaboratorTile({
    required this.collaborator,
    required this.playable,
    required this.tileColor,
    required this.onOpen,
    required this.onPlay,
  });

  final ArtistProfileCollaborator collaborator;
  final bool playable;
  final Color? tileColor;
  final VoidCallback onOpen;
  final Future<void> Function() onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final count = collaborator.displaySongCount;
    final role = switch (collaborator.leadRole) {
      null => null,
      SongArtistCreditRole.primary => 'Lead',
      SongArtistCreditRole.coPrimary => 'Co-lead',
      SongArtistCreditRole.featured => 'Featured',
      SongArtistCreditRole.guest => 'Guest',
    };
    final songs = sonusCount(count, 'song');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        key: ValueKey<String>('artist-collaborator-${collaborator.artistId}'),
        tileColor: tileColor ?? tokens.colors.surface,
        textColor: tokens.colors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        ),
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        minVerticalPadding: 8,
        leading: _CollaboratorPortrait(collaborator: collaborator, size: 48),
        title: Text(
          collaborator.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          role == null ? songs : '$role · $songs',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        trailing: IconButton(
          key: ValueKey<String>(
            'artist-collaborator-play-${collaborator.artistId}',
          ),
          tooltip: 'Play ${collaborator.name}',
          onPressed: playable
              ? () {
                  unawaited(onPlay());
                }
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _CollaboratorPortrait extends StatelessWidget {
  const _CollaboratorPortrait({required this.collaborator, required this.size});

  final ArtistProfileCollaborator collaborator;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final path = collaborator.artworkPath;
    final fallback = ColoredBox(
      color: colors.artworkPlaceholder,
      child: Center(
        child: Text(
          artistInitials(collaborator.name),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: colors.onArtworkPlaceholder,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    return SonusArtworkFrame(
      size: size,
      circular: true,
      child: path == null
          ? fallback
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              // Decoded at its display size, never at full resolution.
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }
}
