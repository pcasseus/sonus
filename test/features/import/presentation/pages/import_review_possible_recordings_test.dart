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

class _FakePossibleRecordings implements PossibleRecordingReviewService {
  _FakePossibleRecordings(this.items, {required this.importOutcome});

  List<PossibleRecordingItem> items;
  final PossibleRecordingOutcome importOutcome;
  final imported = <String>[];
  final markedSame = <String>[];

  @override
  Future<List<PossibleRecordingItem>> pending() async => items;

  @override
  Future<PossibleRecordingActionResult> importSeparately(
    PendingPossibleRecording entry,
  ) async {
    imported.add(entry.normalizedPath);
    if (importOutcome != PossibleRecordingOutcome.failed &&
        importOutcome != PossibleRecordingOutcome.stillPending &&
        importOutcome != PossibleRecordingOutcome.permissionLost &&
        importOutcome != PossibleRecordingOutcome.checkFailed) {
      items = [
        for (final item in items)
          if (item.entry.normalizedPath != entry.normalizedPath) item,
      ];
    }
    return PossibleRecordingActionResult(importOutcome);
  }

  @override
  Future<void> markSameRecording(PendingPossibleRecording entry) async {
    markedSame.add(entry.normalizedPath);
    items = [
      for (final item in items)
        if (item.entry.normalizedPath != entry.normalizedPath) item,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final seenAt = DateTime.utc(2026, 10, 25, 12);
  const path = 'music/quiet rooms/09 errtime.mp3';
  const importKey = ValueKey<String>('possible-recording-import-$path');
  const sameKey = ValueKey<String>('possible-recording-same-$path');
  const laterKey = ValueKey<String>('possible-recording-later-$path');

  final entry = PendingPossibleRecording(
    normalizedPath: path,
    filePath: 'Music/Quiet Rooms/09 ErrTime.mp3',
    candidateSongId: 'song-kept',
    title: 'ErrTime',
    artistName: 'Fictional Harbour',
    albumTitle: 'Quiet Rooms',
    discNumber: 1,
    trackNumber: 9,
    durationSeconds: 147,
    firstSeenAt: seenAt,
  );

  final Song kept = EntityFactory.createSong(
    artistId: 'artist-1',
    albumId: 'album-1',
    albumEditionId: 'edition-1',
    title: 'ErrTime',
    trackNumber: 3,
    durationSeconds: 146,
    now: seenAt,
  );

  Future<_FakePossibleRecordings> pumpPage(
    WidgetTester tester, {
    PossibleRecordingOutcome importOutcome = PossibleRecordingOutcome.imported,
  }) async {
    final possibleRecordings = _FakePossibleRecordings([
      PossibleRecordingItem(entry: entry, candidate: kept),
    ], importOutcome: importOutcome);
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
            possibleRecordings: possibleRecordings,
          ),
          userId: 'user-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return possibleRecordings;
  }

  testWidgets('shows a possible different recording with what it may '
      'duplicate', (tester) async {
    await pumpPage(tester);

    expect(find.text('Possible different recordings'), findsOneWidget);
    expect(find.text('ErrTime'), findsOneWidget);
    expect(find.text('Fictional Harbour · Quiet Rooms'), findsOneWidget);
    expect(find.text('Disc 1 · Track 9 · 2:27'), findsOneWidget);
    expect(find.text('Music/Quiet Rooms/09 ErrTime.mp3'), findsOneWidget);
    expect(
      find.text('May be the same as "ErrTime" (Disc 1 · Track 3 · 2:26)'),
      findsOneWidget,
    );
    expect(find.text('Import separately'), findsOneWidget);
    expect(find.text('Same recording'), findsOneWidget);
    expect(find.text('Decide later'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-review-complete')),
      findsNothing,
    );
  });

  testWidgets('Import separately imports the file and says so', (tester) async {
    final fake = await pumpPage(tester);

    await tester.tap(find.byKey(importKey));
    await tester.pumpAndSettle();

    expect(fake.imported, [path]);
    expect(
      find.text(
        "Imported as a separate song. It's in your review list so you can "
        'check its details.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(importKey), findsNothing);
  });

  testWidgets('Import separately of a missing file says why it left the '
      'list', (tester) async {
    await pumpPage(
      tester,
      importOutcome: PossibleRecordingOutcome.fileUnavailable,
    );

    await tester.tap(find.byKey(importKey));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This file could not be found, so it was removed from the review '
        'list. Nothing was imported.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(importKey), findsNothing);
  });

  // SN-50 §4: a file Sonus can no longer reach stays listed.
  for (final (outcome, message) in [
    (
      PossibleRecordingOutcome.permissionLost,
      "Sonus can't read this folder any more. Reconnect it in Imports.",
    ),
    (
      PossibleRecordingOutcome.checkFailed,
      'Could not check this file. It stays in this list. Try again.',
    ),
  ]) {
    testWidgets('Import separately, ${outcome.name}: says why and keeps the '
        'file listed', (tester) async {
      await pumpPage(tester, importOutcome: outcome);

      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.byKey(importKey), findsOneWidget);
    });
  }

  testWidgets('Same recording records the choice and leaves the list', (
    tester,
  ) async {
    final fake = await pumpPage(tester);

    await tester.tap(find.byKey(sameKey));
    await tester.pumpAndSettle();

    expect(fake.markedSame, [path]);
    expect(fake.imported, isEmpty);
    expect(
      find.text(
        'Marked as the same recording. Nothing was added to your library.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(sameKey), findsNothing);
  });

  testWidgets('Decide later leaves the file for later without a decision', (
    tester,
  ) async {
    final fake = await pumpPage(tester);

    await tester.tap(find.byKey(laterKey));
    await tester.pumpAndSettle();

    expect(fake.imported, isEmpty);
    expect(fake.markedSame, isEmpty);
    expect(fake.items, hasLength(1));
    expect(
      find.text('Left for later. It stays in Import Review.'),
      findsOneWidget,
    );
    expect(find.byKey(laterKey), findsNothing);
  });
}
