import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/library_track_order.dart';
import '../../../search/application/models/library_search_results.dart';
import '../mappers/library_album_row_mapper.dart';
import '../mappers/library_artist_row_mapper.dart';
import '../mappers/library_track_row_mapper.dart';

class LibraryQueryDao {
  const LibraryQueryDao(this.db);

  final DatabaseExecutor db;

  Future<List<LibraryTrack>> findTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    final rows = await db.rawQuery('''
      SELECT
        s.id AS song_id,
        s.title AS song_title,
        s.artist_id AS artist_id,
        ar.name AS artist_name,
        s.album_id AS album_id,
        al.title AS album_title,
        s.album_edition_id AS album_edition_id,
        ae.title AS album_edition_title,
        ae.type AS edition_type,
        s.track_number AS track_number,
        s.disc_number AS disc_number,
        s.duration_seconds AS duration_seconds,
        s.is_single AS is_single,
        s.featured_artists AS featured_artists,
        s.created_at AS created_at,
        m.file_path AS file_path,
        COALESCE(m.is_available, 0) AS is_available,
        COALESCE(sa.id, ea.id) AS artwork_id,
        COALESCE(sa.file_path, ea.file_path) AS artwork_path
      FROM ${DatabaseTables.songs} s
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = s.artist_id
      INNER JOIN ${DatabaseTables.albums} al
        ON al.id = s.album_id
      INNER JOIN ${DatabaseTables.albumEditions} ae
        ON ae.id = s.album_edition_id
      LEFT JOIN ${DatabaseTables.artworkAssets} sa
        ON sa.id = s.artwork_id
      LEFT JOIN ${DatabaseTables.artworkAssets} ea
        ON ea.id = ae.artwork_id
      LEFT JOIN ${DatabaseTables.mediaFileBindings} m
        ON m.id = (
          SELECT mb.id
          FROM ${DatabaseTables.mediaFileBindings} mb
          WHERE mb.song_id = s.id
          ORDER BY mb.is_available DESC, mb.created_at ASC, mb.id ASC
          LIMIT 1
        )
      ORDER BY ${_trackOrderBy(order)}
    ''');

