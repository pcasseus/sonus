// App Update 1.2, PATCH-01: switching between Standard and Deluxe on the
// Album Profile. On the device a tap on Deluxe did not move at first, and a
// second tap switched to Deluxe and then back. Two reads raced: a refresh
// (started by automatic sync or a recorded play) remembered Standard when
// it began and finished after the tap, and an edition read could finish
// after a newer one. The latest choice must always win.

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';

import 'album_profile_controller_test.dart'
    show
        FakeEditionAwareLibraryQueryRepository,
        FakePlaybackEngine,
        createAlbum,
        createLibraryEdition,
        createTrack;

void main() {
  group('Album Profile edition selection (PATCH-01)', () {
    test('a refresh that began before a tap cannot switch the edition '
        'back when it finishes after it (the device bug)', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);

      repository.gateAlbumReads = true;
      final refresh = controller.refresh(); // remembers Standard as it starts
      await _settle();
      repository.gateAlbumReads = false;

      final tap = controller.selectEdition(_deluxe);
      expect(controller.chosenEditionId, _deluxe, reason: 'moves at once');
      expect(await tap, isTrue);
      expect(controller.selectedEdition?.editionId, _deluxe);

      repository.releaseAlbumReads();
      await refresh;

      expect(controller.selectedEdition?.editionId, _deluxe);
      expect(controller.chosenEditionId, _deluxe);
      expect(_songIds(controller), _deluxeSongs);
      controller.dispose();
    });

    test('the selector moves on the first tap, before the songs are read, '
        'and everything else follows together', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      repository.gateTrackReads = true;

      final tap = controller.selectEdition(_deluxe);
      await _settle();

      expect(controller.chosenEditionId, _deluxe);
      // Until Deluxe's songs are read the page still shows Standard whole:
      // never Deluxe's title over Standard's songs.
      expect(controller.selectedEdition?.editionId, _standard);
      expect(_songIds(controller), _standardSongs);

      repository.releaseTrackReads();
      expect(await tap, isTrue);
      expect(controller.selectedEdition?.editionId, _deluxe);
      expect(_songIds(controller), _deluxeSongs);
      expect(controller.discLabels, isEmpty);
      controller.dispose();
    });

    test('a refresh that begins while a tap is being read keeps the edition '
        'tapped', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      repository.gateTrackReads = true;

      final tap = controller.selectEdition(_deluxe);
      await _settle();
      final refresh = controller.refresh();
      await _settle();
      expect(controller.chosenEditionId, _deluxe);

      repository.releaseTrackReads();
      await Future.wait([tap, refresh]);

      expect(controller.selectedEdition?.editionId, _deluxe);
      expect(_songIds(controller), _deluxeSongs);
      controller.dispose();
    });

    test('reads finishing out of order: the latest tap wins', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      repository.gateTrackReads = true;

      final toDeluxe = controller.selectEdition(_deluxe);
      await _settle();
      final backToStandard = controller.selectEdition(_standard);
      await _settle();
      expect(controller.chosenEditionId, _standard);

      // Standard's read finishes first, then the older Deluxe read.
      repository.releaseTrackRead(_standard);
      await backToStandard;
      repository.releaseTrackRead(_deluxe);
      await toDeluxe;

      expect(controller.selectedEdition?.editionId, _standard);
      expect(controller.chosenEditionId, _standard);
      expect(_songIds(controller), _standardSongs);
      controller.dispose();
    });

    test('rapid alternating taps end on the last edition tapped, whatever '
        'order the reads finish in', () async {
      for (var seed = 0; seed < 25; seed++) {
        final random = Random(seed);
        final repository = _GatedRepository();
        final controller = await _loaded(repository);
        repository.gateTrackReads = true;

        final taps = <Future<bool>>[];
        var last = _standard;
        final count = 2 + random.nextInt(7);
        for (var i = 0; i < count; i++) {
          last = last == _standard ? _deluxe : _standard;
          taps.add(controller.selectEdition(last));
          await _settle();
          expect(controller.chosenEditionId, last);
        }
        await repository.releaseTrackReadsShuffled(random);
        await Future.wait(taps);

        expect(controller.selectedEdition?.editionId, last, reason: '$seed');
        expect(controller.chosenEditionId, last, reason: '$seed');
        expect(
          _songIds(controller),
          last == _deluxe ? _deluxeSongs : _standardSongs,
          reason: 'seed $seed',
        );
        controller.dispose();
      }
    });

    test('tapping the edition already chosen does nothing', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      repository.trackReads.clear();
      repository.gateTrackReads = true;

      final first = controller.selectEdition(_deluxe);
      await _settle();
      expect(await controller.selectEdition(_deluxe), isTrue);
      expect(await controller.selectEdition(' $_deluxe '), isTrue);
      expect(repository.trackReads, [_deluxe], reason: 'one read only');

      repository.releaseTrackReads();
      await first;
      expect(await controller.selectEdition(_deluxe), isTrue);
      expect(repository.trackReads, [_deluxe]);
      expect(controller.selectedEdition?.editionId, _deluxe);
      controller.dispose();
    });

    test('the chosen edition stays through later refreshes', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      await controller.selectEdition(_deluxe);

      for (var i = 0; i < 3; i++) {
        await controller.refresh();
        expect(controller.selectedEdition?.editionId, _deluxe);
      }
      controller.dispose();
    });

    test('Play All and track numbers follow the selected edition', () async {
      final repository = _GatedRepository();
      final engine = FakePlaybackEngine();
      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );
      await controller.load();
      await controller.selectEdition(_deluxe);

      expect(controller.tracks.map((track) => track.trackNumber), [1, 2, 3]);
      await controller.playAll();
      expect(engine.lastLoadedTracks!.map((t) => t.songId), _deluxeSongs);

      await controller.selectEdition(_standard);
      await controller.playAll();
      expect(engine.lastLoadedTracks!.map((t) => t.songId), _standardSongs);
      controller.dispose();
      await engine.dispose();
    });

    test('switching only reads: no edition changes', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      final before = _describe(controller.editions);

      for (final id in [_deluxe, _standard, _deluxe]) {
        await controller.selectEdition(id);
      }

      expect(_describe(controller.editions), before);
      expect(repository.editionTracks[_standard]!.map((t) => t.songId), [
        ..._standardSongs,
      ]);
      expect(repository.editionTracks[_deluxe]!.map((t) => t.songId), [
        ..._deluxeSongs,
      ]);
      controller.dispose();
    });

    test('a read that fails keeps the edition on screen', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      repository.failTrackReadsOf = _deluxe;

      expect(await controller.selectEdition(_deluxe), isFalse);
      expect(controller.chosenEditionId, _standard);
      expect(controller.selectedEdition?.editionId, _standard);
      expect(_songIds(controller), _standardSongs);
      expect(controller.hasError, isFalse);

      repository.failTrackReadsOf = null;
      expect(await controller.selectEdition(_deluxe), isTrue);
      expect(controller.selectedEdition?.editionId, _deluxe);
      controller.dispose();
    });

    test('an edition that is not this album\'s is refused', () async {
      final controller = await _loaded(_GatedRepository());
      expect(await controller.selectEdition('edition-elsewhere'), isFalse);
      expect(await controller.selectEdition('  '), isFalse);
      expect(controller.chosenEditionId, _standard);
      controller.dispose();
    });

    test('leaving the page while a read is pending is safe', () async {
      final repository = _GatedRepository();
      final controller = await _loaded(repository);
      repository.gateTrackReads = true;

      final tap = controller.selectEdition(_deluxe);
      await _settle();
      controller.dispose();
      repository.releaseTrackReads();

      expect(await tap, isTrue);
    });
  });
}

