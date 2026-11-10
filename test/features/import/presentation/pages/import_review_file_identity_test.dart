// App Update 1.2, BUG-09: Import Review shows replaced files and changed
// audio, and each choice reaches the review service unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/services/possible_recording_review_service.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/pending_possible_recording.dart';
import 'package:sonus_next/features/import/domain/repositories/song_import_review_repository.dart';
import 'package:sonus_next/features/import/presentation/pages/import_review_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/song_artist_credit_repository.dart';

class _NoReviews implements SongImportReviewRepository {
  @override
  Future<List<SongImportReview>> getUnresolved() async => const [];

  @override
  Future<int> countUnresolved() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyLibrary implements LibraryQueryRepository {
  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused implements TrackProfileEditingService, ArtistCreationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCredits implements SongArtistCreditRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReview implements PossibleRecordingReviewService {
  _FakeReview(this.items);

  List<PossibleRecordingItem> items;
  final usedFor = <(String, String)>[];
  final kept = <String>[];
  final separated = <String>[];

  void _drop(PendingPossibleRecording entry) => items = [
    for (final item in items)
      if (item.entry.normalizedPath != entry.normalizedPath) item,
  ];

  @override
  Future<List<PossibleRecordingItem>> pending() async => items;

  @override
  Future<PossibleRecordingActionResult> useFileForSong(
    PendingPossibleRecording entry, {
    required String songId,
  }) async {
    usedFor.add((entry.normalizedPath, songId));
    _drop(entry);
    return const PossibleRecordingActionResult(
      PossibleRecordingOutcome.usedForSong,
    );
  }

  @override
  Future<PossibleRecordingActionResult> keepChangedAudio(
    PendingPossibleRecording entry,
  ) async {
    kept.add(entry.normalizedPath);
    _drop(entry);
    return const PossibleRecordingActionResult(
      PossibleRecordingOutcome.audioKept,
    );
  }

  @override
  Future<PossibleRecordingActionResult> importSeparately(
    PendingPossibleRecording entry,
  ) async {
    separated.add(entry.normalizedPath);
    _drop(entry);
    return const PossibleRecordingActionResult(
      PossibleRecordingOutcome.imported,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final seenAt = DateTime.utc(2026, 11, 9, 12);
  const renamedPath = "music/justin bieber/purpose/i'll show you.mp3";
  const changedPath = 'music/justin bieber/purpose/sorry.mp3';

  Song song(String title, int track, int seconds) => EntityFactory.createSong(
    artistId: 'artist-1',
    albumId: 'album-1',
    albumEditionId: 'edition-1',
    title: title,
    trackNumber: track,
    durationSeconds: seconds,
    now: seenAt,
  );

  final ill = song('Ill Show You', 3, 197);
  final twin = song('Ill Show You (twin)', 4, 197);
  final sorry = song('Sorry', 5, 198);

  PendingPossibleRecording entry(
    String path,
    String title,
    PendingFileReviewKind kind, {
    required List<String> songs,
  }) => PendingPossibleRecording(
    normalizedPath: path,
    filePath: path,
    candidateSongId: songs.first,
    otherCandidateSongIds: songs.skip(1).toList(),
    title: title,
    artistName: 'Justin Bieber',
    albumTitle: 'Purpose',
    discNumber: 1,
    trackNumber: 2,
    durationSeconds: 197,
    firstSeenAt: seenAt,
    kind: kind,
  );

  Future<_FakeReview> pumpPage(
    WidgetTester tester,
    List<PossibleRecordingItem> items,
  ) async {
    final fake = _FakeReview(items);
    final unused = _Unused();
    await tester.pumpWidget(
      MaterialApp(
        home: ImportReviewPage(
          service: ImportReviewService(
            reviewRepository: _NoReviews(),
            libraryQueryRepository: _EmptyLibrary(),
            trackProfileEditingService: unused,
            artistCreationService: unused,
            songArtistCreditRepository: _UnusedCredits(),
            possibleRecordings: fake,
          ),
          userId: 'user-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('a possible replaced file explains itself and keeps the song '
      'when the user says it is the same', (tester) async {
    final replaced = entry(
      renamedPath,
      "I'll Show You",
      PendingFileReviewKind.possibleReplacedFile,
      songs: [ill.id],
    );
    final fake = await pumpPage(tester, [
      PossibleRecordingItem(entry: replaced, candidate: ill, candidates: [ill]),
    ]);

    expect(find.text('Possible replaced files'), findsOneWidget);
    expect(
      find.text(
        '“i\'ll show you.mp3” appeared where “Ill Show You” '
        "used to be. If it's the same song, Sonus will use the new file and "
        "keep the song's history, playlists and charts.",
      ),
      findsOneWidget,
    );
    expect(find.text('Different song – add separately'), findsOneWidget);
    expect(find.text('Decide later'), findsOneWidget);

    await tapVisible(tester, find.text('Same song – use this file'));

    expect(fake.usedFor, [(renamedPath, ill.id)]);
    expect(
      find.text(
        'The song now plays this file. Its history, playlists and charts '
        'are unchanged.',
      ),
      findsOneWidget,
    );
    expect(find.text('Possible replaced files'), findsNothing);
  });

  testWidgets('a file that may be one of several songs names each', (
    tester,
  ) async {
    final replaced = entry(
      renamedPath,
      "I'll Show You",
      PendingFileReviewKind.possibleReplacedFile,
      songs: [ill.id, twin.id],
    );
    final fake = await pumpPage(tester, [
      PossibleRecordingItem(
        entry: replaced,
        candidate: ill,
        candidates: [ill, twin],
      ),
    ]);

    expect(find.text('Same as “Ill Show You”'), findsOneWidget);
    await tapVisible(tester, find.text('Same as “Ill Show You (twin)”'));
    expect(fake.usedFor, [(renamedPath, twin.id)]);
  });

  testWidgets('"Different song" adds it separately', (tester) async {
    final replaced = entry(
      renamedPath,
      "I'll Show You",
      PendingFileReviewKind.possibleReplacedFile,
      songs: [ill.id],
    );
    final fake = await pumpPage(tester, [
      PossibleRecordingItem(entry: replaced, candidate: ill, candidates: [ill]),
    ]);

    await tapVisible(tester, find.text('Different song – add separately'));
    expect(fake.separated, [renamedPath]);
  });

  testWidgets('changed audio says the song still plays it, and can be kept', (
    tester,
  ) async {
    final changed = entry(
      changedPath,
      'Sorry',
      PendingFileReviewKind.audioChanged,
      songs: [sorry.id],
    );
    final fake = await pumpPage(tester, [
      PossibleRecordingItem(
        entry: changed,
        candidate: sorry,
        candidates: [sorry],
      ),
    ]);

    expect(find.text('Changed audio'), findsOneWidget);
    expect(
      find.text(
        'The music in “sorry.mp3” changed. It still plays '
        '“Sorry”.',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Keep this recording as the same song'));
    expect(fake.kept, [changedPath]);
    expect(find.text('Kept as the same song.'), findsOneWidget);
  });

  testWidgets('Decide later leaves the file without a decision', (
    tester,
  ) async {
    final replaced = entry(
      renamedPath,
      "I'll Show You",
      PendingFileReviewKind.possibleReplacedFile,
      songs: [ill.id],
    );
    final fake = await pumpPage(tester, [
      PossibleRecordingItem(entry: replaced, candidate: ill, candidates: [ill]),
    ]);

    await tapVisible(tester, find.text('Decide later'));
    expect(fake.usedFor, isEmpty);
    expect(fake.separated, isEmpty);
    expect(
      find.text('Left for later. It stays in Import Review.'),
      findsOneWidget,
    );
  });

  testWidgets('fits 320dp at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpPage(tester, [
      PossibleRecordingItem(
        entry: entry(
          renamedPath,
          "I'll Show You",
          PendingFileReviewKind.possibleReplacedFile,
          songs: [ill.id, twin.id],
        ),
        candidate: ill,
        candidates: [ill, twin],
      ),
      PossibleRecordingItem(
        entry: entry(
          changedPath,
          'Sorry',
          PendingFileReviewKind.audioChanged,
          songs: [sorry.id],
        ),
        candidate: sorry,
        candidates: [sorry],
      ),
    ]);
    expect(tester.takeException(), isNull);
  });
}