    return rows.map(LibraryTrackRowMapper.fromRow).toList(growable: false);
  }

  Future<LibraryTrack?> findTrackById(String songId) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id AS song_id,
        s.title AS song_title,
        s.artist_id AS artist_id,
        ar.name AS artist_name,
        s.album_id AS album_id,
        al.title AS album_title,
        s.album_edition_id AS album_edition_id,
        ae.title AS album_edition_title,
        ae.type AS edition_type,
        s.track_number AS track_number,
        s.disc_number AS disc_number,
        s.duration_seconds AS duration_seconds,
        s.is_single AS is_single,
        s.featured_artists AS featured_artists,
        s.created_at AS created_at,
        m.file_path AS file_path,
        COALESCE(m.is_available, 0) AS is_available,
        COALESCE(sa.id, ea.id) AS artwork_id,
        COALESCE(sa.file_path, ea.file_path) AS artwork_path
      FROM ${DatabaseTables.songs} s
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = s.artist_id
      INNER JOIN ${DatabaseTables.albums} al
        ON al.id = s.album_id
      INNER JOIN ${DatabaseTables.albumEditions} ae
        ON ae.id = s.album_edition_id
      LEFT JOIN ${DatabaseTables.artworkAssets} sa
        ON sa.id = s.artwork_id
      LEFT JOIN ${DatabaseTables.artworkAssets} ea
        ON ea.id = ae.artwork_id
      LEFT JOIN ${DatabaseTables.mediaFileBindings} m
        ON m.id = (
          SELECT mb.id
          FROM ${DatabaseTables.mediaFileBindings} mb
          WHERE mb.song_id = s.id
          ORDER BY mb.is_available DESC, mb.created_at ASC, mb.id ASC
          LIMIT 1
        )
      WHERE s.id = ?
      LIMIT 1
      ''',
      [songId],
    );

    if (rows.isEmpty) {
      return null;
    }

    return LibraryTrackRowMapper.fromRow(rows.single);
  }

  Future<List<LibraryAlbum>> findAlbums() async {
    final rows = await db.rawQuery('''
      SELECT
        al.id AS album_id,
        al.title AS album_title,
        al.artist_id AS artist_id,
        ar.name AS artist_name,
        pe.id AS primary_edition_id,
        pe.title AS primary_edition_title,
        pe.type AS primary_edition_type,
        pe.release_date AS release_date,
        pe.genre AS genre,
        pa.id AS artwork_id,
        pa.file_path AS artwork_path,
        COUNT(DISTINCT s.id) AS track_count,
        al.created_at AS created_at
      FROM ${DatabaseTables.albums} al
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = al.artist_id
      LEFT JOIN ${DatabaseTables.albumEditions} pe
        ON pe.id = (
          SELECT ae.id
          FROM ${DatabaseTables.albumEditions} ae
          WHERE ae.album_id = al.id
            AND ae.is_primary = 1
          ORDER BY
            ae.release_date ASC,
            ae.title COLLATE NOCASE ASC,
            ae.id ASC
          LIMIT 1
        )
      LEFT JOIN ${DatabaseTables.artworkAssets} pa
        ON pa.id = pe.artwork_id
      LEFT JOIN ${DatabaseTables.songs} s
        ON s.album_id = al.id
      GROUP BY
        al.id,
        al.title,
        al.artist_id,
        ar.name,
        pe.id,
        pe.title,
        pe.type,
        pe.release_date,
        pe.genre,
        pa.id,
        pa.file_path,
        al.created_at
      ORDER BY
        al.title COLLATE NOCASE ASC,
        ar.name COLLATE NOCASE ASC,
        al.id ASC
    ''');

    return rows.map(LibraryAlbumRowMapper.fromRow).toList(growable: false);
  }

  Future<List<LibraryTrack>> findRecentlyAddedTracks(int limit) async {
    if (limit <= 0) {
      return const [];
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        s.id AS song_id,
        s.title AS song_title,
        s.artist_id AS artist_id,
        ar.name AS artist_name,
        s.album_id AS album_id,
        al.title AS album_title,
        s.album_edition_id AS album_edition_id,
        ae.title AS album_edition_title,
        ae.type AS edition_type,
        s.track_number AS track_number,
        s.disc_number AS disc_number,
        s.duration_seconds AS duration_seconds,
        s.is_single AS is_single,
        s.featured_artists AS featured_artists,
        s.created_at AS created_at,
        m.file_path AS file_path,
        COALESCE(m.is_available, 0) AS is_available,
        COALESCE(sa.id, ea.id) AS artwork_id,
        COALESCE(sa.file_path, ea.file_path) AS artwork_path
      FROM ${DatabaseTables.songs} s
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = s.artist_id
      INNER JOIN ${DatabaseTables.albums} al
        ON al.id = s.album_id
      INNER JOIN ${DatabaseTables.albumEditions} ae
        ON ae.id = s.album_edition_id
      LEFT JOIN ${DatabaseTables.artworkAssets} sa
        ON sa.id = s.artwork_id
      LEFT JOIN ${DatabaseTables.artworkAssets} ea
        ON ea.id = ae.artwork_id
      LEFT JOIN ${DatabaseTables.mediaFileBindings} m
        ON m.id = (
          SELECT mb.id
          FROM ${DatabaseTables.mediaFileBindings} mb
          WHERE mb.song_id = s.id
          ORDER BY mb.is_available DESC, mb.created_at ASC, mb.id ASC
          LIMIT 1
        )
      ORDER BY
        s.created_at DESC,
        s.title COLLATE NOCASE ASC,
        s.id ASC
      LIMIT ?
      ''',
      [limit],
    );

    return rows.map(LibraryTrackRowMapper.fromRow).toList(growable: false);
  }

  Future<List<LibraryTrack>> findTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id AS song_id,
        s.title AS song_title,
        s.artist_id AS artist_id,
        ar.name AS artist_name,
        s.album_id AS album_id,
        al.title AS album_title,
        s.album_edition_id AS album_edition_id,
        ae.title AS album_edition_title,
        ae.type AS edition_type,
        s.track_number AS track_number,
        s.disc_number AS disc_number,
        s.duration_seconds AS duration_seconds,
        s.is_single AS is_single,
        s.featured_artists AS featured_artists,
        s.created_at AS created_at,
        m.file_path AS file_path,
        COALESCE(m.is_available, 0) AS is_available,
        COALESCE(sa.id, ea.id) AS artwork_id,
        COALESCE(sa.file_path, ea.file_path) AS artwork_path
      FROM ${DatabaseTables.songs} s
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = s.artist_id
      INNER JOIN ${DatabaseTables.albums} al
        ON al.id = s.album_id
      INNER JOIN ${DatabaseTables.albumEditions} ae
        ON ae.id = s.album_edition_id
      LEFT JOIN ${DatabaseTables.artworkAssets} sa
        ON sa.id = s.artwork_id
      LEFT JOIN ${DatabaseTables.artworkAssets} ea
        ON ea.id = ae.artwork_id
      LEFT JOIN ${DatabaseTables.mediaFileBindings} m
        ON m.id = (
          SELECT mb.id
          FROM ${DatabaseTables.mediaFileBindings} mb
          WHERE mb.song_id = s.id
          ORDER BY mb.is_available DESC, mb.created_at ASC, mb.id ASC
          LIMIT 1
        )
      WHERE s.artist_id = ?
      ORDER BY ${_trackOrderBy(order)}
      ''',
      [artistId],
    );

    return rows.map(LibraryTrackRowMapper.fromRow).toList(growable: false);
  }

  Future<List<LibraryTrack>> findTracksByAlbumId(String albumId) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id AS song_id,
        s.title AS song_title,
        s.artist_id AS artist_id,
        ar.name AS artist_name,
        s.album_id AS album_id,
        al.title AS album_title,
        s.album_edition_id AS album_edition_id,
        ae.title AS album_edition_title,
        ae.type AS edition_type,
        s.track_number AS track_number,
        s.disc_number AS disc_number,
        s.duration_seconds AS duration_seconds,
        s.is_single AS is_single,
        s.featured_artists AS featured_artists,
        s.created_at AS created_at,
        m.file_path AS file_path,
        COALESCE(m.is_available, 0) AS is_available,
        COALESCE(sa.id, ea.id) AS artwork_id,
        COALESCE(sa.file_path, ea.file_path) AS artwork_path
      FROM ${DatabaseTables.songs} s
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = s.artist_id
      INNER JOIN ${DatabaseTables.albums} al
        ON al.id = s.album_id
      INNER JOIN ${DatabaseTables.albumEditions} ae
        ON ae.id = s.album_edition_id
      LEFT JOIN ${DatabaseTables.artworkAssets} sa
        ON sa.id = s.artwork_id
      LEFT JOIN ${DatabaseTables.artworkAssets} ea
        ON ea.id = ae.artwork_id
      LEFT JOIN ${DatabaseTables.mediaFileBindings} m
        ON m.id = (
          SELECT mb.id
          FROM ${DatabaseTables.mediaFileBindings} mb
          WHERE mb.song_id = s.id
          ORDER BY mb.is_available DESC, mb.created_at ASC, mb.id ASC
          LIMIT 1
        )
      WHERE s.album_id = ?
      ORDER BY
        ae.is_primary DESC,
        ae.release_date ASC,
        ae.title COLLATE NOCASE ASC,
        s.disc_number ASC,
        s.track_number ASC,
        s.title COLLATE NOCASE ASC,
        s.id ASC
      ''',
      [albumId],
    );

    return rows.map(LibraryTrackRowMapper.fromRow).toList(growable: false);
  }

  Future<List<LibraryAlbum>> findRecentlyAddedAlbums(int limit) async {
    if (limit <= 0) {
      return const [];
    }

    final albums = await findAlbums();

    final sorted = [...albums]
      ..sort((a, b) {
        final createdCompare = b.dateAdded.compareTo(a.dateAdded);

        if (createdCompare != 0) {
          return createdCompare;
        }

        final titleCompare = a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        );

        if (titleCompare != 0) {
          return titleCompare;
        }

        return a.albumId.compareTo(b.albumId);
      });

    return sorted.take(limit).toList(growable: false);
  }

  Future<List<LibraryArtist>> findArtists() async {
    final rows = await db.rawQuery('''
      SELECT
        ar.id AS artist_id,
        ar.name AS artist_name,
        ar.is_blacklisted AS is_blacklisted,
        ar.header_artwork_id AS header_artwork_id,
        ha.file_path AS header_artwork_path,
        ar.top_artists_artwork_id AS top_artists_artwork_id,
        ta.file_path AS top_artists_artwork_path,
        COUNT(DISTINCT al.id) AS album_count,
        COUNT(DISTINCT s.id) AS song_count,
        ar.created_at AS created_at
      FROM ${DatabaseTables.artists} ar
      LEFT JOIN ${DatabaseTables.artworkAssets} ha
        ON ha.id = ar.header_artwork_id
      LEFT JOIN ${DatabaseTables.artworkAssets} ta
        ON ta.id = ar.top_artists_artwork_id
      LEFT JOIN ${DatabaseTables.albums} al
        ON al.artist_id = ar.id
      LEFT JOIN ${DatabaseTables.songs} s
        ON s.artist_id = ar.id
      GROUP BY
        ar.id,
        ar.name,
        ar.header_artwork_id,
        ha.file_path,
        ar.top_artists_artwork_id,
        ta.file_path,
        ar.created_at
      ORDER BY
        ar.name COLLATE NOCASE ASC,
        ar.id ASC
    ''');

    return rows.map(LibraryArtistRowMapper.fromRow).toList(growable: false);
  }

  Future<LibraryAlbum?> findAlbumById(String albumId) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        al.id AS album_id,
        al.title AS album_title,
        al.artist_id AS artist_id,
        ar.name AS artist_name,
        pe.id AS primary_edition_id,
        pe.title AS primary_edition_title,
        pe.type AS primary_edition_type,
        pe.release_date AS release_date,
        pe.genre AS genre,
        pa.id AS artwork_id,
        pa.file_path AS artwork_path,
        COUNT(DISTINCT s.id) AS track_count,
        al.created_at AS created_at
      FROM ${DatabaseTables.albums} al
      INNER JOIN ${DatabaseTables.artists} ar
        ON ar.id = al.artist_id
      LEFT JOIN ${DatabaseTables.albumEditions} pe
        ON pe.id = (
          SELECT ae.id
          FROM ${DatabaseTables.albumEditions} ae
          WHERE ae.album_id = al.id
            AND ae.is_primary = 1
          ORDER BY
            ae.release_date ASC,
            ae.title COLLATE NOCASE ASC,
            ae.id ASC
          LIMIT 1
        )
      LEFT JOIN ${DatabaseTables.artworkAssets} pa
        ON pa.id = pe.artwork_id
      LEFT JOIN ${DatabaseTables.songs} s
        ON s.album_id = al.id
      WHERE al.id = ?
      GROUP BY
        al.id,
        al.title,
        al.artist_id,
        ar.name,
        pe.id,
        pe.title,
        pe.type,
        pe.release_date,
        pe.genre,
        pa.id,
        pa.file_path,
        al.created_at
      LIMIT 1
      ''',
      [albumId],
    );

    if (rows.isEmpty) {
      return null;
    }

    return LibraryAlbumRowMapper.fromRow(rows.single);
  }

  Future<List<LibraryAlbum>> findAlbumsByArtistId(String artistId) async {
    final albums = await findAlbums();

    return albums
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  Future<LibraryArtist?> findArtistById(String artistId) async {
    final artists = await findArtists();

    for (final artist in artists) {
      if (artist.artistId == artistId) {
        return artist;
      }
    }

    return null;
  }

  Future<LibrarySearchResults> search(String query) async {
    final normalizedQuery = _normalizeSearchText(query);

    if (normalizedQuery.isEmpty) {
      return const LibrarySearchResults();
    }

    final results = await Future.wait<Object>([
      findArtists(),
      findAlbums(),
      findTracks(),
    ]);

    final artists =
        (results[0] as List<LibraryArtist>)
            .where(
              (artist) =>
                  _normalizeSearchText(artist.name).contains(normalizedQuery),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _compareSearchCandidates(
              query: normalizedQuery,
              aPrimary: a.name,
              bPrimary: b.name,
              aTieBreaker: a.artistId,
              bTieBreaker: b.artistId,
            ),
          );

    final albums =
        (results[1] as List<LibraryAlbum>)
            .where((album) {
              return _normalizeSearchText(
                    album.title,
                  ).contains(normalizedQuery) ||
                  _normalizeSearchText(
                    album.artistName,
                  ).contains(normalizedQuery);
            })
            .toList(growable: false)
          ..sort(
            (a, b) => _compareSearchCandidates(
              query: normalizedQuery,
              aPrimary: a.title,
              bPrimary: b.title,
              aSecondary: a.artistName,
              bSecondary: b.artistName,
              aTieBreaker: a.albumId,
              bTieBreaker: b.albumId,
            ),
          );

    final tracks =
        (results[2] as List<LibraryTrack>)
            .where((track) {
              if (_normalizeSearchText(track.title).contains(normalizedQuery)) {
                return true;
              }

              if (_normalizeSearchText(
                track.artistName,
              ).contains(normalizedQuery)) {
                return true;
              }

              if (_normalizeSearchText(
                track.albumTitle,
              ).contains(normalizedQuery)) {
                return true;
              }

              return track.featuredArtists.any(
                (artist) =>
                    _normalizeSearchText(artist).contains(normalizedQuery),
              );
            })
            .toList(growable: false)
          ..sort(
            (a, b) => _compareSearchCandidates(
              query: normalizedQuery,
              aPrimary: a.title,
              bPrimary: b.title,
              aSecondary: a.artistName,
              bSecondary: b.artistName,
              aTieBreaker: a.songId,
              bTieBreaker: b.songId,
            ),
          );

    return LibrarySearchResults(
      artists: artists,
      albums: albums,
      tracks: tracks,
    );
  }

  static int _compareSearchCandidates({
    required String query,
    required String aPrimary,
    required String bPrimary,
    String? aSecondary,
    String? bSecondary,
    required String aTieBreaker,
    required String bTieBreaker,
  }) {
    final aRank = _searchRank(
      query: query,
      primary: aPrimary,
      secondary: aSecondary,
    );

    final bRank = _searchRank(
      query: query,
      primary: bPrimary,
      secondary: bSecondary,
    );

    final rankCompare = aRank.compareTo(bRank);

    if (rankCompare != 0) {
      return rankCompare;
    }

    final primaryCompare = aPrimary.toLowerCase().compareTo(
      bPrimary.toLowerCase(),
    );

    if (primaryCompare != 0) {
      return primaryCompare;
    }

    final secondaryCompare = (aSecondary ?? '').toLowerCase().compareTo(
      (bSecondary ?? '').toLowerCase(),
    );

    if (secondaryCompare != 0) {
      return secondaryCompare;
    }

    return aTieBreaker.compareTo(bTieBreaker);
  }

  static int _searchRank({
    required String query,
    required String primary,
    String? secondary,
  }) {
    final normalizedPrimary = _normalizeSearchText(primary);
    final normalizedSecondary = _normalizeSearchText(secondary ?? '');

    if (normalizedPrimary == query) {
      return 0;
    }

    if (normalizedPrimary.startsWith(query)) {
      return 1;
    }

    if (normalizedPrimary.contains(query)) {
      return 2;
    }

    if (normalizedSecondary == query) {
      return 3;
    }

    if (normalizedSecondary.startsWith(query)) {
      return 4;
    }

    if (normalizedSecondary.contains(query)) {
      return 5;
    }

    return 6;
  }

  static String _normalizeSearchText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _trackOrderBy(LibraryTrackOrder order) {
    switch (order) {
      case LibraryTrackOrder.title:
        return '''
          s.title COLLATE NOCASE ASC,
          ar.name COLLATE NOCASE ASC,
          s.id ASC
        ''';

      case LibraryTrackOrder.artist:
        return '''
          ar.name COLLATE NOCASE ASC,
          al.title COLLATE NOCASE ASC,
          s.disc_number ASC,
          s.track_number ASC,
          s.title COLLATE NOCASE ASC,
          s.id ASC
        ''';

      case LibraryTrackOrder.dateAdded:
        return '''
          s.created_at DESC,
          s.title COLLATE NOCASE ASC,
          s.id ASC
        ''';
    }
  }
}
