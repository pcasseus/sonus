import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/data/services/possible_recording_store.dart';
import 'package:sonus_next/features/import/domain/models/pending_possible_recording.dart';

void main() {
  final firstSeen = DateTime.utc(2026, 10, 25, 12);

  PendingPossibleRecording entry({
    String path = 'music/drama/track09.mp3',
    String songId = 'song-kept',
    int seconds = 147,
    DateTime? seenAt,
  }) {
    return PendingPossibleRecording(
      normalizedPath: path,
      filePath: path,
      candidateSongId: songId,
      title: 'ErrTime',
      artistName: 'Fictional Harbour',
      albumTitle: 'Quiet Rooms',
      discNumber: 1,
      trackNumber: 9,
      durationSeconds: seconds,
      firstSeenAt: seenAt ?? firstSeen,
      metadataFallbackPath: 'Music/Quiet Rooms/09 ErrTime.mp3',
      sourceId: 'source-1',
    );
  }

  PossibleRecordingStore storeOver(Map<String, String> values) {
    return PossibleRecordingStore.forTesting(
      getString: (key) async => values[key],
      setString: (key, value) async => values[key] = value,
    );
  }

  test('an entry round-trips with every field', () async {
    final store = storeOver({});

    await store.upsert(entry());

    final saved = (await store.getPending()).single;
    expect(saved.normalizedPath, 'music/drama/track09.mp3');
    expect(saved.filePath, 'music/drama/track09.mp3');
    expect(saved.candidateSongId, 'song-kept');
    expect(saved.title, 'ErrTime');
    expect(saved.artistName, 'Fictional Harbour');
    expect(saved.albumTitle, 'Quiet Rooms');
    expect(saved.discNumber, 1);
    expect(saved.trackNumber, 9);
    expect(saved.durationSeconds, 147);
    expect(saved.firstSeenAt, firstSeen);
    expect(saved.firstSeenAt.isUtc, isTrue);
    expect(saved.metadataFallbackPath, 'Music/Quiet Rooms/09 ErrTime.mp3');
    expect(saved.sourceId, 'source-1');
  });

  test('entries and same-recording choices survive a restart', () async {
    final values = <String, String>{};
    final before = storeOver(values);
    await before.upsert(entry());
    await before.markSameRecording(entry(path: 'music/other.mp3'));

    final after = storeOver(values);

    expect((await after.getPending()).map((e) => e.normalizedPath), [
      'music/drama/track09.mp3',
    ]);
    expect(
      await after.isSameRecording(
        normalizedPath: 'music/other.mp3',
        candidateSongId: 'song-kept',
        durationSeconds: 147,
      ),
      isTrue,
    );
  });

  test('unreadable stored data is ignored', () async {
    for (final stored in ['not json', '{"a": 1}', '[1, {"title": 2}]', '']) {
      final values = {
        'import.possible_recordings.pending': stored,
        'import.possible_recordings.same_recording': stored,
      };
      final store = storeOver(values);

      expect(await store.getPending(), isEmpty, reason: stored);
      expect(
        await store.isSameRecording(
          normalizedPath: 'music/drama/track09.mp3',
          candidateSongId: 'song-kept',
          durationSeconds: 147,
        ),
        isFalse,
      );

      await store.upsert(entry());
      expect(await store.getPending(), hasLength(1));
    }
  });

  test('a read that fails is treated as no data', () async {
    final store = PossibleRecordingStore.forTesting(
      getString: (_) async => throw TypeError(),
      setString: (_, _) async {},
    );

    expect(await store.getPending(), isEmpty);
  });

  test('upserting the same path never duplicates and keeps when it was '
      'first seen', () async {
    final store = storeOver({});

    await store.upsert(entry());
    await store.upsert(
      entry(songId: 'song-other', seenAt: DateTime.utc(2026, 10, 30)),
    );

    final saved = (await store.getPending()).single;
    expect(saved.candidateSongId, 'song-other');
    expect(saved.firstSeenAt, firstSeen);
  });

  test('a same-recording choice is tied to the song and the length', () async {
    final store = storeOver({});
    await store.upsert(entry());

    await store.markSameRecording(entry());

    expect(await store.getPending(), isEmpty);
    expect(
      await store.isSameRecording(
        normalizedPath: 'music/drama/track09.mp3',
        candidateSongId: 'song-kept',
        durationSeconds: 147,
      ),
      isTrue,
    );
    expect(
      await store.isSameRecording(
        normalizedPath: 'music/drama/track09.mp3',
        candidateSongId: 'song-kept',
        durationSeconds: 210,
      ),
      isFalse,
    );
    expect(
      await store.isSameRecording(
        normalizedPath: 'music/drama/track09.mp3',
        candidateSongId: 'song-other',
        durationSeconds: 147,
      ),
      isFalse,
    );
  });
}
