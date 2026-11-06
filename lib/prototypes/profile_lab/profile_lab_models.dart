// Artist Profile Lab: the content the prototype page draws.
//
// PROTOTYPE ONLY. Nothing in the app imports lib/prototypes/; the render
// harness in test/visual_lab/ supplies illustrative content. These are plain
// value types, not production models, and carry no statistics of their own.
import 'package:flutter/foundation.dart';

/// One row in the Top Tracks card.
@immutable
class LabTrack {
  const LabTrack({
    required this.title,
    required this.releaseTitle,
    required this.streams,
    this.artworkPath,
    this.isPlaying = false,
  });

  final String title;
  final String releaseTitle;
  final int streams;
  final String? artworkPath;

  /// Shown with the accent and an equaliser mark instead of its number.
  final bool isPlaying;
}

/// One cover in the Releases carousel.
@immutable
class LabRelease {
  const LabRelease({
    required this.title,
    required this.year,
    this.artworkPath,
    this.edition,
  });

  final String title;
  final int year;
  final String? artworkPath;

  /// "Deluxe", "Standard"…; null for none.
  final String? edition;
}

/// One card in the Collaborations row.
@immutable
class LabCollaboration {
  const LabCollaboration({
    required this.partnerName,
    required this.songCount,
    this.partnerPortraitPath,
    this.coverPath,
  });

  final String partnerName;
  final int songCount;
  final String? partnerPortraitPath;
  final String? coverPath;
}

/// Everything the lab page shows for one artist.
@immutable
class LabArtistProfile {
  const LabArtistProfile({
    required this.name,
    required this.streams,
    required this.listened,
    required this.topTracks,
    required this.releases,
    required this.collaborations,
    this.bannerPath,
    this.portraitPath,
    this.standing,
    this.nowPlaying,
  });

  final String name;

  /// The wide photo across the top of the page; the portrait when null.
  final String? bannerPath;
  final String? portraitPath;

  /// "Your #1 artist"; null for none.
  final String? standing;
  final int streams;
  final Duration listened;
  final List<LabTrack> topTracks;
  final List<LabRelease> releases;
  final List<LabCollaboration> collaborations;

  /// Drives the mini-player placeholder; null hides it.
  final LabTrack? nowPlaying;

  /// The artwork the page's atmosphere is drawn from.
  String? get atmospherePath => bannerPath ?? portraitPath;
}
