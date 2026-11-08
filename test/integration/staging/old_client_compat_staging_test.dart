// App Update 1.2 staging validation: old-client compatibility. Runs in two
// phases alternating with the App Update 1.1 client (4f7a36d) driven from
// its own worktree against the same isolated stack:
//   old-a  (1.1)   a 1.1 device seeds a library and history, syncs;
//   old-b  (this)  a 1.2 device permanently deletes a song;
//   old-c  (1.1)   the 1.1 device syncs again, keeps using its stale copy;
//                  a fresh 1.1 install connects;
//   old-d  (this)  the 1.2 device syncs; nothing came back.
// Hand-off files live outside the repository (test_runs). Skipped unless
// --dart-define=SONUS_STAGING_PHASE=old-b or old-d.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';

import 'support/staging_guard.dart';
import 'support/staging_world.dart';

const _dir = r'C:\dev\sonus\test_runs\au12\staging\oldclient';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File(p.join(_dir, name)).readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final config = stagingConfig();
  if (config == null || !const {'old-b', 'old-d'}.contains(config.phase)) {
    test(
      'old-client compatibility',
      () {},
      skip: 'runs only in the old-b / old-d staging phases',
    );
    return;
  }

  late StagingAdmin admin;
  late StagingDevice modern;
  final h = _read('handoff.json');
  final run = h['run'] as String;
  final user = h['userId'] as String;
  String id(String x) => '${run}_$x';

  setUpAll(() async {
    admin = StagingAdmin(config);
    await admin.assertStagingServer();
    modern = await StagingDevice.open(
      name: 'modern',
      root: await Directory(p.join(_dir, 'devices')).create(recursive: true),
      config: config,
      email: h['email'] as String,
      password: h['password'] as String,
      userId: user,
    );
  });

  tearDownAll(() async {
    await modern.close();
    await admin.client.dispose();
  });

  if (config.phase == 'old-b') {
    test(
      'old-b: a 1.2 device deletes a song the 1.1 device uploaded',
      () async {
        await modern.syncNow();
        expect(
          await modern.count(DatabaseTables.songs, 'id = ?', [id('target')]),
          1,
        );
        final impact = await modern.deletion().preview(
          PermanentDeletionTarget.song(id('target')),
        );
        expect(impact.blockers, isEmpty);
        expect(impact.playbackSessionIds, hasLength(2));
        await modern.deletion().delete(impact);
        await modern.syncNow();
        expect(await modern.pendingOutbox(), 0);

        expect(
          (await admin.libraryRow('songs', id('target')))!['deleted_at'],
          isNotNull,
        );
        final record = (await admin.archive(
          user,
          kind: 'library_deletion',
        )).single;
        File(p.join(_dir, 'phase_b.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'deletedSessions': impact.playbackSessionIds.toList(),
            'recordPayload': record['payload'],
            'recordRevision': record['server_revision'],
          }),
        );
      },
    );
  }

  if (config.phase == 'old-d') {
    test('old-d: after the 1.1 devices, nothing came back on the 1.2 device '
        'or in the cloud', () async {
      final c = _read('phase_c.json');
      await modern.syncNow();
      await modern.syncNow();
      expect(
        await modern.count(DatabaseTables.songs, 'id = ?', [id('target')]),
        0,
      );
      expect(
        await modern.count(DatabaseTables.playbackSessions, 'song_id = ?', [
          id('target'),
        ]),
        0,
      );
      expect(await modern.pendingOutbox(), 0);
      final song = (await admin.libraryRow('songs', id('target')))!;
      expect(song['deleted_at'], isNotNull);
      expect(song['title'], id('target'));
      // Listening the 1.1 device recorded for the deleted song afterwards:
      // removed from the cloud by the 1.2 device, emptied.
      final stale = c['stalePlay'] as String?;
      expect(stale, isNotNull);
      final row = (await admin.archive(
        user,
        kind: 'listening_session',
        key: stale,
      )).single;
      expect(row['is_deleted'], isTrue);
      expect(row['payload'], <String, Object?>{});
      final live = (await admin.archive(user, kind: 'listening_session')).where(
        (r) =>
            r['is_deleted'] != true &&
            ((r['payload'] as Map)['session'] as Map)['song_id'] ==
                id('target'),
      );
      expect(live, isEmpty);
    });
  }
}
