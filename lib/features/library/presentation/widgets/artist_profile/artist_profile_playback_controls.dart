import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../controllers/artist_profile_controller.dart';

class ArtistProfilePlaybackControls extends StatelessWidget {
  const ArtistProfilePlaybackControls({
    super.key,
    required this.controller,
    required this.atmosphere,
  });

  final ArtistProfileController controller;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      SonusTheme.of(context).metrics.controlRadius,
    );

    return Row(
      children: [
        IconButton.filledTonal(
          key: const ValueKey<String>('artist-profile-shuffle-button'),
          tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
          isSelected: controller.isShuffleEnabled,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey<String>('artist-profile-play-all-button'),
            onPressed: controller.hasPlayableTracks
                ? () {
                    unawaited(controller.playAll());
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: atmosphere.accent,
              foregroundColor: atmosphere.onAccent,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'Play all',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
