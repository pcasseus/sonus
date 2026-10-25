import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_catalog.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';

import 'media_browse_catalog_test.dart'
    show FakeBrowseLibrary, libraryAlbum, libraryTrack;
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'media_session_test_support.dart';

/// Android Auto's browse and play requests reach Sonus's single playback
/// authority, with the list the listener chose as the queue.
void main() {
  late List<(String, int)> logs;
  late RecordingEngine engine;
  late PlaybackCoordinator coordinator;
  late FakeBrowseLibrary library;
  late MediaBrowseCatalog catalog;
  late SonusAudioHandler handler;

  setUp(() {
    logs = [];
    engine = RecordingEngine();
    coordinator = PlaybackCoordinator(engine: engine);
    library = FakeBrowseLibrary()
      ..albumTracksById['album-1'] = [
        libraryTrack('first'),
        libraryTrack('second'),
        libraryTrack('third'),
        libraryTrack('fourth'),
      ];
    catalog = MediaBrowseCatalog(library: library);
    handler = SonusAudioHandler(
      artworkExists: (_) => false,
      log: (message, {level = 800}) => logs.add((message, level)),
      readinessTimeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() => engine.dispose());

  group('when ready', () {
    setUp(() {
      handler
        ..attach(coordinator)
        ..attachCatalog(catalog);
    });

    test('browsing returns the catalog', () async {
      final root = await handler.getChildren(
        media.AudioService.browsableRootId,
      );
      expect(root.map((item) => item.title), contains('Albums'));

      final album = await handler.getChildren('sonus:album:album-1');
      expect(album, hasLength(4));
    });

    test('playing the third song keeps the album around it', () async {
      await handler.playFromMediaId('sonus:album:album-1/song:third');

      expect(engine.loads.single.$1, ['first', 'second', 'third', 'fourth']);
      expect(engine.loads.single.$2, 2);
      expect(engine.loads.single.$3, isTrue);
    });

    test('preparing loads the same queue without starting audio', () async {
      await handler.prepareFromMediaId('sonus:album:album-1/song:second');

      expect(engine.loads.single.$1, ['first', 'second', 'third', 'fourth']);
      expect(engine.loads.single.$2, 1);
      expect(engine.loads.single.$3, isFalse);
    });

    test('playMediaItem uses the item ID the same way', () async {
      await handler.playMediaItem(
        const media.MediaItem(id: 'sonus:album:album-1/song:fourth', title: ''),
      );

      expect(engine.loads.single.$2, 3);
    });

    test('an unavailable song plays nothing and is logged', () async {
      await handler.playFromMediaId('sonus:album:album-1/song:missing');

      expect(engine.loads, isEmpty);
      expect(logs.single.$1, contains('unavailable'));
    });

    test('voice requests play through the same authority', () async {
      library.albumList = [libraryAlbum('album-1', 'locket')];

      await handler.playFromSearch('locket');

      expect(engine.loads.single.$1, ['first', 'second', 'third', 'fourth']);
      expect(engine.loads.single.$3, isTrue);
    });

    test('structured voice extras are read', () async {
      library.tracks = [libraryTrack('t', title: 'angel wings')];

      await handler.playFromSearch('', {
        SonusAudioHandler.searchArtistKey: 'Nobody',
        SonusAudioHandler.searchAlbumKey: 42,
      });

      // "Nobody" matches no artist or album and no song.
      expect(engine.loads, isEmpty);
      expect(logs.single.$1, contains('found nothing'));
    });

    test('search answers with playable songs', () async {
      library.tracks = [libraryTrack('t', title: 'angel wings')];

      final results = await handler.search('angel');

      expect(results.single.title, 'angel wings');
      expect(results.single.playable, isTrue);
    });

    test(
      'a failing library read returns an empty list and is logged',
      () async {
        handler.attachCatalog(MediaBrowseCatalog(library: _ThrowingLibrary()));

        expect(await handler.getChildren('sonus:songs'), isEmpty);
        expect(logs.single.$2, 900);
      },
    );

    test('a failing playback load is logged, never thrown', () async {
      engine.failWith = StateError('decoder');

      await handler.playFromMediaId('sonus:album:album-1/song:first');

      expect(logs.single.$1, contains('playFromMediaId'));
      expect(logs.single.$2, 900);
    });
  });

  group('when Android Auto starts Sonus with no screen', () {
    test(
      'early requests wait until the library and player are ready',
      () async {
        final children = handler.getChildren('sonus:album:album-1');
        final play = handler.playFromMediaId('sonus:album:album-1/song:second');

        await pumpEventQueue();
        handler.attach(coordinator);
        await pumpEventQueue();
        handler.attachCatalog(catalog);

        expect(await children, hasLength(4));
        await play;
        expect(engine.loads.single.$2, 1);
        expect(logs, isEmpty);
      },
    );

    test('frames are requested only while a request waits', () async {
      var wakes = 0;
      final waking = SonusAudioHandler(
        wakeApp: () => wakes++,
        readinessTimeout: const Duration(seconds: 5),
      );

      final children = waking.getChildren('sonus:album:album-1');
      await Future<void>.delayed(SonusAudioHandler.wakeInterval * 3.5);
      expect(wakes, greaterThanOrEqualTo(3));

      waking
        ..attach(coordinator)
        ..attachCatalog(catalog);
      expect(await children, hasLength(4));

      final afterReady = wakes;
      await Future<void>.delayed(SonusAudioHandler.wakeInterval * 3);
      expect(wakes, afterReady, reason: 'no frames once ready');

      // Once ready, requests answer at once without waking anything.
      await waking.getChildren('sonus:album:album-1');
      expect(wakes, afterReady);
    });

    test('requests give up after the readiness timeout', () async {
      final children = await handler.getChildren('sonus:songs');

      expect(children, isEmpty);
      expect(logs.single.$1, contains('library is not ready'));
    });

    test('a catalog without a player still answers browsing', () async {
      handler.attachCatalog(catalog);

      final children = await handler.getChildren('sonus:album:album-1');
      expect(children, hasLength(4));

      await handler.playFromMediaId('sonus:album:album-1/song:first');
      expect(engine.loads, isEmpty);
      expect(logs.last.$1, contains('playback is not ready'));
    });
  });

  group('rebinding', () {
    test('an older catalog cannot remove a newer one', () async {
      final newer = MediaBrowseCatalog(library: FakeBrowseLibrary());
      handler
        ..attach(coordinator)
        ..attachCatalog(catalog)
        ..attachCatalog(newer)
        ..detachCatalog(catalog);

      expect(handler.catalog, same(newer));

      handler.detachCatalog(newer);
      expect(handler.catalog, isNull);
    });
  });
}

class _ThrowingLibrary extends FakeBrowseLibrary {
  @override
  Future<List<LibraryTrack>> allTracks() async =>
      throw StateError('database closed');
}
