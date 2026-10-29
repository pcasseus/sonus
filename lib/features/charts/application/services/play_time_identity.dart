import 'dart:developer' as developer;

import '../../../analytics/domain/entities/playback_session.dart';
import '../../../analytics/domain/entities/qualified_play.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
import '../../../library/application/models/library_album.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';

/// Identity as recorded at play time, last play winning. A release is
/// credited to its own artist while it is in the library, never to the
/// artist of a song on it (SN-50 E-Q13).
Map<String, ChartEntitySnapshot> playTimeIdentities({
  required Iterable<QualifiedPlay> plays,
  required Map<String, PlaybackSession> sessionsById,
  required ChartType chartType,
  Map<String, LibraryAlbum> albumsById = const {},
}) {
  final identities = <String, ChartEntitySnapshot>{};

  for (final play in [...plays]..sort(_byQualifiedAt)) {
    final session = sessionsById[play.playbackSessionId]!;

    switch (chartType) {
      case ChartType.songs:
        identities[play.songId] = ChartEntitySnapshot(
          entityId: play.songId,
          title: session.songTitle,
          artistId: session.artistId,
          artistName: session.artistName,
          albumTitle: session.albumTitle,
        );

      case ChartType.albums:
        final album = albumsById[play.albumId];
        identities[play.albumId] = ChartEntitySnapshot(
          entityId: play.albumId,
          title: session.albumTitle,
          artistId: album?.artistId ?? session.artistId,
          artistName: album?.artistName ?? session.artistName,
        );
    }
  }

  return identities;
}

/// Play-time identities for songs and releases the library no longer
/// holds. Their verified listening still counts (SN-50 R1), so they are
/// shown as they were heard. Reads one session per entity: its last play.
///
/// For live views only: an entity whose session record is gone is left out
/// and logged, so one bad record never empties the chart. Finalized weeks
/// stay strict and never use this.
Future<Map<String, ChartEntitySnapshot>> loadPlayTimeIdentities({
  required PlaybackSessionRepository? sessions,
  required Iterable<QualifiedPlay> plays,
  required ChartType chartType,
}) async {
  final lastPlayByEntity = <String, QualifiedPlay>{};
  for (final play in [...plays]..sort(_byQualifiedAt)) {
    lastPlayByEntity[switch (chartType) {
          ChartType.songs => play.songId,
          ChartType.albums => play.albumId,
        }] =
        play;
  }

  if (lastPlayByEntity.isEmpty) return const {};

  if (sessions == null) {
    throw StateError(
      'PlaybackSessionRepository is required to chart entities that are '
      'no longer in the library.',
    );
  }

  final lastPlays = lastPlayByEntity.values.toList(growable: false);
  final sessionsById = {
    for (final session in await sessions.getByIds(
      lastPlays.map((play) => play.playbackSessionId),
    ))
      session.id: session,
  };

  final heardPlays = <QualifiedPlay>[];
  for (final MapEntry(key: entityId, value: play) in lastPlayByEntity.entries) {
    if (sessionsById.containsKey(play.playbackSessionId)) {
      heardPlays.add(play);
      continue;
    }
    developer.log(
      'Left out ${chartType.name} entity $entityId: it is no longer in the '
      'library and its playback session is missing',
      name: 'sonus.charts',
      level: 900,
    );
  }

  return playTimeIdentities(
    plays: heardPlays,
    sessionsById: sessionsById,
    chartType: chartType,
  );
}

int _byQualifiedAt(QualifiedPlay a, QualifiedPlay b) {
  final timeCompare = a.qualifiedAt.toUtc().compareTo(b.qualifiedAt.toUtc());

  return timeCompare != 0 ? timeCompare : a.id.compareTo(b.id);
}
