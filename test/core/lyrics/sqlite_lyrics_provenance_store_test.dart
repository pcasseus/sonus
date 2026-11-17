// App Update 1.3 (database version 48): the provenance-aware lyrics writer
// and the import path that uses it, on a real database.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/lyrics/lyrics_provenance.dart';
import 'package:sonus_next/core/lyrics/sqlite_lyrics_provenance_store.dart';
import 'package:sonus_next/features/import/application/lyrics/id3_lyrics_reader.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';

import '../../support/recovery_fixtures.dart';

class _Sidecar implements LyricsSourceReader {
  _Sidecar(this.text);
  String? text;

  @override
  Future<String?> read(ImportCandidate candidate) async => text;
}

ImportCandidate _candidate(String lyricsPath) => ImportCandidate(
  filePath: 'song.mp3',
  normalizedPath: 'song.mp3',
  discoveredAt: DateTime(2026),
  lyricsPath: lyricsPath,
);

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase app;
  late SqliteLyricsProvenanceStore store;
  var clock = DateTime.utc(2026, 11, 16, 10);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_lyrics_store_');
    app = fileAppDatabase(root, 'store.db');
    await seedConnectedLibrary(await app.database, key: 'a');
    // The fixture's legacy row is removed; each test sets what it needs.
    await (await app.database).delete(DatabaseTables.trackLyrics);
    clock = DateTime.utc(2026, 11, 16, 10);
    store = SqliteLyricsProvenanceStore(appDatabase: app, now: () => clock);
  });

  tearDown(() async {
    await app.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> row() async => (await store.read('song-a'))!;

  Future<LyricsWriteResult> auto({
    String? plain,
    String? synced,
    LyricsSource source = LyricsSource.embedded,
    double? confidence,
    LyricsProviderDetails? provider,
  }) => store.saveAutomatic(
    songId: 'song-a',
    plain: plain == null
        ? null
        : LyricsCandidate(text: plain, source: source, confidence: confidence),
    synced: synced == null
        ? null
        : LyricsCandidate(text: synced, source: source, confidence: confidence),
    provider: provider,
  );

  test('an automatic write records each text with its own source and '
      'time', () async {
    await auto(plain: 'Tag words');
    clock = clock.add(const Duration(minutes: 1));
    await auto(synced: '[00:01.00]Line', source: LyricsSource.sidecarLrc);

    final stored = await row();
    expect(stored['plain_text'], 'Tag words');
    expect(stored['plain_source'], 'embedded');
    expect(stored['plain_updated_at'], '2026-11-16T10:00:00.000Z');
    expect(stored['synced_text'], '[00:01.00]Line');
    expect(stored['synced_source'], 'sidecarLrc');
    expect(stored['synced_updated_at'], '2026-11-16T10:01:00.000Z');
    expect(stored['plain_user_edited_at'], isNull);
  });

  test('no automatic source replaces a listener edit; the other text, '
      'and the offset, stay', () async {
    await auto(plain: 'Tag words', synced: '[00:01.00]Tag');
    await store.saveUserEdit(
      songId: 'song-a',
      kind: LyricsTextKind.plain,
      text: 'My words',
    );
    await store.setUserOffset('song-a', const Duration(milliseconds: 300));

    for (final source in [
      LyricsSource.provider,
      LyricsSource.embedded,
      LyricsSource.sidecarLrc,
      LyricsSource.sidecarTxt,
      LyricsSource.generated,
    ]) {
      clock = clock.add(const Duration(minutes: 1));
      final result = await auto(
        plain: 'From $source',
        source: source,
        confidence: source == LyricsSource.generated ? 0.5 : null,
        provider: source == LyricsSource.provider
            ? const LyricsProviderDetails(
                provider: 'p',
                licence: LyricsLicence.cacheable,
              )
            : null,
      );
      expect(result.plain, isFalse, reason: '$source');
    }

    final stored = await row();
    expect(stored['plain_text'], 'My words');
    expect(stored['plain_source'], 'user');
    expect(stored['plain_user_edited_at'], isNotNull);
    expect(stored['synced_text'], '[00:01.00]Tag');
    expect(stored['offset_ms'], 300);
  });

  test('a worse source never replaces a better one', () async {
    await auto(synced: '[00:01.00]Tag');
    final result = await auto(
      synced: '[00:01.00]Sidecar',
      source: LyricsSource.sidecarTxt,
    );
    expect(result.synced, isFalse);
    expect((await row())['synced_text'], '[00:01.00]Tag');

    // Generated text is lowest: it fills a gap only, flagged and scored.
    await auto(plain: 'Guess', source: LyricsSource.generated, confidence: .6);
    final stored = await row();
    expect(stored['plain_source'], 'generated');
    expect(stored['plain_confidence'], 0.6);
    await auto(plain: 'Real', source: LyricsSource.sidecarTxt);
    expect((await row())['plain_text'], 'Real');
  });

  test('live-only provider text is never written; display-only is kept '
      'on this device only', () async {
    final none = await auto(
      plain: 'Live only',
      source: LyricsSource.provider,
      provider: const LyricsProviderDetails(
        provider: 'p',
        licence: LyricsLicence.noStore,
      ),
    );
    expect(none.plain, isFalse);
    expect(await store.read('song-a'), isNull);

    await auto(
      plain: 'Licensed',
      source: LyricsSource.provider,
      provider: const LyricsProviderDetails(
        provider: 'p',
        reference: 'ref-1',
        licence: LyricsLicence.displayOnly,
        language: 'en',
      ),
    );
    final stored = await row();
    expect(stored['plain_text'], 'Licensed');
    expect(stored['provider_licence'], 'displayOnly');
    expect(stored['provider_ref'], 'ref-1');
    expect(LyricsRows.portable(stored), isNull);
  });

  test('an offset beyond 10 minutes is refused', () async {
    expect(
      () => store.setUserOffset('song-a', const Duration(minutes: 11)),
      throwsArgumentError,
    );
  });

  group('import rescans', () {
    Future<void> ingest(String? sidecar, {String path = 'song.lrc'}) =>
        LyricsIngestionService(
          sourceReader: _Sidecar(sidecar),
          lyricsWriter: store,
          embeddedReader: (_) async => null,
        ).ingest(candidate: _candidate(path), songId: 'song-a');

    test('record the sidecar kind from its file name', () async {
      await ingest('[00:01.00]Timed', path: 'Song.LRC');
      await ingest('Plain words', path: 'song.txt');
      final stored = await row();
      expect(stored['synced_source'], 'sidecarLrc');
      expect(stored['plain_source'], 'sidecarTxt');
    });

    test('a sidecar with one kind of text leaves the other alone', () async {
      await ingest('Plain words', path: 'song.txt');
      await ingest('[00:01.00]Timed');
      final stored = await row();
      expect(stored['plain_text'], 'Plain words');
      expect(stored['synced_text'], '[00:01.00]Timed');
    });

    test('never replace a listener edit, while an updated sidecar still '
        'replaces its own earlier text', () async {
      await ingest('[00:01.00]First');
      await ingest('[00:01.00]Updated');
      expect((await row())['synced_text'], '[00:01.00]Updated');

      await store.saveUserEdit(
        songId: 'song-a',
        kind: LyricsTextKind.synced,
        text: '[00:01.50]Mine',
      );
      await ingest('[00:01.00]Rescanned');
      final stored = await row();
      expect(stored['synced_text'], '[00:01.50]Mine');
      expect(stored['synced_source'], 'user');
    });

    test('embedded tags fill gaps, never replacing a legacy or edited '
        'text without a sidecar', () async {
      await (await app.database).insert(DatabaseTables.trackLyrics, {
        'song_id': 'song-a',
        'plain_text': 'Legacy',
        'created_at': fixtureTimestamp,
        'updated_at': fixtureTimestamp,
      });
      var reads = 0;
      await LyricsIngestionService(
        sourceReader: _Sidecar(null),
        lyricsWriter: store,
        embeddedReader: (_) async {
          reads++;
          return const EmbeddedLyrics(plain: 'Tag');
        },
      ).ingest(candidate: _candidate('song.lrc'), songId: 'song-a');
      expect(reads, 0);
      expect((await row())['plain_text'], 'Legacy');
    });
  });
}
