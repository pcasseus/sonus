// App Update 1.2 patches, Checkpoint 1 (BUG-00A, BUG-00C): merged ids are
// followed along their whole chain, history of a merged duplicate stays
// deleted once the record it became is deleted, and a chain that loops is
// refused without writing anything. Disposable databases only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/remote_library_deletion_applier.dart';
import 'package:sonus_next/features/library/data/repositories/merge_history_remap.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_deletion_ledger.dart';
import 'package:sonus_next/features/recovery/application/services/restore_ledger_filter.dart';
import 'package:sonus_next/features/sync/application/services/cloud_archive_sync_service.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';

const _stamp = '2026-11-01T12:00:00.000Z';

void main() {
  sqfliteFfiInit();

  group('MergeChains', () {
    final chains = MergeChains(
      songs: {'a': 'b', 'b': 'c', 'x': 'y'},
      albums: {'loop1': 'loop2', 'loop2': 'loop1', 'self': 'self', 'e': ''},
    );

    test('an id that was never merged resolves to itself', () {
      expect(chains.path('songs', 'z'), ['z']);
      expect(chains.resolve('songs', 'c'), 'c');
      expect(chains.isMerged('songs', 'c'), isFalse);
    });

    test('a chain resolves to its end, never to a middle step', () {
      expect(chains.path('songs', 'a'), ['a', 'b', 'c']);
      expect(chains.resolve('songs', 'a'), 'c');
      expect(chains.resolve('songs', 'b'), 'c');
      expect(chains.resolve('songs', 'x'), 'y');
      expect(chains.isMerged('songs', 'a'), isTrue);
    });

    test('kinds are separate', () {
      expect(chains.resolve('albums', 'a'), 'a');
    });

    test('a deleted record anywhere on the chain counts', () {
      expect(chains.chainHitsAny('songs', 'a', {'c'}), isTrue);
      expect(chains.chainHitsAny('songs', 'a', {'b'}), isTrue);
      expect(chains.chainHitsAny('songs', 'a', {'y'}), isFalse);
      expect(chains.chainHitsAny('songs', null, {'a'}), isFalse);
    });

    test('loops, self-merges and empty ids are refused', () {
      expect(
        () => chains.resolve('albums', 'loop1'),
        throwsA(isA<MergeChainException>()),
      );
      expect(
        () => chains.resolve('albums', 'self'),
        throwsA(isA<MergeChainException>()),
      );
      expect(
        () => chains.resolve('albums', 'e'),
        throwsA(isA<MergeChainException>()),
      );
      expect(
        () => chains.resolve('songs', ''),
        throwsA(isA<MergeChainException>()),
      );
    });

    test('an unknown kind is a programming error', () {
      expect(() => chains.resolve('artists', 'a'), throwsArgumentError);
    });
  });

  late Directory dir;
  late AppDatabase database;
  late Database db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_merge_chain_');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'chain.db'),
    );
    db = await database.database;
    await db.insert(DatabaseTables.artists, {
      'id': 'nova',
      'name': 'nova',
      'canonical_name': 'nova',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  /// A release with one song: album `album_<key>`, edition `ed_<key>`,
  /// song `<key>`.
  Future<void> release(String key) async {
    await db.insert(DatabaseTables.albums, {
      'id': 'album_$key',
      'artist_id': 'nova',
      'title': 'Nova',
      'canonical_title': 'nova',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.albumEditions, {
      'id': 'ed_$key',
      'album_id': 'album_$key',
      'title': 'Nova',
      'type': 'standard',
      'is_primary': 1,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.songs, {
      'id': key,
      'artist_id': 'nova',
      'album_id': 'album_$key',
      'album_edition_id': 'ed_$key',
      'title': 'Opening',
      'canonical_title': 'opening',
      'track_number': 1,
      'duration_seconds': 200,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
  }

  /// A merge of release [from] into release [into], as this device's
  /// journal and ledger record it.
  Future<void> merged(String from, String into, {String? at}) async {
    final operation = 'op_${from}_$into';
    await db.insert(DatabaseTables.libraryDeletionJournal, {
      'id': operation,
      'operation': 'duplicateMerge',
      'target_type': 'album',
      'target_id': 'album_$from',
      'summary': jsonEncode({
        'songs': {from: into},
        'editions': {'ed_$from': 'ed_$into'},
        'albums': {'album_$from': 'album_$into'},
        'movedPlays': 0,
      }),
      'committed_at': at ?? _stamp,
    });
    final ledger = SqliteLibraryDeletionLedger(db);
    for (final (entity, id) in [
      (DeletionLedgerEntity.song, from),
      (DeletionLedgerEntity.albumEdition, 'ed_$from'),
      (DeletionLedgerEntity.album, 'album_$from'),
    ]) {
      await ledger.record(
        entity,
        [id],
        reason: DeletionLedgerReason.duplicateMerge,
        operationId: operation,
        at: DateTime.parse(_stamp),
      );
    }
  }

  Future<void> deletedByUser(String song) =>
      SqliteLibraryDeletionLedger(db).record(
        DeletionLedgerEntity.song,
        [song],
        reason: DeletionLedgerReason.userDeletion,
        operationId: 'op_delete_$song',
        at: DateTime.parse(_stamp),
      );

  Map<String, Object?> session(String id, String song) => {
    'id': id,
    'song_id': song,
    'artist_id': 'nova',
    'album_id': 'album_$song',
    'album_edition_id': 'ed_$song',
    'song_title': 'Opening',
    'artist_name': 'nova',
    'album_title': 'Nova',
    'album_edition_title': 'Nova',
    'started_at': _stamp,
    'ended_at': _stamp,
    'listened_duration_ms': 200000,
    'track_duration_ms': 200000,
    'created_at': _stamp,
    'updated_at': _stamp,
  };

  Map<String, Object?> play(String id, String song) => {
    'id': 'play_$id',
    'playback_session_id': id,
    'song_id': song,
    'artist_id': 'nova',
    'album_id': 'album_$song',
    'album_edition_id': 'ed_$song',
    'qualified_at': _stamp,
    'listened_duration_ms': 200000,
    'track_duration_ms': 200000,
    'created_at': _stamp,
  };

  CloudArchiveRecord listening(String id, String song) => CloudArchiveRecord(
    kind: CloudArchiveKind.listeningSession,
    key: id,
    payload: {
      'session': session(id, song),
      'segments': const <Object>[],
      'qualified_play': play(id, song),
    },
    clientUpdatedAt: DateTime.utc(2026, 11, 5),
  );

  SqliteCloudArchiveStore store() => SqliteCloudArchiveStore(
    appDatabase: database,
    changes: LibraryChangeSignal(),
  );

  Future<List<Map<String, Object?>>> rows(String table, [String? where]) =>
      db.query(table, where: where);

  group('cloud archive replay', () {
    test('BUG-00C: listening of A follows A → B → C to C', () async {
      await release('c');
      await merged('a', 'b');
      await merged('b', 'c', at: '2026-11-02T12:00:00.000Z');

      expect(
        await store().apply(listening('s1', 'a')),
        CloudArchiveApplyOutcome.applied,
      );

      for (final table in [
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
      ]) {
        final row = (await rows(table)).single;
        expect(row['song_id'], 'c', reason: table);
        expect(row['album_id'], 'album_c', reason: table);
        expect(row['album_edition_id'], 'ed_c', reason: table);
      }
    });

    test('BUG-00A: listening of a duplicate merged into a song deleted '
        'later stays deleted', () async {
      await release('k');
      await merged('s', 'k');
      await deletedByUser('k');
      await db.delete(DatabaseTables.songs, where: "id = 'k'");

      expect(
        await store().apply(listening('late', 's')),
        CloudArchiveApplyOutcome.deletedHere,
      );
      expect(await rows(DatabaseTables.playbackSessions), isEmpty);
      expect(await rows(DatabaseTables.qualifiedPlays), isEmpty);
    });

    test(
      'BUG-00A: deletion of any record along a longer chain counts',
      () async {
        await release('c');
        await merged('a', 'b');
        await merged('b', 'c', at: '2026-11-02T12:00:00.000Z');
        await deletedByUser('c');

        expect(
          await store().apply(listening('late', 'a')),
          CloudArchiveApplyOutcome.deletedHere,
        );
        expect(await rows(DatabaseTables.playbackSessions), isEmpty);
      },
    );

    test('BUG-00C: a looping chain writes nothing and waits', () async {
      await release('a');
      await merged('a', 'b');
      await merged('b', 'a', at: '2026-11-02T12:00:00.000Z');

      expect(
        await store().apply(listening('s1', 'a')),
        CloudArchiveApplyOutcome.missingDependencies,
      );
      expect(await rows(DatabaseTables.playbackSessions), isEmpty);
      expect(await rows(DatabaseTables.qualifiedPlays), isEmpty);
    });

    test('an all-time Moment follows the chain, and stays deleted with the '
        'record it became', () async {
      await release('c');
      await merged('a', 'b');
      await merged('b', 'c', at: '2026-11-02T12:00:00.000Z');
      CloudArchiveRecord story(String key) => CloudArchiveRecord(
        kind: CloudArchiveKind.allTimeMoment,
        key: key,
        payload: {
          'id': key,
          'deduplication_key': key,
          'chart_type': 'songs',
          'scope': 'allTime',
          'event_type': 'debut',
          'entity_id': 'a',
          'entity_title': 'Opening',
          'entity_artist_id': 'nova',
          'entity_artist_name': 'nova',
          'week_start_utc': '2026-10-25T04:00:00.000Z',
          'week_end_utc': '2026-11-01T04:00:00.000Z',
          'occurred_at': _stamp,
          'created_at': _stamp,
        },
        clientUpdatedAt: DateTime.utc(2026, 11, 5),
      );

      expect(
        await store().apply(story('debut_a')),
        CloudArchiveApplyOutcome.applied,
      );
      expect(
        (await rows(DatabaseTables.chartMomentEvents)).single['entity_id'],
        'c',
      );

      await deletedByUser('c');
      expect(
        await store().apply(story('debut_a_again')),
        CloudArchiveApplyOutcome.deletedHere,
      );
      expect(await rows(DatabaseTables.chartMomentEvents), hasLength(1));
    });

    test('a playlist entry follows the chain once, and leaves with a song '
        'deleted later', () async {
      await release('c');
      await release('other');
      await merged('a', 'b');
      await merged('b', 'c', at: '2026-11-02T12:00:00.000Z');
      CloudArchiveRecord playlist(List<String> songs) => CloudArchiveRecord(
        kind: CloudArchiveKind.playlist,
        key: 'mix',
        payload: {
          'id': 'mix',
          'name': 'Mix',
          'created_at': _stamp,
          'updated_at': _stamp,
          'items': [
            for (final (index, song) in songs.indexed)
              {
                'id': 'item_$index',
                'song_id': song,
                'position': index,
                'created_at': _stamp,
                'updated_at': _stamp,
              },
          ],
        },
        clientUpdatedAt: DateTime.utc(2026, 11, 5),
      );

      expect(
        await store().apply(playlist(['a', 'other', 'c'])),
        CloudArchiveApplyOutcome.applied,
      );
      final items = await db.query(
        DatabaseTables.playlistItems,
        orderBy: 'position',
      );
      expect([for (final i in items) i['song_id']], ['c', 'other']);
      expect([for (final i in items) i['position']], [0, 1]);

      await deletedByUser('c');
      expect(
        await store().apply(playlist(['a', 'other'])),
        CloudArchiveApplyOutcome.applied,
      );
      final after = await db.query(DatabaseTables.playlistItems);
      expect([for (final i in after) i['song_id']], ['other']);
      expect(after.single['position'], 0);
    });
  });

  group('restore', () {
    Map<String, List<Map<String, Object?>>> backup(String song) => {
      DatabaseTables.playbackSessions: [session('s1', song)],
      DatabaseTables.qualifiedPlays: [play('s1', song)],
      DatabaseTables.playlistItems: [
        {
          'id': 'item_1',
          'playlist_id': 'mix',
          'song_id': song,
          'position': 0,
          'created_at': _stamp,
          'updated_at': _stamp,
        },
      ],
    };

    test('BUG-00C: history in a backup follows A → B → C to C', () async {
      await merged('a', 'b');
      await merged('b', 'c', at: '2026-11-02T12:00:00.000Z');

      final filter = await RestoreLedgerFilter.load(db);
      final out = filter.apply(backup('a')).tables;

      final restoredSession = out[DatabaseTables.playbackSessions]!.single;
      expect(restoredSession['song_id'], 'c');
      expect(restoredSession['album_id'], 'album_c');
      expect(restoredSession['album_edition_id'], 'ed_c');
      expect(out[DatabaseTables.qualifiedPlays]!.single['song_id'], 'c');
      expect(out[DatabaseTables.playlistItems]!.single['song_id'], 'c');
    });

    test('BUG-00A: history of a duplicate merged into a song deleted later '
        'is not restored', () async {
      await merged('s', 'k');
      await deletedByUser('k');

      final filter = await RestoreLedgerFilter.load(db);
      final result = filter.apply(backup('s'));

      expect(result.tables[DatabaseTables.playbackSessions], isEmpty);
      expect(result.tables[DatabaseTables.qualifiedPlays], isEmpty);
      expect(result.tables[DatabaseTables.playlistItems], isEmpty);
      expect(result.removed[DatabaseTables.playbackSessions], 1);
      expect(result.removed[DatabaseTables.qualifiedPlays], 1);
    });

    test('BUG-00C: a looping chain refuses the whole restore', () async {
      await merged('a', 'b');
      await merged('b', 'a', at: '2026-11-02T12:00:00.000Z');

      final filter = await RestoreLedgerFilter.load(db);
      expect(
        () => filter.apply(backup('a')),
        throwsA(isA<MergeChainException>()),
      );
    });
  });

  group('a merge from another device', () {
    Map<String, Object?> remoteMerge(String from, String into) => {
      'operation': 'duplicateMerge',
      'targetType': 'album',
      'targetId': 'album_$from',
      'committedAt': '2026-11-03T12:00:00.000Z',
      'entries': [
        ['album', 'album_$from'],
        ['albumEdition', 'ed_$from'],
        ['song', from],
      ],
      'remap': {
        'songs': {from: into},
        'editions': {'ed_$from': 'ed_$into'},
        'albums': {'album_$from': 'album_$into'},
      },
    };

    Future<bool> applyRemote(String from, String into) => db.transaction(
      (txn) => RemoteLibraryDeletionApplier(
        appDatabase: database,
      ).apply(txn, 'remote_${from}_$into', remoteMerge(from, into)),
    );

    test(
      'BUG-00C: goes to where the kept record was merged here since',
      () async {
        // This device merged K into J; another device merged S into K.
        await release('s');
        await release('j');
        await merged('k', 'j');
        await db.insert(DatabaseTables.playbackSessions, session('s1', 's'));
        await db.insert(DatabaseTables.qualifiedPlays, play('s1', 's'));

        expect(await applyRemote('s', 'k'), isTrue);

        expect(await rows(DatabaseTables.songs, "id = 's'"), isEmpty);
        expect(await rows(DatabaseTables.albums, "id = 'album_s'"), isEmpty);
        for (final table in [
          DatabaseTables.playbackSessions,
          DatabaseTables.qualifiedPlays,
        ]) {
          final row = (await rows(table)).single;
          expect(row['song_id'], 'j', reason: table);
          expect(row['album_id'], 'album_j', reason: table);
          expect(row['album_edition_id'], 'ed_j', reason: table);
        }
      },
    );

    test('BUG-00C: a merge that would close a loop waits and changes '
        'nothing', () async {
      // This device merged K into S; another device merged S into K.
      await release('s');
      await merged('k', 's');
      await db.insert(DatabaseTables.playbackSessions, session('s1', 's'));
      final journal = await rows(DatabaseTables.libraryDeletionJournal);

      expect(await applyRemote('s', 'k'), isFalse);

      expect(await rows(DatabaseTables.songs, "id = 's'"), hasLength(1));
      expect(await rows(DatabaseTables.albums, "id = 'album_s'"), hasLength(1));
      expect(
        (await rows(DatabaseTables.playbackSessions)).single['song_id'],
        's',
      );
      expect(await rows(DatabaseTables.libraryDeletionJournal), journal);
    });

    test('BUG-00C: remembering a merge this device never had resolves '
        'history through later merges', () async {
      // History of S arrived earlier; S itself never did. K was merged
      // into J here.
      await release('j');
      await merged('k', 'j');
      await db.insert(DatabaseTables.playbackSessions, session('s1', 's'));

      expect(await applyRemote('s', 'k'), isTrue);

      expect(
        (await rows(DatabaseTables.playbackSessions)).single['song_id'],
        'j',
      );
    });
  });
}
