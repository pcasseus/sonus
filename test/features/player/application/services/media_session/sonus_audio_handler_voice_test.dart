import 'dart:async';

import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_catalog.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_library.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/application/services/media_session/voice_request_resolver.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import 'media_browse_catalog_test.dart'
    show FakeBrowseLibrary, libraryAlbum, libraryTrack;
import 'media_session_test_support.dart';

/// App Update 1.3: spoken requests from Android Auto and the Assistant.
void main() {
  late List<(String, int)> logs;
  late RecordingEngine engine;
  late PlaybackCoordinator coordinator;
  late FakeBrowseLibrary library;
  late SonusAudioHandler handler;

  setUp(() {
    logs = [];
    engine = RecordingEngine();
    coordinator = PlaybackCoordinator(engine: engine);
    library = FakeBrowseLibrary()
      ..tracks = [
        libraryTrack('a', title: 'Song a'),
        libraryTrack('b', title: 'Song b'),
        libraryTrack('angel', title: 'Angel'),
      ]
      ..playlistList = const [
        MediaBrowsePlaylist(id: 'p1', name: 'Road Trip', trackCount: 3),
        MediaBrowsePlaylist(id: 'empty', name: 'Empty One', trackCount: 0),
      ]
      ..playlistTracksById['p1'] = [
        libraryTrack('b'),
        libraryTrack('a'),
        libraryTrack('b'),
      ];
    handler = SonusAudioHandler(
      artworkExists: (_) => false,
      log: (message, {level = 800}) => logs.add((message, level)),
      readinessTimeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() => engine.dispose());

  void attach() => handler
    ..attach(coordinator)
    ..attachCatalog(MediaBrowseCatalog(library: library));

  Future<void> emit(PlaybackState state) async {
    engine.emit(state);
    await pumpEventQueue();
  }

  group('playlist requests', () {
    setUp(attach);

    test(
      'the playlist extra plays it in order through the coordinator',
      () async {
        await handler.playFromSearch('road trip', {
          VoiceRequestKeys.playlist: 'Road Trip',
          VoiceRequestKeys.focus: VoiceRequestKeys.focusPlaylist,
        });

        expect(engine.loads.single.$1, ['b', 'a', 'b']);
        expect(engine.loads.single.$2, 0);
        expect(engine.loads.single.$3, isTrue);
        expect(handler.queueTitle.value, 'Road Trip');
      },
    );

    test('playlist focus alone reads the query', () async {
      await handler.playFromSearch('my road trip playlist', {
        VoiceRequestKeys.focus: VoiceRequestKeys.focusPlaylist,
      });

      expect(engine.loads.single.$1, ['b', 'a', 'b']);
    });

    test('an empty playlist is not found', () async {
      await handler.playFromSearch('', {
        VoiceRequestKeys.playlist: 'empty one',
      });

      expect(engine.loads, isEmpty);
      expect(
        handler.playbackState.value.errorMessage,
        'Sonus couldn\'t find "empty one".',
      );
    });
  });

  group('not found', () {
    setUp(attach);

    test('publishes a non-fatal error and keeps playback going', () async {
      await emit(queuedState(index: 1));

      await handler.playFromSearch('zzzz');

      final state = handler.playbackState.value;
      expect(engine.commands, isEmpty, reason: 'nothing was stopped');
      expect(state.processingState, media.AudioProcessingState.ready);
      expect(state.playing, isTrue);
      expect(state.queueIndex, 1);
      expect(state.errorCode, SonusAudioHandler.notFoundErrorCode);
      expect(state.errorMessage, 'Sonus couldn\'t find "zzzz".');
      expect(handler.mediaItem.value!.id, 'b');
    });

    test('with nothing queued the session reports an error state', () async {
      await handler.playFromSearch('', {VoiceRequestKeys.artist: 'Nobody'});

      final state = handler.playbackState.value;
      expect(state.processingState, media.AudioProcessingState.error);
      expect(state.errorMessage, 'Sonus couldn\'t find "Nobody".');
    });

    test('the error stays while playback progresses', () async {
      await emit(queuedState());
      await handler.playFromSearch('zzzz');

      await emit(queuedState(position: const Duration(seconds: 30)));

      expect(handler.playbackState.value.errorMessage, isNotNull);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 30),
      );
    });

    test('the next successful command clears it', () async {
      await emit(queuedState(status: PlaybackStatus.paused));
      await handler.playFromSearch('zzzz');
      expect(handler.playbackState.value.errorMessage, isNotNull);

      await handler.play();

      final state = handler.playbackState.value;
      expect(state.errorMessage, isNull);
      expect(state.errorCode, isNull);
      expect(state.processingState, media.AudioProcessingState.ready);
    });

    test('a successful voice request clears it', () async {
      await handler.playFromSearch('zzzz');
      expect(
        handler.playbackState.value.processingState,
        media.AudioProcessingState.error,
      );

      await handler.playFromSearch('angel');

      expect(engine.loads.single.$1.first, 'angel');
      expect(handler.playbackState.value.errorMessage, isNull);
    });

    test('a failed command does not clear it', () async {
      await emit(queuedState(status: PlaybackStatus.paused));
      await handler.playFromSearch('zzzz');
      engine.failWith = StateError('decoder');

      await handler.play();

      expect(handler.playbackState.value.errorMessage, isNotNull);
    });

    test('another song starting, from the app, clears it', () async {
      await emit(queuedState());
      await handler.playFromSearch('zzzz');

      await emit(queuedState(index: 2));

      expect(handler.playbackState.value.errorMessage, isNull);
    });
  });

  test('a request before Sonus is ready reports that it is starting', () async {
    await handler.playFromSearch('angel');

    final state = handler.playbackState.value;
    expect(state.processingState, media.AudioProcessingState.error);
    expect(state.errorCode, SonusAudioHandler.notReadyErrorCode);
    expect(state.errorMessage, SonusAudioHandler.notReadyMessage);
    expect(engine.loads, isEmpty);
  });

  group('a library that cannot be read', () {
    late _ThrowingLibrary unreadable;

    setUp(() {
      unreadable = _ThrowingLibrary();
      handler
        ..attach(coordinator)
        ..attachCatalog(MediaBrowseCatalog(library: unreadable));
    });

    test('is reported, never thrown', () async {
      await handler.playFromSearch('angel');

      expect(logs.single.$2, 900);
      expect(engine.loads, isEmpty);
    });

    test('says the library could not be accessed, as an app error', () async {
      await handler.playFromSearch('locket by madison beer');

      final state = handler.playbackState.value;
      expect(state.errorMessage, "Sonus couldn't access your music library.");
      expect(state.errorCode, SonusAudioHandler.libraryUnreadableErrorCode);
      expect(state.errorCode, 1, reason: 'ERROR_CODE_APP_ERROR');
      expect(state.processingState, media.AudioProcessingState.error);
    });

    test('is never reported as music not found', () async {
      for (final (query, extras) in [
        ('angel', null),
        ('', {VoiceRequestKeys.playlist: 'Road Trip'}),
        ('', {VoiceRequestKeys.artist: 'Nobody'}),
      ]) {
        await handler.playFromSearch(query, extras);

        final state = handler.playbackState.value;
        expect(state.errorMessage, SonusAudioHandler.libraryUnreadableMessage);
        expect(state.errorMessage, isNot(contains("couldn't find")));
        expect(state.errorCode, isNot(SonusAudioHandler.notFoundErrorCode));
      }
    });

    test('keeps the current song playing', () async {
      await emit(queuedState(index: 1));

      await handler.playFromSearch('angel');

      final state = handler.playbackState.value;
      expect(engine.commands, isEmpty, reason: 'nothing was stopped');
      expect(engine.loads, isEmpty);
      expect(state.processingState, media.AudioProcessingState.ready);
      expect(state.playing, isTrue);
      expect(state.queueIndex, 1);
      expect(state.errorCode, SonusAudioHandler.libraryUnreadableErrorCode);
      expect(state.errorMessage, SonusAudioHandler.libraryUnreadableMessage);
      expect(handler.mediaItem.value!.id, 'b');
    });

    test('is cleared once the library can be read again', () async {
      await handler.playFromSearch('angel');
      expect(handler.playbackState.value.errorMessage, isNotNull);

      unreadable.broken = false;
      await handler.playFromSearch('angel');

      expect(engine.loads.single.$1.first, 'angel');
      expect(handler.playbackState.value.errorMessage, isNull);
      expect(handler.playbackState.value.errorCode, isNull);
    });
  });

  group('repeated requests', () {
    setUp(attach);

    test('only the newest of several quick requests plays', () async {
      final slow = _SlowLibrary(library);
      handler.attachCatalog(MediaBrowseCatalog(library: slow));

      final first = handler.playFromSearch('angel');
      await pumpEventQueue();
      final second = handler.playFromSearch('road trip', {
        VoiceRequestKeys.playlist: 'Road Trip',
      });
      slow.release();
      await Future.wait([first, second]);

      expect(engine.loads, hasLength(1));
      expect(engine.loads.single.$1, ['b', 'a', 'b']);
      expect(logs.map((log) => log.$1), contains(contains('newer request')));
    });

    test('the same request three times loads once', () async {
      await Future.wait([
        for (var i = 0; i < 3; i++) handler.playFromSearch('angel'),
      ]);

      expect(engine.loads, hasLength(1));
    });
  });

  group('the queue title', () {
    setUp(attach);

    test('names a spoken song search and a browsed list', () async {
      await handler.playFromSearch('angel');
      expect(handler.queueTitle.value, 'Search: angel');

      library.recent = [libraryTrack('a')];
      await handler.playFromMediaId('sonus:recent/song:a');
      expect(handler.queueTitle.value, 'Recent');
    });

    test('is kept while songs are added, dropped when replaced', () async {
      await handler.playFromSearch('', {
        VoiceRequestKeys.playlist: 'road trip',
      });
      final tracks = [mediaTrack('b'), mediaTrack('a'), mediaTrack('b')];
      await emit(queuedState(tracks: tracks));
      expect(handler.queueTitle.value, 'Road Trip');

      await emit(queuedState(tracks: [...tracks, mediaTrack('x')]));
      expect(handler.queueTitle.value, 'Road Trip');

      // Stopping empties the published queue; the title waits for resume.
      await emit(queuedState(tracks: tracks, status: PlaybackStatus.idle));
      expect(handler.queueTitle.value, 'Road Trip');

      await emit(queuedState(tracks: [mediaTrack('x'), mediaTrack('y')]));
      expect(handler.queueTitle.value, '');
    });

    test('queue items keep the song IDs as their IDs', () async {
      await handler.playFromSearch('', {
        VoiceRequestKeys.playlist: 'road trip',
      });
      await emit(
        queuedState(
          tracks: [mediaTrack('b'), mediaTrack('a'), mediaTrack('b')],
        ),
      );

      expect(handler.queue.value.map((item) => item.id), ['b', 'a', 'b']);
    });

    test('a failed load sets no title', () async {
      engine.failWith = StateError('decoder');

      await handler.playFromSearch('angel');

      expect(handler.queueTitle.value, '');
    });

    test('is cleared when the player goes away', () async {
      await handler.playFromSearch('angel');

      handler.detach(coordinator);

      expect(handler.queueTitle.value, '');
    });
  });

  group('play next and add to queue from a media controller', () {
    setUp(attach);

    test('add to queue appends, as the app does', () async {
      await handler.addQueueItem(const media.MediaItem(id: 'angel', title: ''));

      expect(engine.commands, ['appendTrack']);
    });

    test('a browsed song can be added by its browse ID', () async {
      await handler.addQueueItem(
        const media.MediaItem(id: 'sonus:songs/song:a', title: ''),
      );

      expect(engine.commands, ['appendTrack']);
    });

    test('an insert after the current song is Play next', () async {
      await emit(queuedState(index: 0));

      await handler.insertQueueItem(
        1,
        const media.MediaItem(id: 'angel', title: ''),
      );

      expect(engine.commands, ['insertTrack']);
    });

    test('an insert at the end is Add to queue', () async {
      await emit(queuedState(index: 0));

      await handler.insertQueueItem(
        3,
        const media.MediaItem(id: 'angel', title: ''),
      );

      expect(engine.commands, ['appendTrack']);
    });

    test('with nothing queued, an insert is Play next', () async {
      await handler.insertQueueItem(
        5,
        const media.MediaItem(id: 'angel', title: ''),
      );

      expect(engine.loads.single.$1, ['angel']);
      expect(engine.loads.single.$3, isFalse, reason: 'it loads paused');
    });

    test('any other position is refused', () async {
      await emit(queuedState(index: 0));

      await handler.insertQueueItem(
        2,
        const media.MediaItem(id: 'angel', title: ''),
      );

      expect(engine.commands, isEmpty);
      expect(logs.single.$1, contains('only Play next'));
    });

    test('an unknown or unplayable song is not queued', () async {
      library.tracks = [...library.tracks, libraryTrack('x', blocked: true)];

      await handler.addQueueItem(const media.MediaItem(id: 'x', title: ''));
      await handler.addQueueItem(const media.MediaItem(id: 'gone', title: ''));

      expect(engine.commands, isEmpty);
      expect(logs.map((log) => log.$1), everyElement(contains('unavailable')));
    });
  });

  group('what the car says when a request cannot play', () {
    test('the exact wording of each failure', () {
      expect(
        SonusAudioHandler.notReadyMessage,
        'Sonus is still starting. Try again in a moment.',
      );
      expect(
        SonusAudioHandler.nothingToPlayMessage,
        'Sonus has nothing to play yet.',
      );
      expect(
        SonusAudioHandler.notFoundMessage('locket by Madison Beer'),
        'Sonus couldn\'t find "locket by Madison Beer".',
      );
      expect(
        SonusAudioHandler.libraryUnreadableMessage,
        "Sonus couldn't access your music library.",
      );
    });

    test('the error code of each failure', () {
      expect(SonusAudioHandler.notReadyErrorCode, 1); // ERROR_CODE_APP_ERROR
      expect(SonusAudioHandler.libraryUnreadableErrorCode, 1);
      expect(SonusAudioHandler.notFoundErrorCode, 0); // UNKNOWN_ERROR
    });

    test('missing music quotes the request', () async {
      attach();
      await handler.playFromSearch('locket by madison beer');

      expect(
        handler.playbackState.value.errorMessage,
        'Sonus couldn\'t find "locket by madison beer".',
      );
      expect(
        handler.playbackState.value.errorCode,
        SonusAudioHandler.notFoundErrorCode,
      );
    });

    test('an empty playable library has nothing to play, '
        'whatever was asked', () async {
      library
        ..tracks = [libraryTrack('gone', available: false)]
        ..playlistTracksById.clear();
      attach();

      for (final (query, extras) in [
        ('', null),
        ('angel', null),
        ('', {VoiceRequestKeys.playlist: 'Road Trip'}),
      ]) {
        await handler.playFromSearch(query, extras);
        expect(
          handler.playbackState.value.errorMessage,
          'Sonus has nothing to play yet.',
          reason: query,
        );
        expect(
          handler.playbackState.value.errorCode,
          SonusAudioHandler.notFoundErrorCode,
        );
      }
      expect(engine.loads, isEmpty);
    });

    test('a library still starting says so', () async {
      await handler.playFromSearch('', {VoiceRequestKeys.playlist: 'Gym'});

      expect(
        handler.playbackState.value.errorMessage,
        'Sonus is still starting. Try again in a moment.',
      );
      expect(
        handler.playbackState.value.errorCode,
        SonusAudioHandler.notReadyErrorCode,
      );
    });
  });

  group('voice queues keep their songs and order', () {
    setUp(attach);

    test(
      'a playlist, an album and a search queue the same IDs as browsing',
      () async {
        library
          ..albumList = [libraryAlbum('album-1', 'Locket')]
          ..albumTracksById['album-1'] = [libraryTrack('a'), libraryTrack('b')];

        await handler.playFromSearch('playlist road trip');
        expect(engine.loads.last.$1, ['b', 'a', 'b']);
        expect(engine.loads.last.$2, 0);
        expect(handler.queueTitle.value, 'Road Trip');

        await handler.playFromSearch('the album locket');
        expect(engine.loads.last.$1, ['a', 'b']);
        expect(handler.queueTitle.value, 'Locket');

        await handler.playFromSearch('song angel');
        expect(engine.loads.last.$1, ['angel']);
        expect(handler.queueTitle.value, 'Search: song angel');

        await handler.playFromMediaId('sonus:playlist:p1/song:a');
        expect(engine.loads.last.$1, ['b', 'a', 'b']);
        expect(engine.loads.last.$2, 1);
        expect(handler.queueTitle.value, 'Road Trip');
      },
    );
  });
}

/// Fails every read of the songs while [broken], as a closed database
/// would.
class _ThrowingLibrary extends FakeBrowseLibrary {
  _ThrowingLibrary() {
    tracks = [libraryTrack('angel', title: 'Angel')];
  }

  bool broken = true;

  @override
  Future<List<LibraryTrack>> allTracks() async {
    if (broken) throw StateError('database closed');
    return tracks;
  }
}

/// Holds the first read of every song until [release], so a request can
/// be overtaken by a newer one.
class _SlowLibrary extends FakeBrowseLibrary {
  _SlowLibrary(FakeBrowseLibrary from) {
    tracks = from.tracks;
    playlistList = from.playlistList;
    playlistTracksById = from.playlistTracksById;
  }

  final Completer<void> _gate = Completer<void>();
  bool _held = false;

  void release() => _gate.complete();

  @override
  Future<List<LibraryTrack>> allTracks() async {
    if (!_held) {
      _held = true;
      await _gate.future;
    }
    return tracks;
  }
}
