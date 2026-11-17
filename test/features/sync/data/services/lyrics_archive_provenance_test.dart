// App Update 1.3 (database version 48): the lyrics compatibility gate.
// Outbound lyrics sync is off; inbound records never replace the
// listener's edit or recorded provenance, and an older build's record
// (without the provenance marker) only reaches legacy rows. Disposable
// data and an in-memory archive only: no real cloud.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/sync/application/services/cloud_archive_sync_service.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';
import 'package:sonus_next/features/sync/domain/models/lyrics_archive_sync_gate.dart';

import '../../../../support/in_memory_cloud_archive.dart';
import '../../../../support/recovery_fixtures.dart';

const _user = 'user-1';
const _edited = '2026-11-10T00:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase app;
  late SqliteCloudArchiveStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_lyrics_gate_');
    app = fileAppDatabase(root, 'device.db');
    // One song with a legacy lyrics row ('Lyrics a', no provenance).
    await seedConnectedLibrary(await app.database, key: 'a');
    store = SqliteCloudArchiveStore(
      appDatabase: app,
      changes: LibraryChangeSignal(),
    );
  });

  tearDown(() async {
    await app.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> lyrics() async =>
      (await (await app.database).query(DatabaseTables.trackLyrics)).single;

  Future<void> setLyrics(Map<String, Object?> values) async =>
      (await app.database).update(DatabaseTables.trackLyrics, values);

  Future<void> apply(Map<String, Object?> payload) async {
    final outcome = await store.apply(
      CloudArchiveRecord(
        kind: CloudArchiveKind.lyrics,
        key: 'song-a',
        payload: {
          'song_id': 'song-a',
          'created_at': fixtureTimestamp,
          'updated_at': '2026-11-12T00:00:00.000Z',
          ...payload,
        },
        clientUpdatedAt: DateTime.utc(2026, 11, 12),
      ),
    );
    expect(outcome, CloudArchiveApplyOutcome.applied);
  }

  Map<String, Object?> marked(Map<String, Object?> payload) => {
    ...payload,
    LyricsArchiveSyncGate.markerKey: LyricsArchiveSyncGate.provenanceSchema,
  };

  Future<CloudArchiveRecord?> collected() async => (await store.collect())
      .where((r) => r.kind == CloudArchiveKind.lyrics)
      .singleOrNull;

  group('outbound', () {
    test('is off by default', () {
      expect(LyricsArchiveSyncGate.uploadsEnabled, isFalse);
    });

    test('a legacy row keeps exactly the payload (and fingerprint) earlier '
        'builds made', () async {
      final record = (await collected())!;
      expect(record.payload, {
        'song_id': 'song-a',
        'plain_text': 'Lyrics a',
        'synced_text': null,
        'created_at': fixtureTimestamp,
        'updated_at': fixtureTimestamp,
      });
    });

    test('provenance travels only when set, with the marker', () async {
      await setLyrics({
        'plain_source': 'user',
        'plain_user_edited_at': _edited,
      });
      final payload = (await collected())!.payload;
      expect(payload['plain_source'], 'user');
      expect(payload['plain_user_edited_at'], _edited);
      expect(payload.containsKey('synced_source'), isFalse);
      expect(payload.containsKey('offset_ms'), isFalse);
      expect(LyricsArchiveSyncGate.isMarked(payload), isTrue);
    });

    test('display-only text never leaves the device', () async {
      await setLyrics({
        'plain_text': 'Licensed',
        'plain_source': 'provider',
        'synced_text': '[00:01.00]Mine',
        'synced_source': 'sidecarLrc',
        'provider': 'p',
        'provider_licence': 'displayOnly',
      });
      final payload = (await collected())!.payload;
      expect(
        payload.containsKey('plain_text') && payload['plain_text'] != null,
        isFalse,
      );
      expect(payload.values, isNot(contains('Licensed')));
      expect(payload['synced_text'], '[00:01.00]Mine');
      expect(payload.containsKey('provider_licence'), isFalse);

      await setLyrics({'synced_text': null, 'synced_source': null});
      expect(await collected(), isNull, reason: 'nothing portable is left');
    });

    test('the service uploads no lyrics record and records no lyrics '
        'removal', () async {
      final cloud = InMemoryCloudArchive();
      CloudArchiveSyncService service({bool? uploadLyrics}) =>
          uploadLyrics == null
          ? CloudArchiveSyncService(
              gateway: cloud,
              store: store,
              queueArtworkUpload:
                  ({required userId, required artworkId}) async {},
            )
          : CloudArchiveSyncService(
              gateway: cloud,
              store: store,
              queueArtworkUpload:
                  ({required userId, required artworkId}) async {},
              uploadLyrics: uploadLyrics,
            );

      await service().synchronize(_user);
      expect(cloud.rowsFor(_user).keys, isNot(contains('lyrics:song-a')));
      expect(cloud.rowsFor(_user).keys, contains('playlist:playlist-a'));

      // An agreement made while uploads were open (as an older build
      // would): with the gate closed, removing the row here sends nothing.
      await service(uploadLyrics: true).synchronize(_user);
      final before = cloud.rowsFor(_user)['lyrics:song-a']!;
      await (await app.database).delete(DatabaseTables.trackLyrics);
      final writes = cloud.writes;
      await service().synchronize(_user);
      expect(cloud.writes, writes);
      expect(cloud.rowsFor(_user)['lyrics:song-a']!.isDeleted, isFalse);
      expect(
        cloud.rowsFor(_user)['lyrics:song-a']!.fingerprint,
        before.fingerprint,
      );
    });
  });

  group('inbound from an older build (no marker)', () {
    test('never touches a row with provenance', () async {
      await setLyrics({
        'plain_text': 'My words',
        'plain_source': 'user',
        'plain_user_edited_at': _edited,
      });
      final before = await lyrics();
      await apply({'plain_text': 'Old build', 'synced_text': '[00:01.00]X'});
      expect(await lyrics(), before);

      await setLyrics({
        'plain_source': 'embedded',
        'plain_user_edited_at': null,
      });
      final imported = await lyrics();
      await apply({'plain_text': 'Old build'});
      expect(await lyrics(), imported);
    });

    test('cannot plant provenance it claims', () async {
      await apply({
        'plain_text': 'Old build',
        'plain_source': 'user',
        'plain_user_edited_at': '2030-01-01T00:00:00.000Z',
      });
      final row = await lyrics();
      expect(row['plain_text'], 'Old build');
      expect(row['plain_source'], isNull);
      expect(row['plain_user_edited_at'], isNull);
    });

    test('updates a legacy row as before, but never clears a text', () async {
      await setLyrics({'synced_text': '[00:01.00]Kept'});
      await apply({'plain_text': 'Newer words', 'synced_text': null});
      final row = await lyrics();
      expect(row['plain_text'], 'Newer words');
      expect(row['synced_text'], '[00:01.00]Kept');
    });

    test('fills a song with no lyrics', () async {
      await (await app.database).delete(DatabaseTables.trackLyrics);
      await apply({'plain_text': 'From the cloud'});
      final row = await lyrics();
      expect(row['plain_text'], 'From the cloud');
      expect(row['plain_source'], isNull);
    });
  });

  group('inbound with the provenance marker', () {
    test(
      'a remote edit replaces imported text; the other text stays',
      () async {
        await setLyrics({
          'plain_source': 'embedded',
          'synced_text': '[00:01.00]Mine',
          'synced_source': 'sidecarLrc',
        });
        await apply(
          marked({
            'plain_text': 'Edited elsewhere',
            'plain_source': 'user',
            'plain_user_edited_at': _edited,
          }),
        );
        final row = await lyrics();
        expect(row['plain_text'], 'Edited elsewhere');
        expect(row['plain_source'], 'user');
        expect(row['synced_text'], '[00:01.00]Mine');
      },
    );

    test('no remote automatic text replaces a local edit', () async {
      await setLyrics({
        'plain_text': 'My words',
        'plain_source': 'user',
        'plain_user_edited_at': _edited,
      });
      final before = await lyrics();
      await apply(
        marked({'plain_text': 'Provider', 'plain_source': 'provider'}),
      );
      await apply(
        marked({
          'plain_text': 'Older edit',
          'plain_source': 'user',
          'plain_user_edited_at': '2026-11-09T00:00:00.000Z',
        }),
      );
      expect(await lyrics(), before);
    });

    test('display-only text is never stored from another device', () async {
      await (await app.database).delete(DatabaseTables.trackLyrics);
      await apply(
        marked({
          'plain_text': 'Licensed',
          'plain_source': 'provider',
          'synced_text': '[00:01.00]Free',
          'synced_source': 'embedded',
          'provider': 'p',
          'provider_licence': 'displayOnly',
        }),
      );
      final row = await lyrics();
      expect(row['plain_text'], isNull);
      expect(row['synced_text'], '[00:01.00]Free');
      expect(row['provider_licence'], isNull);
    });
  });
}
