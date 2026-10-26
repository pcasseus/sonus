// Release readiness: a genuinely new library on a reinstalled device, with
// disposable accounts and databases only. The old account's cloud library
// must not repopulate the new library, and must stay exactly as it was.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/account/data/repositories/sqlite_local_account_binding_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_archive_sync_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_library_first_link_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';

import '../../support/in_memory_cloud_archive.dart';
import '../../support/recovery_fixtures.dart';

const _oldAccount = 'old-account';
const _newAccount = 'new-account';

class _CloudLibraries implements CloudLibraryProbe {
  _CloudLibraries(this.cloud);

  final InMemoryCloudArchive cloud;

  @override
  Future<bool> hasLibrary(String userId) async =>
      cloud.rowsFor(userId).isNotEmpty;
}

class _Consent implements CloudLibraryConsentStore {
  final granted = <String>{};

  @override
  Future<bool> hasConsent(String userId) async => granted.contains(userId);

  @override
  Future<void> grant(String userId) async => granted.add(userId);
}

/// A device composed like the app: the first-link guard, then the account
/// binding, then the archive. The library tables are covered by the same
/// guard, which runs before anything else.
class _Device {
  _Device(this.database, InMemoryCloudArchive cloud)
    : binding = SqliteLocalAccountBindingRepository(appDatabase: database) {
    final archive = CloudArchiveSyncService(
      gateway: cloud,
      store: SqliteCloudArchiveStore(
        appDatabase: database,
        changes: LibraryChangeSignal(),
      ),
      queueArtworkUpload: ({required userId, required artworkId}) async {},
    );
    final guard = CloudLibraryFirstLinkGuard(
      boundUserId: () async => (await binding.getBinding())?.userId,
      probe: _CloudLibraries(cloud),
      consent: consent,
    );
    service = SyncService.forTesting(
      bindToUser: binding.bindToUser,
      claimUnowned: (_) async => 0,
      attachAccount: (userId) async {
        await binding.bindToUser(userId);
        return 0;
      },
      getPending: (_) async => const [],
      pushPending: (_) async {},
      pullAll: (_) async => 0,
      firstLinkGuard: guard.check,
      syncArchive: archive.synchronize,
    );
  }

  final AppDatabase database;
  final SqliteLocalAccountBindingRepository binding;
  final consent = _Consent();
  late final SyncService service;

  Future<Database> get db => database.database;
}

void main() {
  late Directory root;
  late InMemoryCloudArchive cloud;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_fresh_start_');
    cloud = InMemoryCloudArchive();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<_Device> device(String name) async {
    final database = fileAppDatabase(root, '$name.db');
    addTearDown(database.close);
    return _Device(database, cloud);
  }

  /// The old library, already in the old account's cloud.
  Future<Map<String, Object>> oldCloudLibrary() async {
    final old = await device('old-phone');
    await seedConnectedLibrary(await old.db, key: 'old');
    await old.service.synchronize(_oldAccount);
    expect(cloud.rowsFor(_oldAccount), isNotEmpty);
    return {
      for (final MapEntry(:key, :value) in cloud.rowsFor(_oldAccount).entries)
        key: '${value.serverRevision}:${value.fingerprint}',
    };
  }

  /// A reinstalled device whose new library came from the folder importer.
  Future<_Device> reinstalledDevice() async {
    final fresh = await device('reinstalled');
    await seedConnectedLibrary(await fresh.db, key: 'new', songTitle: 'New');
    return fresh;
  }

  test('the old account cannot repopulate the new library', () async {
    final oldCloud = await oldCloudLibrary();
    final fresh = await reinstalledDevice();
    final before = await snapshotDatabase(await fresh.db);

    await expectLater(
      fresh.service.synchronize(_oldAccount),
      throwsA(isA<SyncNeedsCloudLibraryChoice>()),
    );

    expect(await snapshotDatabase(await fresh.db), before);
    expect(await fresh.binding.getBinding(), isNull);
    expect({
      for (final MapEntry(:key, :value) in cloud.rowsFor(_oldAccount).entries)
        key: '${value.serverRevision}:${value.fingerprint}',
    }, oldCloud);
  });

  test('a new account syncs the new library and leaves the old one', () async {
    final oldCloud = await oldCloudLibrary();
    final fresh = await reinstalledDevice();

    final result = await fresh.service.synchronize(_newAccount);
    final again = await fresh.service.synchronize(_newAccount);

    expect(result.userId, _newAccount);
    expect(again.userId, _newAccount);
    expect((await fresh.binding.getBinding())!.userId, _newAccount);
    expect(cloud.rowsFor(_newAccount).keys, {
      'playlist:playlist-new',
      'listening_session:session-new',
      'lyrics:song-new',
    });
    expect({
      for (final MapEntry(:key, :value) in cloud.rowsFor(_oldAccount).entries)
        key: '${value.serverRevision}:${value.fingerprint}',
    }, oldCloud);
    final playlists = await (await fresh.db).query(DatabaseTables.playlists);
    expect([for (final p in playlists) p['id']], ['playlist-new']);
  });

  test('once linked, the old account is refused as before', () async {
    await oldCloudLibrary();
    final fresh = await reinstalledDevice();
    await fresh.service.synchronize(_newAccount);

    await expectLater(
      fresh.service.synchronize(_oldAccount),
      throwsA(isA<LocalAccountBindingConflict>()),
    );
  });

  test('choosing to bring the old library merges it, nothing lost', () async {
    await oldCloudLibrary();
    final fresh = await reinstalledDevice();
    await fresh.consent.grant(_oldAccount);

    await fresh.service.synchronize(_oldAccount);

    final db = await fresh.db;
    final sessions = await db.query(
      DatabaseTables.playbackSessions,
      orderBy: 'id',
    );
    expect([for (final s in sessions) s['id']], ['session-new', 'session-old']);
    final playlists = await db.query(DatabaseTables.playlists, orderBy: 'id');
    expect([for (final p in playlists) p['id']], ['playlist-new']);
    final waiting = await db.query(
      DatabaseTables.cloudArchiveState,
      where: 'pending_apply = 1',
    );
    expect(
      {for (final w in waiting) w['record_key']},
      {'playlist-old', 'song-old'},
      reason: 'they apply once library sync brings the old songs',
    );
  });
}
