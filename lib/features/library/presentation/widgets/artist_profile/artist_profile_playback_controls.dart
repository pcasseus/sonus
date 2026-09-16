import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/artist_profile_controller.dart';

class ArtistProfilePlaybackControls extends StatelessWidget {
  const ArtistProfilePlaybackControls({super.key, required this.controller});

  final ArtistProfileController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          key: const ValueKey<String>('artist-profile-shuffle-button'),
          tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
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
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play all'),
          ),
        ),
      ],
    );
  }
}
