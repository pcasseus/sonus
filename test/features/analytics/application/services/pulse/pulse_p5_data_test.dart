import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/listening_artist_attribution.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_entity_directory.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_insights_service.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_pulse_listening_records.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  var n = 0;

  setUp(() async {
    n = 0;
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AnalyticsSchema.create(db),
      ),
    );
  });
  tearDown(() => db.close());

  /// One qualifying 3-minute play.
  Future<void> play(
    DateTime startLocal, {
    required String song,
    required String artist,
    required String album,
    String edition = 'standard',
  }) async {
    final id = 's${n++}';
    final start = startLocal.toUtc();
    final end = start.add(const Duration(minutes: 3));
    await db.insert(DatabaseTables.playbackSessions, {
      'id': id,
      'song_id': song,
      'artist_id': artist,
      'album_id': album,
      'album_edition_id': edition,
      'song_title': 'Title $song',
      'artist_name': 'Name $artist',
      'album_title': 'Album $album',
      'album_edition_title': edition,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'listened_duration_ms': 180000,
      'created_at': start.toIso8601String(),
      'updated_at': start.toIso8601String(),
    });
    await db.insert(DatabaseTables.playbackListeningSegments, {
      'id': 'seg$id',
      'playback_session_id': id,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'listened_duration_ms': 180000,
      'created_at': start.toIso8601String(),
      'updated_at': start.toIso8601String(),
    });
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'q$id',
      'playback_session_id': id,
      'song_id': song,
      'artist_id': artist,
      'album_id': album,
      'album_edition_id': edition,
      'qualified_at': start.add(const Duration(seconds: 30)).toIso8601String(),
      'listened_duration_ms': 30000,
      'track_duration_ms': 180000,
      'created_at': start.toIso8601String(),
    });
  }

  PulseInsightsService service() => PulseInsightsService(
    records: SqlitePulseListeningRecords(db),
    artistAttribution: const _ProjectOwner(),
    nowLocal: () => DateTime(2030),
  );

  Future<void> seed() async {
    // owner: two tracks on the LP (one also played by a contributor),
    // one on an EP. other: one track on the LP (a duet LP shares album).
    for (var i = 0; i < 3; i++) {
      await play(
        DateTime(2026, 10, 2 + i, 9),
        song: 'lp_1',
        artist: 'owner',
        album: 'lp',
      );
    }
    await play(
      DateTime(2026, 10, 5, 9),
      song: 'lp_2',
      artist: 'contributor',
      album: 'lp',
      edition: 'deluxe',
    );
    await play(
      DateTime(2026, 10, 6, 9),
      song: 'ep_1',
      artist: 'owner',
      album: 'ep',
    );
    await play(
      DateTime(2026, 10, 6, 10),
      song: 'ep_1',
      artist: 'owner',
      album: 'ep',
    );
    await play(
      DateTime(2026, 10, 7, 9),
      song: 'other_1',
      artist: 'other',
      album: 'lp',
    );
    // Earlier history for lifetime counts.
    await play(
      DateTime(2025, 3, 1, 9),
      song: 'lp_1',
      artist: 'owner',
      album: 'lp',
      edition: 'deluxe',
    );
  }

  test('an artist\'s tracks, their release contributions, and a release\'s '
      'tracks come from the same plays', () async {
    await seed();
    final data = await service().load(PulsePeriod.month(2026, 10));

    expect(data.artistOfTrack('lp_2'), 'owner', reason: 'contributor → owner');
    expect(
      data
          .tracksOfArtist('owner', PulseMeasure.streams)
          .map((t) => (t.id, t.metrics.streams)),
      [('lp_1', 3), ('ep_1', 2), ('lp_2', 1)],
    );
    final contributions = data.releaseContributionsOf(
      'owner',
      PulseMeasure.streams,
    );
    expect(contributions.map((r) => (r.id, r.metrics.streams)), [
      ('lp', 4),
      ('ep', 2),
    ], reason: 'the owner\'s part of the LP, not the other artist\'s');
    expect(data.totalsFor(PulseEntityKind.release, 'lp').streams, 5);
    expect(data.tracksOfRelease('lp', PulseMeasure.streams).map((t) => t.id), [
      'lp_1',
      'other_1',
      'lp_2',
    ]);
    expect(
      data.tracksOfArtist('owner', PulseMeasure.streams, limit: 1),
      hasLength(1),
    );
  });

  test('lifetime streams cover all history with the same attribution and '
      'count a release across editions', () async {
    await seed();
    final s = service();
    expect(await s.lifetimeStreams(PulseEntityKind.track, 'lp_1'), 4);
    expect(await s.lifetimeStreams(PulseEntityKind.release, 'lp'), 6);
    expect(await s.lifetimeStreams(PulseEntityKind.artist, 'owner'), 7);
    expect(await s.lifetimeStreams(PulseEntityKind.artist, 'contributor'), 0);
    expect(await s.lifetimeStreams(PulseEntityKind.track, 'never'), 0);
  });

  group('directory', () {
    LibraryTrack track(
      String id, {
      bool blocked = false,
      bool available = true,
    }) => LibraryTrack(
      songId: id,
      title: 'Library $id',
      artistId: 'owner',
      artistName: 'Owner Now',
      albumId: 'lp',
      albumTitle: 'LP Now',
      albumEditionId: 'standard',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime(2026),
      isAvailable: available,
      isSongBlocked: blocked,
      filePath: '/music/$id.mp3',
      artworkPath: '/art/$id.jpg',
    );

    test('labels current, blacklisted, unavailable and historical items '
        'and never invents names', () async {
      await seed();
      final data = await service().load(PulsePeriod.month(2026, 10));
      final directory = await PulseEntityDirectoryService(
        library: _Library(
          tracks: [
            track('lp_1'),
            track('lp_2', blocked: true),
            track('ep_1', available: false),
          ],
          artists: [
            LibraryArtist(
              artistId: 'owner',
              name: 'Owner Now',
              albumCount: 2,
              songCount: 3,
              dateAdded: DateTime(2026),
              topArtistsArtworkPath: '/art/owner.jpg',
            ),
          ],
          // Listed under a project: not in getArtists, but findable.
          hidden: [
            LibraryArtist(
              artistId: 'other',
              name: 'Other Now',
              albumCount: 0,
              songCount: 1,
              dateAdded: DateTime(2026),
            ),
          ],
          albums: [
            LibraryAlbum(
              albumId: 'lp',
              title: 'LP Now',
              artistId: 'owner',
              artistName: 'Owner Now',
              trackCount: 3,
              dateAdded: DateTime(2026),
              artworkPath: '/art/lp.jpg',
            ),
          ],
        ),
        playbackSessions: _Sessions(db),
      ).load(data);

      final lp1 = directory.infoFor(PulseEntityKind.track, 'lp_1');
      expect(lp1.title, 'Library lp_1');
      expect(lp1.status, PulseEntityStatus.current);
      expect(lp1.badge, isNull);
      expect(lp1.isPlayable, isTrue);
      expect(lp1.artistId, 'owner');

      expect(
        directory.infoFor(PulseEntityKind.track, 'lp_2').badge,
        'BLACKLISTED',
      );
      expect(
        directory.infoFor(PulseEntityKind.track, 'ep_1').badge,
        'UNAVAILABLE',
      );
      final removed = directory.infoFor(PulseEntityKind.track, 'other_1');
      expect(removed.badge, 'HISTORICAL');
      expect(
        removed.title,
        'Title other_1',
        reason: 'named from its last play',
      );
      expect(removed.isPlayable, isFalse);

      expect(
        directory.infoFor(PulseEntityKind.artist, 'owner').artworkPath,
        '/art/owner.jpg',
      );
      expect(
        directory.infoFor(PulseEntityKind.artist, 'other').status,
        PulseEntityStatus.current,
      );
      expect(
        directory.infoFor(PulseEntityKind.release, 'ep').title,
        'Album ep',
      );
      expect(
        directory.infoFor(PulseEntityKind.release, 'ep').status,
        PulseEntityStatus.historical,
      );
      expect(
        directory.infoFor(PulseEntityKind.track, 'nope').title,
        'Unknown track',
      );

      expect(
        directory
            .playableTracks(['lp_2', 'lp_1', 'ep_1', 'other_1'])
            .map((t) => t.songId),
        ['lp_1'],
        reason: 'blacklisted, unavailable and removed songs never play',
      );
    });
  });
}

