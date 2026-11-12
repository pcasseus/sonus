import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_permanent_deletion_impact_repository.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';

/// Synthetic library, never real data:
///
/// - Nova (self-titled release "Nova", Standard + Deluxe):
///   - opening, second: on both editions (home Standard);
///   - bonus: Deluxe only;
///   - duet: performed by Lumen, on Nova's release (shared).
/// - Lumen ("Lights"):
///   - glow: Lumen, featuring Nova (collaboration);
///   - guest: performed by Nova, on Lumen's release (shared).
/// - Echo ("Echoes"): echo; Lumen is grouped under Nova's release as a
///   project.
void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;

  const now = '2026-10-01T12:00:00.000Z';
  const week1 = '2026-10-04T00:00:00.000Z';
  const week1End = '2026-10-11T00:00:00.000Z';

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    await _seed(db, now: now, week: week1, weekEnd: week1End);
  });

  tearDown(() async => appDatabase.close());

  Future<PermanentDeletionImpact> plan(
    PermanentDeletionTarget target, {
    bool includeShared = false,
  }) => SqlitePermanentDeletionImpactRepository(db).plan(
    target,
    options: PermanentDeletionOptions(includeSharedRecordings: includeShared),
  );

  test('song: removes its history, chart rows, Moments and listings', () async {
    final impact = await plan(
      const PermanentDeletionTarget.song('song_opening'),
    );

    expect(impact.canProceed, isTrue);
    expect(impact.targetName, 'Opening');
    expect(impact.songIds, {'song_opening'});
    expect(impact.albumIds, isEmpty);
    expect(impact.playbackSessionIds, {'session_opening'});
    expect(impact.qualifiedPlayIds, {'play_opening'});
    expect(impact.listeningSegmentCount, 2);
    expect(impact.listenedMs, 200000);
    expect(impact.chartEntryIds, {'entry_song_opening'});
    // Its release keeps its place but loses the play's stream.
    expect(impact.affectedChartWeeks, {'songs:$week1', 'albums:$week1'});
    expect(impact.earliestAffectedWeekStartUtc, week1);
    expect(impact.momentIdsAboutTarget, {'moment_opening_debut'});
    expect(impact.momentIdsMentioningTarget, {
      'moment_glow_dethrones_opening',
      'moment_echoes_exit_caused_by_opening',
    });
    expect(impact.playlists.single.playlistName, 'Road');
    expect(impact.playlists.single.itemsRemoved, 1);
    expect(impact.mediaFileBindingCount, 1);
    expect(impact.lyricsCount, 1);
  });

  test("REF-19: a deleted song's artist-dominance Moment in a week it "
      'charted goes with it; other artists and weeks stay', () async {
    Future<void> dominance(
      String id,
      String artistId,
      String week, [
      String weekEnd = week1End,
    ]) => db.insert(DatabaseTables.chartMomentEvents, {
      'id': id,
      'deduplication_key': id,
      'source_id': 'dominance:hot100:5:snapshot_songs',
      'chart_type': 'songs',
      'scope': 'finalized',
      'event_type': 'artistSimultaneousThresholdSongs',
      // It names another song: only the count includes Opening.
      'entity_id': 'song_second',
      'entity_title': 'Second',
      'entity_artist_id': artistId,
      'entity_artist_name': artistId,
      'week_start_utc': week,
      'week_end_utc': weekEnd,
      'occurred_at': now,
      'created_at': now,
      'threshold': 100,
      'milestone_value': 5,
    });
    await dominance('moment_nova_dominance', 'artist_nova', week1);
    await dominance('moment_echo_dominance', 'artist_echo', week1);
    await dominance(
      'moment_nova_dominance_later',
      'artist_nova',
      week1End,
      '2026-10-18T00:00:00.000Z',
    );

    final impact = await plan(
      const PermanentDeletionTarget.song('song_opening'),
    );

    expect(impact.momentIdsMentioningTarget, contains('moment_nova_dominance'));
    expect(
      impact.momentIdsMentioningTarget,
      isNot(contains('moment_echo_dominance')),
    );
    expect(
      impact.momentIdsMentioningTarget,
      isNot(contains('moment_nova_dominance_later')),
    );
    expect(
      impact.momentIdsAboutTarget,
      isNot(contains('moment_nova_dominance')),
    );
  });

  test('edition: only songs no other edition lists are deleted', () async {
    final impact = await plan(
      const PermanentDeletionTarget.edition('edition_nova_deluxe'),
    );

    expect(impact.editionIds, {'edition_nova_deluxe'});
    expect(impact.albumIds, isEmpty);
    expect(impact.songIds, {'song_bonus'});
    expect(impact.songsKeptLosingListing, {'song_opening', 'song_second'});
    // The Opening session and play were heard on Deluxe; they move to
    // Standard instead of being deleted.
    expect(impact.historyRowsRepointed, 2);
    expect(impact.playbackSessionIds, {'session_bonus'});
    expect(impact.momentIdsMentioningTarget, {
      'moment_lights_milestone_from_bonus_play',
    });
  });

  test('edition: the only edition of a release means the release', () async {
    final impact = await plan(
      const PermanentDeletionTarget.edition('edition_echoes'),
    );

    expect(impact.albumIds, {'album_echoes'});
    expect(impact.songIds, {'song_echo'});
  });

  test(
    'album: every edition and track, and other artists\' grouping',
    () async {
      final impact = await plan(
        const PermanentDeletionTarget.album('album_nova'),
      );

      expect(impact.targetName, 'Nova');
      expect(impact.albumIds, {'album_nova'});
      expect(impact.editionIds, {
        'edition_nova_standard',
        'edition_nova_deluxe',
      });
      expect(impact.songIds, {
        'song_opening',
        'song_second',
        'song_bonus',
        'song_duet',
      });
      expect(impact.chartEntryIds, {'entry_song_opening', 'entry_album_nova'});
      expect(impact.otherArtistsLosingProjectGrouping, {'artist_lumen'});
      expect(impact.metadataFieldStateCount, 1);
      expect(impact.artistIds, isEmpty, reason: 'the artist is never deleted');
    },
  );

  test('artist: shared recordings block until confirmed', () async {
    final impact = await plan(
      const PermanentDeletionTarget.artist('artist_nova'),
    );

    expect(impact.canProceed, isFalse);
    expect(impact.blockers, {
      PermanentDeletionBlocker.sharedRecordingsNotConfirmed,
    });
    expect(impact.sharedRecordingIds, {'song_duet', 'song_guest'});
    expect(impact.songIds, {'song_opening', 'song_second', 'song_bonus'});
    // Glow is Lumen's: it stays, and only loses the link to Nova.
    expect(impact.collaborationSongIdsKept, {'song_glow'});
    expect(impact.creditLinksRemoved, 1);
    expect(impact.momentIdsAboutTarget, contains('moment_nova_top_artist'));
  });

  test('artist: confirmed shared recordings are included', () async {
    final impact = await plan(
      const PermanentDeletionTarget.artist('artist_nova'),
      includeShared: true,
    );

    expect(impact.canProceed, isTrue);
    expect(impact.songIds, containsAll(['song_duet', 'song_guest']));
    expect(impact.albumIds, {'album_nova'});
    expect(impact.albumIds, isNot(contains('album_lights')));
  });

  test('a pending cloud write blocks the deletion', () async {
    await db.insert(DatabaseTables.syncOutbox, {
      'id': 'outbox_1',
      'entity_type': 'song',
      'entity_id': 'song_opening',
      'operation': 'upsert',
      'created_at': now,
      'updated_at': now,
    });

    final impact = await plan(
      const PermanentDeletionTarget.song('song_opening'),
    );

    expect(impact.blockers, {PermanentDeletionBlocker.pendingCloudWrite});
    expect(impact.pendingCloudWriteCount, 1);
  });

  test('an unknown id is reported, not guessed', () async {
    final impact = await plan(
      const PermanentDeletionTarget.album('album_nope'),
    );

    expect(impact.blockers, {PermanentDeletionBlocker.notFound});
    expect(impact.songIds, isEmpty);
  });

  test('planning never writes', () async {
    Future<Map<String, int>> counts() async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      return {
        for (final t in tables)
          t['name'] as String: _firstInt(
            await db.rawQuery('SELECT COUNT(*) FROM "${t['name']}"'),
          ),
      };
    }

    final before = await counts();
    final changesBefore = _firstInt(
      await db.rawQuery('SELECT total_changes()'),
    );
    for (final target in const [
      PermanentDeletionTarget.song('song_opening'),
      PermanentDeletionTarget.edition('edition_nova_deluxe'),
      PermanentDeletionTarget.album('album_nova'),
      PermanentDeletionTarget.artist('artist_nova'),
    ]) {
      await plan(target, includeShared: true);
    }

    expect(await counts(), before);
    expect(
      _firstInt(await db.rawQuery('SELECT total_changes()')),
      changesBefore,
    );
  });
}

