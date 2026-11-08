// App Update 1.2 staging validation, C14: against a server WITHOUT
// migration 20261108000001 (rolled back on the isolated stack), a device
// linked to cloud sync cannot permanently delete, nothing changes anywhere,
// and ordinary sync still works.
//
// Runs only with --dart-define=SONUS_STAGING_PHASE=no-capability (see
// permanent_deletion_staging_test.dart for the other defines).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';

import 'support/staging_guard.dart';
import 'support/staging_world.dart';

void main() {
  final config = stagingConfig();
  if (config == null || config.phase != 'no-capability') {
    test(
      'C14 server without the capability',
      () {},
      skip: 'runs only in the no-capability staging phase',
    );
    return;
  }

  final run = 'nc${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  String a(String id) => '${run}_$id';
  const password = 'staging-password-not-secret';

  late Directory root;
  late StagingAdmin admin;
  late String user;
  late StagingDevice phone;
  late StagingDevice tablet;

  setUpAll(() async {
    admin = StagingAdmin(config);
    await admin.assertStagingServer();
    root = await Directory.systemTemp.createTemp('sonus_staging_nc_');
    user = await admin.createUser('nc-$run@staging.invalid', password);
    Future<StagingDevice> open(String name) => StagingDevice.open(
      name: name,
      root: root,
      config: config,
      email: 'nc-$run@staging.invalid',
      password: password,
      userId: user,
    );
    phone = await open('phone');
    tablet = await open('tablet');
  });

  tearDownAll(() async {
    await phone.close();
    await tablet.close();
    await admin.client.dispose();
    await root.delete(recursive: true);
  });

  test('C14 the server is really without the capability', () async {
    expect(await phone.sync.deletionReadiness.isReady(), isFalse);
  });

  test('C14 a linked device cannot delete; nothing changes anywhere; sync '
      'still works', () async {
    await phone.artist(a('nova'));
    await phone.album(a('album'), a('nova'), [a('std')]);
    await phone.song(
      a('song'),
      artistId: a('nova'),
      albumId: a('album'),
      home: a('std'),
    );
    await phone.play(a('song'), DateTime.utc(2026, 10, 6, 12));
    await phone.syncNow();
    await tablet.syncNow();
    expect(await tablet.count(DatabaseTables.songs, 'id = ?', [a('song')]), 1);

    final impact = await phone.deletion().preview(
      PermanentDeletionTarget.song(a('song')),
    );
    expect(
      impact.blockers,
      contains(PermanentDeletionBlocker.cloudDeletionUnavailable),
    );
    await expectLater(
      phone.deletion().delete(impact),
      throwsA(isA<DeletionBlocked>()),
    );

    // Nothing changed here, in the cloud, or on the other device.
    expect(await phone.count(DatabaseTables.songs, 'id = ?', [a('song')]), 1);
    expect(await phone.count(DatabaseTables.playbackSessions), 1);
    expect(await phone.count(DatabaseTables.libraryDeletionLedger), 0);
    expect(await phone.count(DatabaseTables.libraryDeletionJournal), 0);
    expect(await phone.pendingOutbox(), 0);
    await phone.syncNow();
    expect((await admin.libraryRow('songs', a('song')))!['deleted_at'], isNull);
    final archive = await admin.archive(user);
    expect(archive.where((r) => r['kind'] == 'library_deletion'), isEmpty);
    expect(archive.where((r) => r['is_deleted'] == true), isEmpty);
    await tablet.syncNow();
    expect(await tablet.count(DatabaseTables.songs, 'id = ?', [a('song')]), 1);
    expect(await tablet.count(DatabaseTables.playbackSessions), 1);
  });
}
