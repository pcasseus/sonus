// App Update 1.2 patches, Checkpoint 3 (BUG-08): moving between an Artist
// Profile's sections glides there in one smooth motion without lighting
// every tab on the way.
// Fictional fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/library/presentation/widgets/artist_profile/artist_profile_section_tabs.dart';

import 'artist_profile_page_test.dart' as base;

LibraryTrack _guest(int i) => LibraryTrack(
  songId: 'guest-$i',
  title: 'Guest Song $i',
  artistId: 'other-artist',
  artistName: 'Other Fixture',
  albumId: 'their-album-$i',
  albumTitle: 'Their Album $i',
  albumEditionId: 'their-edition-$i',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.values.first,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const ['Test Artist'],
  dateAdded: DateTime(2026, 1, 1),
  filePath: '/music/guest-$i.mp3',
  isAvailable: true,
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool reduceMotion = false,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(411, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final own = [
      for (var i = 0; i < 12; i++)
        base.createTrack(songId: 'own-$i', title: 'Own Song $i'),
    ];
    final collaborations = [for (var i = 0; i < 30; i++) _guest(i)];
    final repository = base.FakeLibraryQueryRepository(
      artist: base.createArtist(),
      albums: [base.createAlbum()],
      tracks: own,
      allTracks: [...own, ...collaborations],
    );
    final plays = base.FakeQualifiedPlayRepository([
      for (final track in own)
        for (var n = 0; n < 3; n++)
          base.qualifiedPlay(track.songId, at: DateTime.utc(2026, 1, 1 + n)),
    ]);

    await tester.pumpWidget(
      base.buildSubject(
        repository: repository,
        qualifiedPlays: plays,
        theme: SonusThemeFactory.build(
          SonusAppearanceSpec(reduceMotion: reduceMotion),
        ),
        home: const ArtistProfilePage(
          artistId: 'artist-1',
          initialArtistName: 'Test Artist',
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  ScrollPosition pageScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('artist-profile-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  ValueNotifier<int> selectedTab(WidgetTester tester) => tester
      .widget<ArtistProfileSectionTabs>(find.byType(ArtistProfileSectionTabs))
      .selected;

  Finder tab(int index) =>
      find.byKey(ValueKey<String>('artist-profile-section-tab-$index'));

  testWidgets('a far section is reached in one glide: no jumps, no '
      'overshoot, and only the chosen tab lit on the way', (tester) async {
    await pump(tester);
    final tabs = find.byType(ArtistProfileSectionTabs);
    expect(tabs, findsOneWidget);
    final collaborationsTab = tester
        .widget<ArtistProfileSectionTabs>(tabs)
        .tabs
        .indexWhere((t) => t.label == 'Collaborations');
    expect(collaborationsTab, greaterThan(0));
    // The section is far enough down that it is not built yet.
    expect(
      tester
          .widget<ArtistProfileSectionTabs>(tabs)
          .tabs[collaborationsTab]
          .anchor
          .currentContext,
      isNull,
    );

    final position = pageScroll(tester);
    final lit = <int>{};
    final notifier = selectedTab(tester);
    void record() => lit.add(notifier.value);
    notifier.addListener(record);
    addTearDown(() => notifier.removeListener(record));

    // Recorded before the tap: a jump can happen within the tap itself.
    final offsets = <double>[position.pixels];
    tester.widget<InkWell>(tab(collaborationsTab)).onTap!();
    offsets.add(position.pixels);
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      offsets.add(position.pixels);
    }
    await tester.pumpAndSettle();
    offsets.add(position.pixels);

    var largestStep = 0.0;
    var wentBack = false;
    for (var i = 1; i < offsets.length; i++) {
      final step = offsets[i] - offsets[i - 1];
      if (step > largestStep) largestStep = step;
      if (step < -0.5) wentBack = true;
    }
    expect(
      largestStep,
      lessThan(position.viewportDimension * 0.5),
      reason: 'no frame lurches most of a screen at once',
    );
    expect(wentBack, isFalse, reason: 'no overshoot and bounce back');
    expect(lit, {collaborationsTab}, reason: 'no tab passed on the way lit');
    expect(notifier.value, collaborationsTab);
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('with Reduce motion the section is reached without animation', (
    tester,
  ) async {
    await pump(tester, reduceMotion: true);
    final tabs = tester
        .widget<ArtistProfileSectionTabs>(find.byType(ArtistProfileSectionTabs))
        .tabs;
    final collaborationsTab = tabs.indexWhere(
      (t) => t.label == 'Collaborations',
    );

    // The tabs scroll away with the page, so their state is read first.
    final notifier = selectedTab(tester);
    final position = pageScroll(tester);
    tester.widget<InkWell>(tab(collaborationsTab)).onTap!();
    await tester.pumpAndSettle();

    expect(notifier.value, collaborationsTab);
    expect(position.pixels, greaterThan(0));
  });
}
