import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/models/track_profile_edit_draft.dart';
import 'package:sonus_next/features/library/presentation/pages/track_studio_page.dart';
import 'package:sonus_next/features/library/presentation/widgets/track_profile_edit_dialog.dart';

// SN-48J J2 (scenario G): both track editors keep the edition the user was
// editing. Before the fix they sent the album's primary edition with every
// save, which turned a Deluxe-only track into a Standard track too.
void main() {
  /// A track as listed in the Deluxe edition of an album whose primary
  /// edition is Standard.
  LibraryTrack deluxeListing() => LibraryTrack(
    songId: 'song-bonus',
    title: 'Bonus',
    artistId: 'artist-1',
    artistName: 'Fixture Artist',
    albumId: 'album-a',
    albumTitle: 'Album A',
    albumEditionId: 'edition-deluxe',
    albumEditionTitle: 'Deluxe',
    albumEditionType: AlbumEditionType.deluxe,
    trackNumber: 12,
    discNumber: 1,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026),
    isAvailable: true,
  );

  LibraryAlbum album(String id, String title, String primary) => LibraryAlbum(
    albumId: id,
    title: title,
    artistId: 'artist-1',
    artistName: 'Fixture Artist',
    trackCount: 12,
    dateAdded: DateTime(2026),
    primaryEditionId: primary,
    primaryEditionTitle: 'Standard',
    primaryEditionType: AlbumEditionType.standard,
  );

  final albums = [
    album('album-a', 'Album A', 'edition-a-standard'),
    album('album-b', 'Album B', 'edition-b-standard'),
  ];

  Future<TrackProfileEditDraft?> run(
    WidgetTester tester, {
    required bool studio,
    String? chooseAlbumTitle,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    TrackProfileEditDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                draft = studio
                    ? await Navigator.of(context).push<TrackProfileEditDraft>(
                        MaterialPageRoute(
                          builder: (_) => TrackStudioPage(
                            track: deluxeListing(),
                            albums: albums,
                          ),
                        ),
                      )
                    : await showDialog<TrackProfileEditDraft>(
                        context: context,
                        builder: (_) => TrackProfileEditDialog(
                          track: deluxeListing(),
                          albums: albums,
                        ),
                      );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    if (chooseAlbumTitle != null) {
      final field = find.byKey(const ValueKey<String>('track-album-field'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(chooseAlbumTitle).last);
      await tester.pumpAndSettle();
    }

    final saveKey = studio
        ? 'track-studio-save-button'
        : 'track-edit-save-button';
    final save = find.byKey(ValueKey<String>(saveKey));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    return draft;
  }

  for (final (name, studio) in [
    ('Track Studio', true),
    ('Import Review dialog', false),
  ]) {
    group(name, () {
      testWidgets('a same-album save keeps the edition being edited', (
        tester,
      ) async {
        final draft = await run(tester, studio: studio);

        expect(draft, isNotNull);
        expect(draft!.albumId, 'album-a');
        expect(draft.moveToEditionId, isNull);
        expect(draft.placementEditionId, 'edition-deluxe');
      });

      testWidgets('choosing another album moves to its primary edition', (
        tester,
      ) async {
        final draft = await run(
          tester,
          studio: studio,
          chooseAlbumTitle: 'Album B',
        );

        expect(draft, isNotNull);
        expect(draft!.albumId, 'album-b');
        expect(draft.moveToEditionId, 'edition-b-standard');
      });
    });
  }
}
