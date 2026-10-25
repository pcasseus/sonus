import '../../../../core/database/database_tables.dart';
import '../../domain/services/album_edition_track_order.dart';

/// The order of an edition's tracks, shared by every query that lists them.
///
/// An edition someone has deliberately reordered keeps that order
/// (`sort_position`). Every other edition is ordered by disc, then track
/// number, with unknown numbers after the numbered tracks of their disc. The
/// order is computed when read, so libraries imported in file-discovery
/// order list correctly without rewriting anything, and devices never
/// disagree about stored positions.
///
/// [alias] is the `album_edition_tracks` alias in the query. In memory, the
/// same disc-and-track order is [compareByDiscAndTrack].
String editionTrackOrderBy(String alias) {
  return '''
    CASE WHEN EXISTS (
      SELECT 1 FROM ${DatabaseTables.albumEditionTracks} manual_order
      WHERE manual_order.album_edition_id = $alias.album_edition_id
        AND manual_order.ordering_authority = 'manual'
    ) THEN $alias.sort_position ELSE 0 END ASC,
    CASE WHEN $alias.disc_number <= 0 THEN 1 ELSE $alias.disc_number END ASC,
    CASE WHEN $alias.track_number <= 0 THEN 1 ELSE 0 END ASC,
    $alias.track_number ASC,
    $alias.sort_position ASC,
    $alias.song_id ASC''';
}