Future<void> _seed(
  Database db, {
  required String now,
  required String week,
  required String weekEnd,
}) async {
  Map<String, Object?> stamp(Map<String, Object?> row) => {
    ...row,
    'created_at': now,
    'updated_at': now,
  };

  for (final (id, name) in [
    ('artist_nova', 'Nova'),
    ('artist_lumen', 'Lumen'),
    ('artist_echo', 'Echo'),
  ]) {
    await db.insert(
      DatabaseTables.artists,
      stamp({'id': id, 'name': name, 'canonical_name': name.toLowerCase()}),
    );
  }

  for (final (id, artist, title) in [
    ('album_nova', 'artist_nova', 'Nova'),
    ('album_lights', 'artist_lumen', 'Lights'),
    ('album_echoes', 'artist_echo', 'Echoes'),
  ]) {
    await db.insert(
      DatabaseTables.albums,
      stamp({
        'id': id,
        'artist_id': artist,
        'title': title,
        'canonical_title': title.toLowerCase(),
      }),
    );
  }

  for (final (id, album, title, type, primary) in [
    ('edition_nova_standard', 'album_nova', 'Nova', 'standard', 1),
    ('edition_nova_deluxe', 'album_nova', 'Nova (Deluxe)', 'deluxe', 0),
    ('edition_lights', 'album_lights', 'Lights', 'standard', 1),
    ('edition_echoes', 'album_echoes', 'Echoes', 'standard', 1),
  ]) {
    await db.insert(
      DatabaseTables.albumEditions,
      stamp({
        'id': id,
        'album_id': album,
        'title': title,
        'type': type,
        'is_primary': primary,
      }),
    );
  }

  // (song, title, artist, album, home edition, listed on)
  final songs = [
    (
      'song_opening',
      'Opening',
      'artist_nova',
      'album_nova',
      'edition_nova_standard',
      ['edition_nova_standard', 'edition_nova_deluxe'],
    ),
    (
      'song_second',
      'Second',
      'artist_nova',
      'album_nova',
      'edition_nova_standard',
      ['edition_nova_standard', 'edition_nova_deluxe'],
    ),
    (
      'song_bonus',
      'Bonus',
      'artist_nova',
      'album_nova',
      'edition_nova_deluxe',
      ['edition_nova_deluxe'],
    ),
    (
      'song_duet',
      'Duet',
      'artist_lumen',
      'album_nova',
      'edition_nova_standard',
      ['edition_nova_standard'],
    ),
    (
      'song_glow',
      'Glow',
      'artist_lumen',
      'album_lights',
      'edition_lights',
      ['edition_lights'],
    ),
    (
      'song_guest',
      'Guest',
      'artist_nova',
      'album_lights',
      'edition_lights',
      ['edition_lights'],
    ),
    (
      'song_echo',
      'Echo',
      'artist_echo',
      'album_echoes',
      'edition_echoes',
      ['edition_echoes'],
    ),
  ];
  var position = 0;
  for (final (id, title, artist, album, edition, listings) in songs) {
    await db.insert(
      DatabaseTables.songs,
      stamp({
        'id': id,
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': edition,
        'title': title,
        'canonical_title': title.toLowerCase(),
      }),
    );
    for (final listing in listings) {
      await db.insert(
        DatabaseTables.albumEditionTracks,
        stamp({
          'album_edition_id': listing,
          'song_id': id,
          'sort_position': position++,
        }),
      );
    }
    await db.insert(
      DatabaseTables.songArtistCredits,
      stamp({
        'id': 'credit_${id}_0',
        'song_id': id,
        'artist_id': artist,
        'credited_name': artist,
        'canonical_credited_name': artist,
        'role': 'primary',
        'position': 0,
      }),
    );
    await db.insert(
      DatabaseTables.mediaFileBindings,
      stamp({
        'id': 'binding_$id',
        'song_id': id,
        'file_path': '/synthetic/$id.mp3',
        'normalized_path': '/synthetic/$id.mp3',
      }),
    );
  }
  await db.insert(
    DatabaseTables.songArtistCredits,
    stamp({
      'id': 'credit_song_glow_1',
      'song_id': 'song_glow',
      'artist_id': 'artist_nova',
      'credited_name': 'Nova',
      'canonical_credited_name': 'nova',
      'role': 'featured',
      'position': 1,
    }),
  );
  await db.insert(
    DatabaseTables.trackLyrics,
    stamp({'song_id': 'song_opening', 'plain_text': 'la la'}),
  );

  // Listening history: one session and play per song (the Opening play was
  // heard on the Deluxe edition).
  for (final (song, artist, album, edition, at) in [
    (
      'opening',
      'artist_nova',
      'album_nova',
      'edition_nova_deluxe',
      '2026-10-05T10:00:00.000Z',
    ),
    (
      'bonus',
      'artist_nova',
      'album_nova',
      'edition_nova_deluxe',
      '2026-10-05T11:00:00.000Z',
    ),
    (
      'glow',
      'artist_lumen',
      'album_lights',
      'edition_lights',
      '2026-10-05T12:00:00.000Z',
    ),
    (
      'echo',
      'artist_echo',
      'album_echoes',
      'edition_echoes',
      '2026-10-05T13:00:00.000Z',
    ),
  ]) {
    await db.insert(
      DatabaseTables.playbackSessions,
      stamp({
        'id': 'session_$song',
        'song_id': 'song_$song',
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': edition,
        'song_title': song,
        'artist_name': artist,
        'album_title': album,
        'album_edition_title': edition,
        'started_at': at,
        'ended_at': at,
        'listened_duration_ms': 200000,
        'track_duration_ms': 200000,
      }),
    );
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play_$song',
      'playback_session_id': 'session_$song',
      'song_id': 'song_$song',
      'artist_id': artist,
      'album_id': album,
      'album_edition_id': edition,
      'qualified_at': at,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': now,
    });
  }
  for (final segment in ['a', 'b']) {
    await db.insert(
      DatabaseTables.playbackListeningSegments,
      stamp({
        'id': 'segment_opening_$segment',
        'playback_session_id': 'session_opening',
        'started_at': now,
        'ended_at': now,
        'listened_duration_ms': 100000,
      }),
    );
  }

  // One finalized week of each chart.
  for (final type in ['songs', 'albums']) {
    await db.insert(
      DatabaseTables.chartSnapshots,
      stamp({
        'id': 'snapshot_$type',
        'chart_type': type,
        'week_start_utc': week,
        'week_end_utc': weekEnd,
        'finalized_at': weekEnd,
      }),
    );
  }
  for (final (id, snapshot, entity, rank) in [
    ('entry_song_opening', 'snapshot_songs', 'song_opening', 1),
    ('entry_song_glow', 'snapshot_songs', 'song_glow', 2),
    ('entry_song_echo', 'snapshot_songs', 'song_echo', 3),
    ('entry_album_nova', 'snapshot_albums', 'album_nova', 1),
    ('entry_album_lights', 'snapshot_albums', 'album_lights', 2),
    ('entry_album_echoes', 'snapshot_albums', 'album_echoes', 3),
  ]) {
    await db.insert(
      DatabaseTables.chartEntries,
      stamp({
        'id': id,
        'chart_snapshot_id': snapshot,
        'entity_id': entity,
        'title': entity,
        'artist_name': 'synthetic',
        'rank': rank,
        'qualified_stream_count': 1,
        'peak_rank': rank,
        'peak_achieved_at': weekEnd,
        'weeks_on_chart': 1,
        'movement': 'newEntry',
        'last_qualified_at': weekEnd,
      }),
    );
  }

  Future<void> moment(
    String id, {
    required String type,
    required String entity,
    required String artistId,
    String chartType = 'songs',
    String? related,
    String? relatedArtistId,
    String? source,
  }) => db.insert(DatabaseTables.chartMomentEvents, {
    'id': id,
    'deduplication_key': id,
    'source_id': source,
    'chart_type': chartType,
    'scope': 'allTime',
    'event_type': type,
    'entity_id': entity,
    'entity_title': entity,
    'entity_artist_id': artistId,
    'entity_artist_name': artistId,
    'related_entity_id': related,
    'related_entity_title': related,
    'related_entity_artist_id': relatedArtistId,
    'related_entity_artist_name': related == null ? null : relatedArtistId,
    'week_start_utc': week,
    'week_end_utc': weekEnd,
    'occurred_at': now,
    'created_at': now,
  });

  await moment(
    'moment_opening_debut',
    type: 'debut',
    entity: 'song_opening',
    artistId: 'artist_nova',
    source: 'play_opening',
  );
  await moment(
    'moment_glow_dethrones_opening',
    type: 'numberOne',
    entity: 'song_glow',
    artistId: 'artist_lumen',
    related: 'song_opening',
    relatedArtistId: 'artist_nova',
    source: 'play_glow',
  );
  await moment(
    'moment_echoes_exit_caused_by_opening',
    type: 'exit',
    chartType: 'albums',
    entity: 'album_echoes',
    artistId: 'artist_echo',
    source: 'exit:play_opening:album_echoes',
  );
  await moment(
    'moment_echo_unrelated',
    type: 'debut',
    entity: 'song_echo',
    artistId: 'artist_echo',
    source: 'play_echo',
  );
  await moment(
    'moment_nova_top_artist',
    type: 'topArtist',
    entity: 'artist_nova',
    artistId: 'artist_nova',
  );
  await moment(
    'moment_lights_milestone_from_bonus_play',
    type: 'streamMilestone',
    chartType: 'albums',
    entity: 'album_lights',
    artistId: 'artist_lumen',
    source: 'play_bonus',
  );

  await db.insert(
    DatabaseTables.playlists,
    stamp({'id': 'pl_road', 'name': 'Road'}),
  );
  var item = 0;
  for (final song in ['song_opening', 'song_bonus', 'song_glow']) {
    await db.insert(
      DatabaseTables.playlistItems,
      stamp({
        'id': 'pl_item_$song',
        'playlist_id': 'pl_road',
        'song_id': song,
        'position': item++,
      }),
    );
  }

  await db.insert(DatabaseTables.metadataFieldStates, {
    'entity_type': 'album',
    'entity_id': 'album_nova',
    'field_name': 'title',
    'authority': 'manual',
    'source': 'user',
    'updated_at': now,
  });
  await db.insert(
    DatabaseTables.artistProjectAssignments,
    stamp({
      'artist_id': 'artist_lumen',
      'album_id': 'album_nova',
      'mode': 'grouped',
    }),
  );
}

int _firstInt(List<Map<String, Object?>> rows) =>
    rows.first.values.first! as int;
