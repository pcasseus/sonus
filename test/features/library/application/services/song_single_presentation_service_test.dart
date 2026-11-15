import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/song_single_presentation_service.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_single_presentation_repository.dart';

/// App Update 1.3 (REF-1.3-04): the release date and cover are edited on
/// their own; nothing about the song changes.
class _Presentations implements SongSinglePresentationRepository {
  final rows = <String, SongSinglePresentation>{};

  @override
  Future<SongSinglePresentation?> getBySongId(String songId) async =>
      rows[songId];

  @override
  Future<Map<String, SongSinglePresentation>> getAll() async => {...rows};

  @override
  Future<void> save(SongSinglePresentation presentation) async {
    if (presentation.isEmpty) {
      rows.remove(presentation.songId);
    } else {
      rows[presentation.songId] = presentation;
    }
  }

  @override
  Future<void> clear(String songId) async => rows.remove(songId);
}

/// Only the song lookups the service needs; any write fails the test.
class _Songs implements SongRepository {
  _Songs(this.ids);

  final Set<String> ids;
  final looked = <String>[];

  @override
  Future<Song?> getById(String id) async {
    looked.add(id);
    return ids.contains(id) ? _song(id) : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the service must not touch songs: $invocation');
}

Song _song(String id) => Song(
  id: id,
  artistId: 'artist',
  albumId: 'album',
  albumEditionId: 'edition',
  title: 'Title',
  canonicalTitle: 'title',
  trackNumber: 1,
  durationSeconds: 200,
  isSingle: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  late _Presentations presentations;
  late LibraryChangeSignal changes;
  late SongSinglePresentationService service;
  final notified = <LibraryChangeKind>[];

  setUp(() {
    presentations = _Presentations();
    changes = LibraryChangeSignal();
    notified.clear();
    changes.changes.listen(notified.add);
    service = SongSinglePresentationService(
      presentations: presentations,
      songs: _Songs({'s1'}),
      changes: changes,
      now: () => DateTime.utc(2026, 11, 15),
    );
  });

  test('the date is set and cleared on its own', () async {
    await service.setReleaseDate('s1', ReleaseDate.of(2026, 4));
    expect(presentations.rows['s1']!.releaseDate, ReleaseDate.of(2026, 4));
    expect(notified, [LibraryChangeKind.libraryEdited]);

    await service.setReleaseDate('s1', null);
    expect(presentations.rows, isEmpty, reason: 'nothing left set');
  });

  test('clearing the cover keeps the date and turns charts off', () async {
    presentations.rows['s1'] = SongSinglePresentation(
      songId: 's1',
      releaseDate: ReleaseDate.of(2026, 4, 17),
      artworkId: 'art',
      artworkPath: '/art/single.png',
      useArtworkInCharts: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    await service.clearArtwork('s1');

    final left = presentations.rows['s1']!;
    expect(left.artworkId, isNull);
    expect(left.useArtworkInCharts, isFalse);
    expect(left.releaseDate, ReleaseDate.of(2026, 4, 17));
  });

  test('the date keeps a chosen cover and its chart setting', () async {
    presentations.rows['s1'] = SongSinglePresentation(
      songId: 's1',
      artworkId: 'art',
      useArtworkInCharts: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await service.setReleaseDate('s1', ReleaseDate.of(2026));
    expect(presentations.rows['s1']!.artworkId, 'art');
    expect(presentations.rows['s1']!.useArtworkInCharts, isTrue);
  });

  test('a song that does not exist is refused, and nothing is saved', () async {
    await expectLater(
      service.setReleaseDate('missing', ReleaseDate.of(2026)),
      throwsStateError,
    );
    expect(presentations.rows, isEmpty);
    expect(notified, isEmpty);
  });

  test('no artwork storage: no cover can be chosen', () async {
    expect(service.canAssignArtwork, isFalse);
    await expectLater(
      service.assignArtwork('s1', '/picked.png'),
      throwsStateError,
    );
  });
}