const _standard = 'edition-standard';
const _deluxe = 'edition-deluxe';
const _standardSongs = ['song-a', 'song-b'];
const _deluxeSongs = ['song-a', 'song-b', 'song-bonus'];

Future<AlbumProfileController> _loaded(_GatedRepository repository) async {
  final controller = AlbumProfileController(
    repository: repository,
    albumId: 'album-1',
  );
  await controller.load();
  expect(controller.selectedEdition?.editionId, _standard);
  return controller;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

List<String> _songIds(AlbumProfileController controller) => [
  for (final track in controller.tracks) track.songId,
];

List<String> _describe(List<LibraryAlbumEdition> editions) => [
  for (final edition in editions)
    '${edition.editionId}|${edition.title}|${edition.type}|'
        '${edition.isPrimary}|${edition.artworkPath}',
];

/// Standard and Deluxe with different tracklists. Album and edition-song
/// reads can be held and released in any order.
class _GatedRepository extends FakeEditionAwareLibraryQueryRepository {
  _GatedRepository()
    : super(
        album: _album,
        editions: [
          createLibraryEdition(
            editionId: _standard,
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
          createLibraryEdition(
            editionId: _deluxe,
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
          ),
        ],
        editionTracks: {
          _standard: [
            for (final (i, id) in _standardSongs.indexed)
              _track(id, _standard, 'Standard', i + 1),
          ],
          _deluxe: [
            for (final (i, id) in _deluxeSongs.indexed)
              _track(id, _deluxe, 'Deluxe', i + 1),
          ],
        },
      );

  static final LibraryAlbum _album = createAlbum(
    primaryEditionId: _standard,
    primaryEditionTitle: 'Standard',
    primaryEditionType: AlbumEditionType.standard,
  );

  static LibraryTrack _track(String id, String edition, String title, int n) =>
      createTrack(
        songId: id,
        albumEditionId: edition,
        albumEditionTitle: title,
        albumEditionType: title == 'Deluxe'
            ? AlbumEditionType.deluxe
            : AlbumEditionType.standard,
        trackNumber: n,
      );

  bool gateAlbumReads = false;
  bool gateTrackReads = false;
  String? failTrackReadsOf;
  final List<String> trackReads = [];
  final List<Completer<void>> _albumGates = [];
  final List<(String, Completer<void>)> _trackGates = [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    if (gateAlbumReads) {
      final gate = Completer<void>();
      _albumGates.add(gate);
      await gate.future;
    }
    return super.getAlbumById(albumId);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId) async {
    trackReads.add(editionId);
    if (gateTrackReads) {
      final gate = Completer<void>();
      _trackGates.add((editionId, gate));
      await gate.future;
    }
    if (editionId == failTrackReadsOf) {
      throw StateError('read failed');
    }
    return super.getTracksByAlbumEditionId(editionId);
  }

  void releaseAlbumReads() {
    for (final gate in _albumGates) {
      gate.complete();
    }
    _albumGates.clear();
  }

  void releaseTrackRead(String editionId) {
    final index = _trackGates.indexWhere((gate) => gate.$1 == editionId);
    _trackGates.removeAt(index).$2.complete();
  }

  void releaseTrackReads() {
    gateTrackReads = false;
    for (final gate in _trackGates) {
      gate.$2.complete();
    }
    _trackGates.clear();
  }

  /// Releases the held reads one at a time, in a random order.
  Future<void> releaseTrackReadsShuffled(Random random) async {
    gateTrackReads = false;
    final gates = [..._trackGates]..shuffle(random);
    _trackGates.clear();
    for (final gate in gates) {
      gate.$2.complete();
      await _settle();
    }
  }
}
