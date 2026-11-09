// App Update 1.2 patches, Checkpoint 4 (BUG-04): Tracks has Charts' Back
// to top, clear of the A-Z rail. Fictional fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/presentation/widgets/alphabet_rail.dart';

import 'tracks_page_test.dart' as base;

void main() {
  const button = ValueKey<String>('tracks-scroll-to-top');

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final names = [
      for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
        for (var i = 0; i < 8; i++) '$letter Song $i',
    ];
    await tester.pumpWidget(
      base.buildSubject(
        repository: base.FakeLibraryQueryRepository(
          tracks: [
            for (final (i, name) in names.indexed)
              base.createTrack(songId: 'song-$i', title: name),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition list(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey<String>('tracks-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(button),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('Back to top appears far down the songs, clear of the A-Z '
      'rail, and returns to the top', (tester) async {
    await pump(tester);
    expect(opacity(tester), 0);

    list(tester).jumpTo(4000);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);

    final rail = tester.getRect(find.byType(AlphabetRail));
    final fab = tester.getRect(find.byKey(button));
    expect(fab.overlaps(rail), isFalse, reason: 'the rail stays usable');

    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();
    expect(list(tester).pixels, 0);
    expect(find.text('A Song 0'), findsOneWidget);
  });
}
