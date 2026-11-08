// App Update 1.2 staging validation: permanent deletion and library
// integrity, end to end, against the isolated local Supabase stack.
//
// Skipped unless a staging target is given:
//   flutter test test/integration/staging --concurrency=1 \
//     --dart-define=SONUS_STAGING_URL=http://127.0.0.1:55421 \
//     --dart-define=SONUS_STAGING_ANON_KEY=<local demo anon key> \
//     --dart-define=SONUS_STAGING_SERVICE_KEY=<local demo service key>
// The guard (support/staging_guard.dart) refuses every other target, and
// the server must carry the staging marker. Synthetic users and records.
//
// The scenarios run in order and share one world: S = server, C = client
// (plan: _internal/APP_UPDATE_1_2_STAGING_TEST_PLAN.md). Every device runs
// the app's real sync stack (SyncComposition) over HTTP.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/restore_preflight_service.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';

import '../../support/recovery_fixtures.dart' show createFixtureBackup;
import 'support/staging_guard.dart';
import 'support/staging_world.dart';

void main() {
  final config = stagingConfig();
  if (config == null) {
    test(
      'staging validation',
      () {},
      skip: 'no staging target (SONUS_STAGING_URL) given',
    );
    return;
  }
  if (config.phase.isNotEmpty) {
    test('staging validation', () {}, skip: 'phase ${config.phase} run');
    return;
  }

  // Unique per run, so a run never meets an earlier run's records.
  final run = 'st${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  String a(String id) => '${run}_a_$id';
  String b(String id) => '${run}_b_$id';
  const password = 'staging-password-not-secret';
  final now = DateTime.now();
  // Plays this week: never part of a finalized chart.
  final thisWeek = now.toUtc().subtract(const Duration(hours: 2));

  late Directory root;
  late StagingAdmin admin;
  late String userA;
  late String userB;
  late String userP; // server probes only; no device
  late SupabaseClient probe;
  late StagingDevice phone;
  late StagingDevice tablet;
  late StagingDevice travel;
  late StagingDevice other;
  late StagingDevice laptop;
  late File preDeletionBackup;
  final devices = <StagingDevice>[];
  final deleted = <String>{};

  Future<StagingDevice> open(String name, String user, String email) async {
    final device = await StagingDevice.open(
      name: name,
      root: root,
      config: config,
      email: email,
      password: password,
      userId: user,
    );
    devices.add(device);
    return device;
  }

  /// The server refuses: 42501 (not allowed), or 23514 (a check, such as
  /// "a deleted record keeps no content").
  Future<void> expectRefused(
    Future<Object?> Function() write, {
    Set<String> codes = const {'42501'},
  }) async {
    try {
      await write();
      fail('the server accepted the write');
    } on PostgrestException catch (error) {
      expect(codes, contains(error.code), reason: error.message);
    }
  }

  Future<Map<String, dynamic>> cloudSong(String id) async =>
      (await admin.libraryRow('songs', id))!;

  /// The newest deletion or merge recorded on [device].
  Future<String> lastOperation(StagingDevice device) async =>
      (await (await device.db).query(
            DatabaseTables.libraryDeletionJournal,
            orderBy: 'committed_at DESC, id DESC',
            limit: 1,
          )).single['id']!
          as String;

  Future<List<Map<String, dynamic>>> deletionRecords(String user) =>
      admin.archive(user, kind: 'library_deletion');

  Future<int> ledgered(StagingDevice device, String type, String id) =>
      device.count(
        DatabaseTables.libraryDeletionLedger,
        'entity_type = ? AND entity_id = ?',
        [type, id],
      );

  setUpAll(() async {
    admin = StagingAdmin(config);
    await admin.assertStagingServer();
    root = await Directory.systemTemp.createTemp('sonus_staging_');
    userA = await admin.createUser('a-$run@staging.invalid', password);
    userB = await admin.createUser('b-$run@staging.invalid', password);
    userP = await admin.createUser('p-$run@staging.invalid', password);
    probe = SupabaseClient(
      config.url.toString(),
      config.anonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await probe.auth.signInWithPassword(
      email: 'p-$run@staging.invalid',
      password: password,
    );
    phone = await open('phone', userA, 'a-$run@staging.invalid');
    tablet = await open('tablet', userA, 'a-$run@staging.invalid');
    travel = await open('travel', userA, 'a-$run@staging.invalid');
    other = await open('other', userB, 'b-$run@staging.invalid');
  });

  tearDownAll(() async {
    for (final device in devices) {
      await device.close();
    }
    await probe.dispose();
    await admin.client.dispose();
    if (Platform.environment['SONUS_STAGING_KEEP'] == null) {
      await root.delete(recursive: true);
    } else {
      stdout.writeln('Staging device databases kept in ${root.path}');
    }
  });

  test('seed: one library and its history on every device of user A', () async {
    for (final artist in ['nova', 'lumen', 'echo']) {
      await phone.artist(a(artist));
    }
    await phone.album(a('nova_album'), a('nova'), [
      a('nova_std'),
      a('nova_dlx'),
    ]);
    await phone.album(a('lights'), a('lumen'), [a('lights_std')]);
    await phone.album(a('echoes'), a('echo'), [a('echoes_std')]);
    await phone.album(a('misc'), a('echo'), [a('misc_std')]);
    await phone.album(a('dup_a'), a('echo'), [
      a('dup_a_std'),
    ], title: 'Duplicate Days');
    await phone.album(a('dup_b'), a('echo'), [
      a('dup_b_std'),
    ], title: 'Duplicate Days');
    await phone.album(a('twin'), a('lumen'), [a('twin_std'), a('twin_dlx')]);

    await phone.song(
      a('opening'),
      artistId: a('nova'),
      albumId: a('nova_album'),
      home: a('nova_std'),
      listedOn: [a('nova_std'), a('nova_dlx')],
    );
    await phone.song(
      a('bonus'),
      artistId: a('nova'),
      albumId: a('nova_album'),
      home: a('nova_dlx'),
    );
    await phone.song(
      a('glow'),
      artistId: a('lumen'),
      albumId: a('lights'),
      home: a('lights_std'),
      featuring: [a('nova')],
    );
    await phone.song(
      a('echo'),
      artistId: a('echo'),
      albumId: a('echoes'),
      home: a('echoes_std'),
    );
    // Nova's recording on Echo's release: a shared recording.
    await phone.song(
      a('guest'),
      artistId: a('nova'),
      albumId: a('echoes'),
      home: a('echoes_std'),
      track: 2,
    );
    // Echo featuring Nova: a collaboration that stays.
    await phone.song(
      a('duet'),
      artistId: a('echo'),
      albumId: a('echoes'),
      home: a('echoes_std'),
      featuring: [a('nova')],
      track: 3,
    );
    for (final (index, x) in ['x1', 'x2', 'x3'].indexed) {
      await phone.song(
        a(x),
        artistId: a('echo'),
        albumId: a('misc'),
        home: a('misc_std'),
        track: index + 1,
      );
    }
    for (final suffix in ['a', 'b']) {
      for (final (index, title) in ['One', 'Two'].indexed) {
        await phone.song(
          a('d${index + 1}$suffix'),
          artistId: a('echo'),
          albumId: a('dup_$suffix'),
          home: a('dup_${suffix}_std'),
          title: title,
          track: index + 1,
        );
      }
    }
    await phone.song(
      a('t1'),
      artistId: a('lumen'),
      albumId: a('twin'),
      home: a('twin_std'),
      listedOn: [a('twin_std'), a('twin_dlx')],
    );

    // Two finished weeks of listening, then some this week.
    final w1 = DateTime.utc(2026, 10, 6, 12);
    final w2 = DateTime.utc(2026, 10, 13, 12);
    for (final (song, at, times) in [
      ('opening', w1, 3),
      ('glow', w1, 2),
      ('echo', w1, 1),
      ('opening', w2, 3),
      ('glow', w2, 1),
      ('echo', w2, 2),
    ]) {
      for (var i = 0; i < times; i++) {
        await phone.play(a(song), at.add(Duration(minutes: i)));
      }
    }
    for (final song in ['x1', 'x2', 'x3', 'guest', 'd1a', 'd1a', 'bonus']) {
      await phone.play(a(song), thisWeek);
    }
    await phone.moment(a('m_open'), entity: a('opening'), artistId: a('nova'));
    await phone.moment(
      a('m_glow_passes'),
      entity: a('glow'),
      artistId: a('lumen'),
      related: a('opening'),
      relatedArtistId: a('nova'),
    );
    await phone.moment(a('m_echo'), entity: a('echo'), artistId: a('echo'));
    await phone.finalizeCharts(now);

    final result = await phone.syncNow();
    expect(result.pendingAfterSync, 0);
    expect(await phone.pendingOutbox(), 0);

    final song = await cloudSong(a('opening'));
    expect(song['user_id'], userA);
    expect(song['deleted_at'], isNull);
    expect(
      await admin.archive(userA, kind: 'listening_session'),
      hasLength(await phone.count(DatabaseTables.playbackSessions)),
    );
    expect(await admin.archive(userA, kind: 'all_time_moment'), hasLength(3));

    for (final device in [tablet, travel]) {
      await device.syncNow();
      expect(
        await device.count(DatabaseTables.songs, 'id LIKE ?', ['${run}_a_%']),
        await phone.count(DatabaseTables.songs),
      );
      expect(
        await device.count(DatabaseTables.playbackSessions),
        await phone.count(DatabaseTables.playbackSessions),
      );
      expect(
        await device.count(
          DatabaseTables.chartMomentEvents,
          "scope = 'allTime'",
        ),
        3,
      );
    }

    // User B's own library.
    await other.artist(b('solo'));
    await other.album(b('solo_album'), b('solo'), [b('solo_std')]);
    await other.song(
      b('solo_song'),
      artistId: b('solo'),
      albumId: b('solo_album'),
      home: b('solo_std'),
    );
    await other.play(b('solo_song'), thisWeek);
    await other.syncNow();

    // C9 needs a backup from before any deletion.
    final backups = await Directory('${root.path}/backups').create();
    preDeletionBackup = await createFixtureBackup(
      source: phone.database,
      directory: backups,
      backupId: 'pre-deletion',
      fileName: 'pre-deletion.sonusbackup',
    );
  });

  group('server (S3-S7)', () {
    test('S3 as a signed-in user: probe allowed; deleted history and deletion '
        'records cannot be changed', () async {
      final caps = await probe.rpc<List<dynamic>>('sonus_capabilities');
      expect(caps, contains('permanent_deletion_v1'));

      Map<String, Object?> record(String kind, String key, Object payload) => {
        'user_id': userP,
        'library_id': 'main',
        'kind': kind,
        'record_key': key,
        'payload': payload,
        'client_updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final table = probe.from('sonus_archive_records');
      await table.insert(
        record('listening_session', '${run}_s3', {'session': 'x'}),
      );
      await probe
          .from('sonus_archive_records')
          .update({'is_deleted': true, 'payload': <String, Object?>{}})
          .eq('record_key', '${run}_s3');
      await expectRefused(
        () => probe
            .from('sonus_archive_records')
            .update({
              'is_deleted': false,
              'payload': {'session': 'x'},
            })
            .eq('record_key', '${run}_s3'),
      );
      // A deleted history record must be empty.
      await expectRefused(
        () => probe
            .from('sonus_archive_records')
            .update({
              'payload': {'session': 'y'},
            })
            .eq('record_key', '${run}_s3'),
        codes: const {'42501', '23514'},
      );
      await probe
          .from('sonus_archive_records')
          .insert(
            record('library_deletion', '${run}_s3_op', {'entries': <Object>[]}),
          );
      await expectRefused(
        () => probe
            .from('sonus_archive_records')
            .update({
              'payload': {
                'entries': [
                  ['song', 'x'],
                ],
              },
            })
            .eq('record_key', '${run}_s3_op'),
      );
      await expectRefused(
        () => probe
            .from('sonus_archive_records')
            .update({'is_deleted': true})
            .eq('record_key', '${run}_s3_op'),
      );
      final rows = await admin.archive(userP, key: '${run}_s3_op');
      expect(rows.single['payload'], {'entries': <Object>[]});
      expect(rows.single['is_deleted'], isFalse);
    });

    test(
      'S4 one user can neither see nor change another user\'s records',
      () async {
        final b = other.client;
        expect(await b.from('songs').select().eq('id', a('opening')), isEmpty);
        expect(
          await b.from('sonus_archive_records').select().eq('user_id', userA),
          isEmpty,
        );
        expect(
          await b
              .from('songs')
              .update({'title': 'hijacked'})
              .eq('id', a('opening'))
              .select(),
          isEmpty,
        );
        expect(
          await b
              .from('songs')
              .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
              .eq('id', a('echo'))
              .select(),
          isEmpty,
        );
        expect(
          await b
              .from('sonus_archive_records')
              .update({'is_deleted': true, 'payload': <String, Object?>{}})
              .eq('user_id', userA)
              .select(),
          isEmpty,
        );
        await expectRefused(
          () => b.from('sonus_archive_records').insert({
            'user_id': userA,
            'library_id': 'main',
            'kind': 'library_deletion',
            'record_key': '${run}_forged',
            'payload': {
              'entries': [
                ['song', a('echo')],
              ],
            },
            'client_updated_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        final song = await cloudSong(a('opening'));
        expect(song['title'], a('opening'));
        expect((await cloudSong(a('echo')))['deleted_at'], isNull);
        expect(
          (await admin.archive(userA)).where((r) => r['is_deleted'] == true),
          isEmpty,
        );
        expect(await admin.archive(userA, key: '${run}_forged'), isEmpty);
      },
    );

    test('S5 anonymous callers get nothing', () async {
      final anon = SupabaseClient(
        config.url.toString(),
        config.anonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(anon.dispose);
      await expectRefused(() => anon.rpc<Object?>('sonus_capabilities'));
      // Refused outright, or nothing visible.
      for (final table in ['songs', 'sonus_archive_records']) {
        try {
          expect(await anon.from(table).select().limit(5), isEmpty);
        } on PostgrestException catch (error) {
          expect(error.code, '42501', reason: table);
        }
      }
      await expectRefused(
        () => anon.from('sonus_archive_records').insert({
          'user_id': userA,
          'library_id': 'main',
          'kind': 'listening_session',
          'record_key': '${run}_anon',
          'payload': {'x': 1},
          'client_updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    });

    test(
      'S6 old clients: removable kinds can still be removed and restored',
      () async {
        await probe.from('sonus_archive_records').insert({
          'user_id': userP,
          'library_id': 'main',
          'kind': 'playlist',
          'record_key': '${run}_playlist',
          'payload': {'name': 'Road'},
          'client_updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        await probe
            .from('sonus_archive_records')
            .update({'is_deleted': true})
            .eq('record_key', '${run}_playlist');
        final revived = await probe
            .from('sonus_archive_records')
            .update({
              'is_deleted': false,
              'payload': {'name': 'Road 2'},
            })
            .eq('record_key', '${run}_playlist')
            .select();
        expect(revived.single['is_deleted'], isFalse);
        expect(revived.single['payload'], {'name': 'Road 2'});
      },
    );
  });

  group('clients (C1-C15)', () {
    late PermanentDeletionImpact opening;
    late int finalizedMomentsAfterDeletion;
    late String travelSession;
    late String tabletDuplicatePlay;

    test('C6 (before) the travel device goes offline and plays and edits the '
        'song about to be deleted', () async {
      travel.http.offline = true;
      travelSession = await travel.play(a('opening'), thisWeek);
      await travel.renameSong(a('opening'), 'Opening (live)');
      await expectLater(travel.syncNow(), throwsA(anything));
      expect(await travel.pendingOutbox(), greaterThan(0));
    });

    test(
      'C1 song deletion reaches the cloud: library, history, Moments',
      () async {
        opening = await phone.deletion().preview(
          PermanentDeletionTarget.song(a('opening')),
        );
        expect(opening.blockers, isEmpty);
        expect(opening.songIds, {a('opening')});
        expect(opening.playbackSessionIds, hasLength(6));
        // The all-time Moments (archived), and the phone's weekly chart
        // Moments about it (local only).
        expect(
          opening.allMomentIds,
          containsAll([a('m_open'), a('m_glow_passes')]),
        );
        expect(opening.allMomentIds, isNot(contains(a('m_echo'))));
        expect(await phone.songChartWeeks(), hasLength(2));

        await phone.deletion().delete(opening);
        deleted.add(a('opening'));
        // Locally, at once.
        expect(
          await phone.count(DatabaseTables.songs, 'id = ?', [a('opening')]),
          0,
        );
        expect(
          await phone.count(DatabaseTables.playbackSessions, 'song_id = ?', [
            a('opening'),
          ]),
          0,
        );
        expect(
          await phone.count(DatabaseTables.qualifiedPlays, 'song_id = ?', [
            a('opening'),
          ]),
          0,
        );
        expect(await ledgered(phone, 'song', a('opening')), 1);
        finalizedMomentsAfterDeletion = await phone.count(
          DatabaseTables.chartMomentEvents,
        );

        await phone.syncNow();
        expect(await phone.pendingOutbox(), 0);

        final song = await cloudSong(a('opening'));
        expect(song['deleted_at'], isNotNull);
        for (final id in opening.playbackSessionIds) {
          final row = (await admin.archive(
            userA,
            kind: 'listening_session',
            key: id,
          )).single;
          expect(row['is_deleted'], isTrue, reason: id);
          expect(row['payload'], <String, Object?>{}, reason: id);
        }
        for (final id in [a('m_open'), a('m_glow_passes')]) {
          final row = (await admin.archive(
            userA,
            kind: 'all_time_moment',
            key: id,
          )).single;
          expect(row['is_deleted'], isTrue, reason: id);
          expect(row['payload'], <String, Object?>{}, reason: id);
        }
        final records = await deletionRecords(userA);
        expect(records, hasLength(1));
        expect(records.single['record_key'], await lastOperation(phone));
        expect(records.single['payload']['targetId'], a('opening'));
        // Other listening and Moments untouched.
        final live = (await admin.archive(
          userA,
          kind: 'listening_session',
        )).where((r) => r['is_deleted'] != true);
        expect(live, isNotEmpty);
        expect(
          (await admin.archive(
            userA,
            kind: 'all_time_moment',
            key: a('m_echo'),
          )).single['is_deleted'],
          isFalse,
        );
      },
    );

    test('C4 charts are rebuilt without gaps and tell no new story', () async {
      await phone.finalizeCharts(now);
      final weeks = await phone.songChartWeeks();
      expect(weeks, hasLength(2));
      expect(await phone.songChart(weeks[0]), [(a('glow'), 1), (a('echo'), 2)]);
      expect(await phone.songChart(weeks[1]), [(a('echo'), 1), (a('glow'), 2)]);
      expect(
        await phone.count(
          DatabaseTables.chartMomentEvents,
          'entity_id = ? OR related_entity_id = ?',
          [a('opening'), a('opening')],
        ),
        0,
      );
      expect(
        await phone.count(DatabaseTables.chartMomentEvents),
        finalizedMomentsAfterDeletion,
        reason: 'recalculated weeks publish no new Moments',
      );
    });

    test(
      'S7 a deleted song cannot be revived in the cloud, even by its owner',
      () async {
        await expectRefused(
          () => phone.client
              .from('songs')
              .update({'deleted_at': null})
              .eq('id', a('opening')),
        );
        await expectRefused(
          () => phone.client
              .from('songs')
              .update({'deleted_at': null, 'title': 'revived'})
              .eq('id', a('opening')),
        );
        final restamped = await phone.client
            .from('songs')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', a('opening'))
            .select('deleted_at');
        expect(restamped.single['deleted_at'], isNotNull);
        // Not even with the service role.
        await expectRefused(
          () => admin.client
              .from('songs')
              .update({'deleted_at': null})
              .eq('id', a('opening')),
        );
      },
    );

    test('C5 another device of the same user applies the deletion and sends '
        'nothing of its own for it', () async {
      final before = await cloudSong(a('opening'));
      final recordsBefore = await deletionRecords(userA);
      await tablet.syncNow();

      expect(
        await tablet.count(DatabaseTables.songs, 'id = ?', [a('opening')]),
        0,
      );
      expect(
        await tablet.count(DatabaseTables.playbackSessions, 'song_id = ?', [
          a('opening'),
        ]),
        0,
      );
      expect(
        await tablet.count(
          DatabaseTables.chartMomentEvents,
          'deduplication_key IN (?, ?)',
          [a('m_open'), a('m_glow_passes')],
        ),
        0,
      );
      expect(await ledgered(tablet, 'song', a('opening')), 1);
      expect(await tablet.pendingOutbox(), 0);
      await tablet.syncNow();
      final after = await cloudSong(a('opening'));
      expect(after['server_revision'], before['server_revision']);
      expect(after['deleted_at'], before['deleted_at']);
      expect(await deletionRecords(userA), hasLength(recordsBefore.length));

      // Charts here are rebuilt from what is left.
      await tablet.finalizeCharts(now);
      final weeks = await tablet.songChartWeeks();
      expect(await tablet.songChart(weeks.first), [
        (a('glow'), 1),
        (a('echo'), 2),
      ]);
    });

    test('C6 the offline device reconnects: its stale edit and its play of the '
        'deleted song do not come back', () async {
      travel.http.offline = false;
      Object? firstError;
      try {
        await travel.syncNow();
      } on Object catch (error) {
        firstError = error;
      }
      // Whatever the first run met, a second run completes and is clean.
      await travel.syncNow();
      printOnFailure('first reconnect run: $firstError');

      expect(
        await travel.count(DatabaseTables.songs, 'id = ?', [a('opening')]),
        0,
      );
      expect(
        await travel.count(DatabaseTables.playbackSessions, 'song_id = ?', [
          a('opening'),
        ]),
        0,
      );
      expect(await ledgered(travel, 'song', a('opening')), 1);
      expect(await travel.pendingOutbox(), 0);

      final song = await cloudSong(a('opening'));
      expect(song['deleted_at'], isNotNull);
      expect(song['title'], isNot('Opening (live)'));
      final session = await admin.archive(
        userA,
        kind: 'listening_session',
        key: travelSession,
      );
      if (session.isNotEmpty) {
        expect(session.single['is_deleted'], isTrue);
        expect(session.single['payload'], <String, Object?>{});
      }

      await phone.syncNow();
      expect(
        await phone.count(DatabaseTables.playbackSessions, 'id = ?', [
          travelSession,
        ]),
        0,
      );
    });

    test('C7 a stale cloud copy (an old client\'s write) does not bring the '
        'song back', () async {
      // An old client writing over the tombstone, with a newer revision.
      final row = await cloudSong(a('opening'));
      await admin.client
          .from('songs')
          .update({
            'title': 'stale copy',
            'server_revision': (row['server_revision'] as int) + 10,
          })
          .eq('id', a('opening'));
      for (final device in [tablet, phone, travel]) {
        await device.syncNow();
        expect(
          await device.count(DatabaseTables.songs, 'id = ?', [a('opening')]),
          0,
          reason: device.name,
        );
        expect(await device.pendingOutbox(), 0, reason: device.name);
      }
      expect((await cloudSong(a('opening')))['deleted_at'], isNotNull);
    });

    test('C8 a device connecting for the first time never sees what was '
        'deleted', () async {
      laptop = await open('laptop', userA, 'a-$run@staging.invalid');
      await laptop.syncNow();
      expect(
        await laptop.count(DatabaseTables.songs, 'id = ?', [a('opening')]),
        0,
      );
      expect(
        await laptop.count(DatabaseTables.songs),
        await phone.count(DatabaseTables.songs),
      );
      expect(
        await laptop.count(DatabaseTables.playbackSessions, 'song_id = ?', [
          a('opening'),
        ]),
        0,
      );
      expect(
        await laptop.count(
          DatabaseTables.chartMomentEvents,
          "scope = 'allTime'",
        ),
        1,
      );
      expect(await ledgered(laptop, 'song', a('opening')), 1);
      expect(
        await laptop.count(DatabaseTables.libraryDeletionJournal),
        (await deletionRecords(userA)).length,
      );
      expect(await laptop.pendingOutbox(), 0);
    });

    test('C2 release and artist deletion, shared recordings confirmed, '
        'collaborations kept', () async {
      final release = await phone.deletion().preview(
        PermanentDeletionTarget.album(a('lights')),
      );
      expect(release.blockers, isEmpty);
      expect(release.songIds, {a('glow')});
      expect(release.editionIds, {a('lights_std')});
      await phone.deletion().delete(release);
      deleted.add(a('glow'));
      await phone.syncNow();
      expect(
        (await admin.libraryRow('albums', a('lights')))!['deleted_at'],
        isNotNull,
      );
      expect(
        (await admin.libraryRow(
          'album_editions',
          a('lights_std'),
        ))!['deleted_at'],
        isNotNull,
      );
      expect((await cloudSong(a('glow')))['deleted_at'], isNotNull);
      expect(
        (await admin.libraryRow('artists', a('lumen')))!['deleted_at'],
        isNull,
      );

      var artist = await phone.deletion().preview(
        PermanentDeletionTarget.artist(a('nova')),
      );
      expect(
        artist.blockers,
        contains(PermanentDeletionBlocker.sharedRecordingsNotConfirmed),
      );
      expect(artist.sharedRecordingIds, contains(a('guest')));
      const confirmed = PermanentDeletionOptions(includeSharedRecordings: true);
      artist = await phone.deletion().preview(
        PermanentDeletionTarget.artist(a('nova')),
        options: confirmed,
      );
      expect(artist.blockers, isEmpty);
      expect(artist.songIds, containsAll([a('bonus'), a('guest')]));
      expect(artist.songIds, isNot(contains(a('duet'))));
      await phone.deletion().delete(artist, options: confirmed);
      deleted.addAll(artist.songIds);
      await phone.syncNow();
      expect(await phone.pendingOutbox(), 0);

      expect(
        (await admin.libraryRow('artists', a('nova')))!['deleted_at'],
        isNotNull,
      );
      for (final album in ['nova_album']) {
        expect(
          (await admin.libraryRow('albums', a(album)))!['deleted_at'],
          isNotNull,
        );
      }
      for (final edition in ['nova_std', 'nova_dlx']) {
        expect(
          (await admin.libraryRow('album_editions', a(edition)))!['deleted_at'],
          isNotNull,
        );
      }
      for (final song in ['bonus', 'guest']) {
        expect((await cloudSong(a(song)))['deleted_at'], isNotNull);
      }
      // Echo's release and the collaboration stay, with Nova's name.
      expect(
        (await admin.libraryRow('albums', a('echoes')))!['deleted_at'],
        isNull,
      );
      final duet = await cloudSong(a('duet'));
      expect(duet['deleted_at'], isNull);
      expect('${duet['artist_credits'] ?? duet}', contains(a('nova')));
      final credit = (await (await phone.db).query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ? AND position = 1',
        whereArgs: [a('duet')],
      )).single;
      expect(credit['credited_name'], a('nova'));

      for (final device in [tablet, laptop]) {
        await device.syncNow();
        for (final song in deleted) {
          expect(
            await device.count(DatabaseTables.songs, 'id = ?', [song]),
            0,
            reason: '${device.name} $song',
          );
        }
        expect(
          await device.count(DatabaseTables.songs, 'id = ?', [a('duet')]),
          1,
        );
      }
    });

    test('C3 no listening history or Moment about a deleted song remains in '
        'the cloud', () async {
      final sessions = await admin.archive(userA, kind: 'listening_session');
      for (final row in sessions) {
        final payload = row['payload'] as Map<String, dynamic>;
        if (row['is_deleted'] == true) {
          expect(payload, isEmpty, reason: '${row['record_key']}');
          continue;
        }
        final songId = (payload['session'] as Map)['song_id'];
        expect(
          deleted,
          isNot(contains(songId)),
          reason: '${row['record_key']}',
        );
      }
      final moments = await admin.archive(userA, kind: 'all_time_moment');
      for (final row in moments) {
        final payload = row['payload'] as Map<String, dynamic>;
        if (row['is_deleted'] == true) {
          expect(payload, isEmpty);
          continue;
        }
        expect(deleted, isNot(contains(payload['entity_id'])));
        expect(deleted, isNot(contains(payload['related_entity_id'])));
      }
      expect(
        sessions.where((r) => r['is_deleted'] == true).length,
        greaterThanOrEqualTo(opening.playbackSessionIds.length + 3),
      );
    });

    test('C9 restoring a backup from before the deletions brings nothing back, '
        'here or in the cloud', () async {
      final recordsBefore = await deletionRecords(userA);
      final cloudBefore = {
        for (final song in deleted) song: await cloudSong(song),
      };
      final contents = await const BackupArchiveVerifier().verifyAndExtract(
        backupFile: preDeletionBackup,
        targetDirectory: Directory('${root.path}/restore_extract'),
      );
      final preflight = await RestorePreflightService(
        appDatabase: phone.database,
      ).assess(contents);
      expect(preflight.blockers, isEmpty);
      await (await phone.db).transaction(
        (transaction) => const SqliteRestoreExecutor().apply(
          transaction: transaction,
          backup: contents.backup,
          artworkPaths: const {},
        ),
      );
      for (final song in deleted) {
        expect(
          await phone.count(DatabaseTables.songs, 'id = ?', [song]),
          0,
          reason: song,
        );
        expect(
          await phone.count(DatabaseTables.playbackSessions, 'song_id = ?', [
            song,
          ]),
          0,
          reason: song,
        );
      }
      expect(await phone.count(DatabaseTables.songs, 'id = ?', [a('duet')]), 1);

      await phone.syncNow();
      await phone.syncNow();
      expect(await phone.pendingOutbox(), 0);
      for (final song in deleted) {
        final now = await cloudSong(song);
        expect(now['deleted_at'], isNotNull, reason: song);
        expect(
          now['server_revision'],
          cloudBefore[song]!['server_revision'],
          reason: '$song: nothing was sent for it',
        );
      }
      expect(await deletionRecords(userA), hasLength(recordsBefore.length));
      for (final row in await admin.archive(userA, kind: 'listening_session')) {
        if (row['is_deleted'] == true) continue;
        final songId = ((row['payload'] as Map)['session'] as Map)['song_id'];
        expect(deleted, isNot(contains(songId)));
      }
    });

    test('C10 a lost response is retried without duplicates; applying a '
        'deletion twice changes nothing', () async {
      final impact = await phone.deletion().preview(
        PermanentDeletionTarget.song(a('x1')),
      );
      expect(impact.blockers, isEmpty);
      await phone.deletion().delete(impact);
      deleted.add(a('x1'));
      final operation = await lastOperation(phone);

      phone.http.loseResponse = (request, body) =>
          request.method == 'POST' &&
          request.url.path.endsWith('/sonus_archive_records') &&
          body.contains('"library_deletion"');
      await expectLater(phone.syncNow(), throwsA(anything));
      expect(phone.http.lost, greaterThan(0));
      // The server did commit it.
      expect(await admin.archive(userA, key: operation), hasLength(1));
      phone.http.clearFaults();

      await phone.syncNow();
      await phone.syncNow();
      expect(await admin.archive(userA, key: operation), hasLength(1));
      expect((await cloudSong(a('x1')))['deleted_at'], isNotNull);
      expect(await phone.pendingOutbox(), 0);

      await tablet.syncNow();
      await tablet.syncNow();
      expect(
        await tablet.count(DatabaseTables.libraryDeletionJournal, 'id = ?', [
          operation,
        ]),
        1,
      );
      expect(await tablet.count(DatabaseTables.songs, 'id = ?', [a('x1')]), 0);
    });

    test('C11 interrupted: the app closes after the deletion, and the '
        'connection drops during the archive push', () async {
      // Closed before any sync.
      var impact = await phone.deletion().preview(
        PermanentDeletionTarget.song(a('x2')),
      );
      await phone.deletion().delete(impact);
      deleted.add(a('x2'));
      final closedOperation = await lastOperation(phone);
      await phone.restart();
      await phone.syncNow();
      expect((await cloudSong(a('x2')))['deleted_at'], isNotNull);
      expect(await admin.archive(userA, key: closedOperation), hasLength(1));

      // Dropped after the first archive write.
      impact = await phone.deletion().preview(
        PermanentDeletionTarget.song(a('x3')),
      );
      await phone.deletion().delete(impact);
      deleted.add(a('x3'));
      final droppedOperation = await lastOperation(phone);
      var writes = 0;
      phone.http.refuse = (request, body) =>
          request.method != 'GET' &&
          request.method != 'HEAD' &&
          request.url.path.endsWith('/sonus_archive_records') &&
          ++writes > 1;
      await expectLater(phone.syncNow(), throwsA(anything));
      phone.http.clearFaults();
      await phone.restart();
      await phone.syncNow();
      await phone.syncNow();

      expect((await cloudSong(a('x3')))['deleted_at'], isNotNull);
      expect(await admin.archive(userA, key: droppedOperation), hasLength(1));
      for (final id in impact.playbackSessionIds) {
        final row = (await admin.archive(
          userA,
          kind: 'listening_session',
          key: id,
        )).single;
        expect(row['is_deleted'], isTrue);
        expect(row['payload'], <String, Object?>{});
      }
      expect(await phone.pendingOutbox(), 0);
    });

    test('C12 a verified duplicate merged on one device is merged on the '
        'others, and their plays follow the kept release', () async {
      tabletDuplicatePlay = await tablet.play(a('d1b'), thisWeek);
      final plan = await phone.reconciliation().plan();
      printOnFailure(
        'merges: ${plan.merges.map((m) => '${m.keptAlbumId}<-${m.duplicateAlbumId}')} '
        'reviews: ${plan.reviews.map((r) => '${r.albumIds} ${r.reason}')}',
      );
      final merge = plan.merges.singleWhere(
        (m) => m.duplicateAlbumId == a('dup_b'),
      );
      expect(merge.keptAlbumId, a('dup_a'));
      final report = await phone.reconciliation().reconcile(approved: plan);
      expect(report.merged, hasLength(plan.merges.length));
      await phone.syncNow();
      expect(await phone.pendingOutbox(), 0);
      expect(
        (await admin.libraryRow('albums', a('dup_b')))!['deleted_at'],
        isNotNull,
      );
      expect((await cloudSong(a('d1b')))['deleted_at'], isNotNull);
      expect(
        (await admin.libraryRow('albums', a('dup_a')))!['deleted_at'],
        isNull,
      );
      final records = await deletionRecords(userA);
      expect(
        records.where((r) => r['payload']['operation'] == 'duplicateMerge'),
        hasLength(1),
      );

      await tablet.syncNow();
      await tablet.syncNow();
      expect(
        await tablet.count(DatabaseTables.albums, 'id = ?', [a('dup_b')]),
        0,
      );
      expect(await tablet.count(DatabaseTables.songs, 'id = ?', [a('d1b')]), 0);
      final moved = (await (await tablet.db).query(
        DatabaseTables.playbackSessions,
        where: 'id = ?',
        whereArgs: [tabletDuplicatePlay],
      )).single;
      expect(moved['song_id'], a('d1a'));
      expect(moved['album_id'], a('dup_a'));
      expect(
        await tablet.count(DatabaseTables.qualifiedPlays, 'song_id = ?', [
          a('d1b'),
        ]),
        0,
      );

      // The play the tablet sent before it knew of the merge, on the phone
      // and on a device that never had the duplicate.
      await phone.syncNow();
      await laptop.syncNow();
      for (final device in [phone, tablet, laptop]) {
        expect(
          await device.count(
            DatabaseTables.playbackSessions,
            'song_id NOT IN (SELECT id FROM ${DatabaseTables.songs})',
          ),
          0,
          reason: '${device.name}: no listening left pointing at nothing',
        );
      }
      for (final device in [phone, laptop]) {
        expect(
          await device.count(DatabaseTables.playbackSessions, 'song_id = ?', [
            a('d1a'),
          ]),
          3,
          reason: device.name,
        );
      }
    });

    test('C13 a deletion that depends on a library change waits for it, then '
        'applies', () async {
      // The phone's library writes fail; its archive writes go through.
      phone.http.refuse = (request, body) =>
          request.method != 'GET' &&
          request.method != 'HEAD' &&
          request.url.path.contains('/rest/v1/') &&
          !request.url.path.endsWith('/sonus_archive_records') &&
          !request.url.path.endsWith('/sonus_capabilities');
      final impact = await phone.deletion().preview(
        PermanentDeletionTarget.edition(a('twin_std')),
      );
      expect(impact.blockers, isEmpty);
      expect(impact.songIds, isEmpty);
      await phone.deletion().delete(impact);
      final operation = await lastOperation(phone);
      await expectLater(phone.syncNow(), throwsA(anything));
      expect(await admin.archive(userA, key: operation), hasLength(1));
      expect(
        (await cloudSong(a('t1')))['album_edition_id'],
        a('twin_std'),
        reason: 'the new home has not reached the cloud',
      );

      await tablet.syncNow();
      expect(
        await tablet.count(DatabaseTables.libraryDeletionJournal, 'id = ?', [
          operation,
        ]),
        0,
        reason: 'waiting',
      );
      expect(
        await tablet.count(DatabaseTables.albumEditions, 'id = ?', [
          a('twin_std'),
        ]),
        1,
      );
      expect(await tablet.count(DatabaseTables.songs, 'id = ?', [a('t1')]), 1);

      phone.http.clearFaults();
      await phone.syncNow();
      expect(await phone.pendingOutbox(), 0);
      await tablet.syncNow();
      expect(
        await tablet.count(DatabaseTables.libraryDeletionJournal, 'id = ?', [
          operation,
        ]),
        1,
      );
      expect(
        await tablet.count(DatabaseTables.albumEditions, 'id = ?', [
          a('twin_std'),
        ]),
        0,
      );
      final t1 = (await (await tablet.db).query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: [a('t1')],
      )).single;
      expect(t1['album_edition_id'], a('twin_dlx'));
    });

    test('C15 the other user sees none of this', () async {
      await other.syncNow();
      expect(
        await other.count(DatabaseTables.songs, 'id LIKE ?', ['${run}_a_%']),
        0,
      );
      expect(
        await other.count(DatabaseTables.playbackSessions, 'song_id LIKE ?', [
          '${run}_a_%',
        ]),
        0,
      );
      expect(await other.count(DatabaseTables.libraryDeletionLedger), 0);
      expect(await other.count(DatabaseTables.libraryDeletionJournal), 0);
      expect(
        await other.count(DatabaseTables.songs, 'id = ?', [b('solo_song')]),
        1,
      );
      expect(
        await other.client
            .from('sonus_archive_records')
            .select()
            .eq('kind', 'library_deletion'),
        isEmpty,
      );
      expect((await cloudSong(b('solo_song')))['deleted_at'], isNull);
      expect(await deletionRecords(userB), isEmpty);
    });
  });
}