class _ProjectOwner implements ListeningArtistAttribution {
  const _ProjectOwner();

  @override
  Future<ArtistAttributor> load() async => ArtistAttributor(
    (artistId, albumId) => artistId == 'contributor' ? 'owner' : artistId,
  );
}

class _Library implements LibraryQueryRepository {
  _Library({
    required this.tracks,
    required this.artists,
    required this.albums,
    this.hidden = const [],
  });

  final List<LibraryTrack> tracks;
  final List<LibraryArtist> artists;
  final List<LibraryArtist> hidden;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => tracks;

  @override
  Future<List<LibraryArtist>> getArtists() async => artists;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async =>
      [...artists, ...hidden].where((a) => a.artistId == artistId).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sessions straight from the test database.
class _Sessions implements PlaybackSessionRepository {
  _Sessions(this.db);

  final Database db;

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    final rows = await db.query(DatabaseTables.playbackSessions);
    return [
      for (final r in rows)
        PlaybackSession(
          id: r['id']! as String,
          songId: r['song_id']! as String,
          artistId: r['artist_id']! as String,
          albumId: r['album_id']! as String,
          albumEditionId: r['album_edition_id']! as String,
          songTitle: r['song_title']! as String,
          artistName: r['artist_name']! as String,
          albumTitle: r['album_title']! as String,
          albumEditionTitle: r['album_edition_title']! as String,
          startedAt: DateTime.parse(r['started_at']! as String),
          listenedDuration: const Duration(minutes: 3),
          trackDuration: const Duration(minutes: 3),
          finalPosition: const Duration(minutes: 3),
          createdAt: DateTime.parse(r['created_at']! as String),
          updatedAt: DateTime.parse(r['updated_at']! as String),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
