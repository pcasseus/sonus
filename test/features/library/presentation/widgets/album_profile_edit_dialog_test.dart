// App Update 1.2 BUG-10: Import Review's album dialog edits the release
// date with the same editor as Edit Release, keeping its precision.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/presentation/widgets/album_profile_edit_dialog.dart';

import '../../../../support/release_date_editor_driver.dart';

void main() {
  late AlbumProfileEditDraft? draft;

  Future<void> open(WidgetTester tester, LibraryAlbum album) async {
    draft = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                draft = await showDialog<AlbumProfileEditDraft>(
                  context: context,
                  builder: (_) => AlbumProfileEditDialog(
                    album: album,
                    artists: [
                      LibraryArtist(
                        artistId: 'artist-1',
                        name: 'Test Artist',
                        albumCount: 1,
                        songCount: 1,
                        dateAdded: DateTime(2026, 1, 1),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  LibraryAlbum album({
    DateTime? releaseDate,
    ReleaseDatePrecision? precision,
  }) => LibraryAlbum(
    albumId: 'album-1',
    title: 'Purpose',
    artistId: 'artist-1',
    artistName: 'Test Artist',
    primaryEditionId: 'edition-1',
    primaryEditionTitle: 'Standard',
    releaseDate: releaseDate,
    releaseDatePrecision: precision,
    trackCount: 1,
    dateAdded: DateTime(2026, 1, 1),
  );

  Finder dateField() =>
      find.byKey(const ValueKey<String>('album-release-date-field'));

  Future<void> saveDialog(WidgetTester tester) async {
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved date at its precision and keeps it', (
    tester,
  ) async {
    await open(
      tester,
      album(
        releaseDate: DateTime.utc(2015, 11),
        precision: ReleaseDatePrecision.month,
      ),
    );
    expect(
      find.descendant(of: dateField(), matching: find.text('November 2015')),
      findsOneWidget,
    );

    await saveDialog(tester);
    expect(draft!.releaseDate, DateTime.utc(2015, 11));
    expect(draft!.releaseDatePrecision, ReleaseDatePrecision.month);
  });

  testWidgets('the editor sets a day, and saving carries it', (tester) async {
    await open(tester, album());
    expect(
      find.descendant(of: dateField(), matching: find.text('Not set')),
      findsOneWidget,
    );

    await tester.tap(dateField());
    await tester.pumpAndSettle();
    await enterReleaseDate(tester, '2015-11-13');
    await tester.tap(
      find.byKey(const ValueKey<String>('release-studio-save-date')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: dateField(),
        matching: find.text('November 13, 2015'),
      ),
      findsOneWidget,
    );

    await saveDialog(tester);
    expect(draft!.releaseDate, DateTime.utc(2015, 11, 13));
    expect(draft!.releaseDatePrecision, ReleaseDatePrecision.day);
  });

  testWidgets('cancelling the editor changes nothing; removing clears', (
    tester,
  ) async {
    await open(
      tester,
      album(
        releaseDate: DateTime.utc(2015),
        precision: ReleaseDatePrecision.year,
      ),
    );
    await tester.tap(dateField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dateField(), matching: find.text('2015')),
      findsOneWidget,
    );

    await tester.tap(dateField());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('release-date-remove')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('release-studio-save-date')),
    );
    await tester.pumpAndSettle();

    await saveDialog(tester);
    expect(draft!.releaseDate, isNull);
    expect(draft!.releaseDatePrecision, isNull);
  });
}
