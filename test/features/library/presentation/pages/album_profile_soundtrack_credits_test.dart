import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';

import 'album_profile_page_test.dart' as base;

// UI redesign C2 (D10): on soundtracks and cast recordings, track rows with
// many performers show a compact credit summary that expands.
void main() {
  const many = ['Ada Moor', 'Ben Lark', 'Cy Vale', 'Dee Rowe', 'Eve Hart'];
  const manyFull = 'Ft. Ada Moor, Ben Lark, Cy Vale, Dee Rowe, Eve Hart';
  const manyCompact = 'Ft. Ada Moor, Ben Lark + 3 others';

  List<LibraryTrack> tracks() => [
    base.createTrack(songId: 's1', title: 'Overture', featuredArtists: many),
    base.createTrack(
      songId: 's2',
      title: 'Duet',
      trackNumber: 2,
      featuredArtists: const ['Ada Moor', 'Ben Lark'],
    ),
  ];

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  Future<(_FakeOrganizationRepository, List<LibraryTrack>)> pump(
    WidgetTester tester, {
    ReleaseKind? kind,
    bool withService = true,
    Size size = const Size(411, 1200),
    double textScale = 1,
    bool disableAnimations = false,
    ThemeData? theme,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final list = tracks();
    final repository = base.FakeLibraryQueryRepository(
      album: base.createAlbum(title: 'Stage Show'),
      tracks: list,
    );
    final organization = _FakeOrganizationRepository([
      if (kind != null)
        AlbumReleaseClassification(
          albumId: 'album-1',
          kind: kind,
          authority: ReleaseClassificationAuthority.manual,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      // Another release's kind never applies here.
      AlbumReleaseClassification(
        albumId: 'album-other',
        kind: ReleaseKind.soundtrack,
        authority: ReleaseClassificationAuthority.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ]);

    await tester.pumpWidget(
      Provider<LibraryOrganizationService?>.value(
        value: withService
            ? LibraryOrganizationService(
                library: repository,
                collaborators: _UnusedCollaborators(),
                organization: organization,
              )
            : null,
        child: base.buildSubject(
          repository: repository,
          theme: theme,
          appBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (organization, list);
  }

  Finder rowText(String songId, String text) => find.descendant(
    of: byKey('album-track-$songId'),
    matching: find.text(text),
  );

  for (final kind in [ReleaseKind.soundtrack, ReleaseKind.castRecording]) {
    testWidgets('${kind.label}: many credits show a summary', (tester) async {
      await pump(tester, kind: kind);

      expect(rowText('s1', manyCompact), findsOneWidget);
      expect(rowText('s1', manyFull), findsNothing);
      expect(byKey('album-track-credits-toggle-s1'), findsOneWidget);
      // Few credits stay as they were.
      expect(rowText('s2', 'Ft. Ada Moor, Ben Lark'), findsOneWidget);
      expect(byKey('album-track-credits-toggle-s2'), findsNothing);
    });
  }

  testWidgets('expanding reveals the full credits and collapses again', (
    tester,
  ) async {
    await pump(tester, kind: ReleaseKind.soundtrack);

    await tester.tap(byKey('album-track-credits-toggle-s1'));
    await tester.pumpAndSettle();
    expect(rowText('s1', manyFull), findsOneWidget);
    expect(rowText('s1', manyCompact), findsNothing);

    await tester.tap(byKey('album-track-credits-toggle-s1'));
    await tester.pumpAndSettle();
    expect(rowText('s1', manyCompact), findsOneWidget);
  });

  testWidgets('screen readers hear the full credits and the state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, kind: ReleaseKind.castRecording);

    final toggle = byKey('album-track-credits-toggle-s1');
    var node = tester.getSemantics(toggle);
    expect(node.label, contains(manyFull));
    expect(
      node,
      isSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    node = tester.getSemantics(toggle);
    expect(node.label, contains(manyFull));
    expect(node, isSemantics(hasExpandedState: true, isExpanded: true));
    semantics.dispose();
  });

  testWidgets('the expand control is at least 48dp tall', (tester) async {
    await pump(tester, kind: ReleaseKind.soundtrack);

    final size = tester.getSize(byKey('album-track-credits-toggle-s1'));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('reduced motion expands at once', (tester) async {
    await pump(tester, kind: ReleaseKind.soundtrack, disableAnimations: true);

    await tester.tap(byKey('album-track-credits-toggle-s1'));
    await tester.pump();
    expect(rowText('s1', manyFull), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('album-track-credits-s1'),
        matching: find.byType(AnimatedSize),
      ),
      findsNothing,
    );
  });

  // Register R6: the in-app Reduce motion setting reaches the theme's
  // SonusMotion, never MediaQuery, and must stop the animation too.
  testWidgets('in-app Reduce motion expands at once', (tester) async {
    await pump(
      tester,
      kind: ReleaseKind.soundtrack,
      theme: ThemeData(
        extensions: const [
          SonusMotion(reduced: true, curve: Curves.easeOutCubic),
        ],
      ),
    );

    await tester.tap(byKey('album-track-credits-toggle-s1'));
    await tester.pump();
    expect(rowText('s1', manyFull), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('album-track-credits-s1'),
        matching: find.byType(AnimatedSize),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping the title does not expand the credits', (tester) async {
    await pump(tester, kind: ReleaseKind.soundtrack);

    // The row keeps its key, title and menu.
    expect(byKey('album-track-s1'), findsOneWidget);
    expect(byKey('album-track-menu-s1'), findsOneWidget);
    await tester.tap(rowText('s1', 'Overture'));
    await tester.pumpAndSettle();
    expect(rowText('s1', manyCompact), findsOneWidget);
  });

  testWidgets('compilations show the full line', (tester) async {
    await pump(tester, kind: ReleaseKind.compilation);

    expect(rowText('s1', manyFull), findsOneWidget);
    expect(byKey('album-track-credits-toggle-s1'), findsNothing);
  });

  testWidgets('unclassified releases show the full line', (tester) async {
    await pump(tester);

    expect(rowText('s1', manyFull), findsOneWidget);
    expect(byKey('album-track-credits-toggle-s1'), findsNothing);
  });

  testWidgets('without the organization service, the full line', (
    tester,
  ) async {
    await pump(tester, kind: ReleaseKind.soundtrack, withService: false);

    expect(rowText('s1', manyFull), findsOneWidget);
    expect(byKey('album-track-credits-toggle-s1'), findsNothing);
  });

  testWidgets('a failed read leaves the full line', (tester) async {
    final (organization, _) = await pump(tester, kind: ReleaseKind.soundtrack);
    expect(organization.reads, greaterThan(0));

    // Fresh page with a failing repository.
    await tester.pumpWidget(const SizedBox.shrink());
    final repository = base.FakeLibraryQueryRepository(
      album: base.createAlbum(),
      tracks: tracks(),
    );
    await tester.pumpWidget(
      Provider<LibraryOrganizationService?>.value(
        value: LibraryOrganizationService(
          library: repository,
          collaborators: _UnusedCollaborators(),
          organization: _FakeOrganizationRepository(const [], fail: true),
        ),
        child: base.buildSubject(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(rowText('s1', manyFull), findsOneWidget);
  });

  testWidgets('stored credits are untouched', (tester) async {
    final (organization, list) = await pump(
      tester,
      kind: ReleaseKind.soundtrack,
    );
    await tester.tap(byKey('album-track-credits-toggle-s1'));
    await tester.pumpAndSettle();

    expect(list.first.featuredArtists, many);
    expect(list.first.coPrimaryArtists, isEmpty);
    expect(list.first.guestArtists, isEmpty);
    // Only reads: any write would hit the Fake and throw.
    expect(organization.reads, greaterThan(0));
  });

  testWidgets('fits 320dp at 2x text, collapsed and expanded', (tester) async {
    await pump(
      tester,
      kind: ReleaseKind.soundtrack,
      size: const Size(320, 4000),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    final row = byKey('album-track-s1');
    final toggle = byKey('album-track-credits-toggle-s1');
    expect(tester.getRect(toggle).right, lessThanOrEqualTo(320));
    expect(
      tester.getRect(toggle).right,
      lessThanOrEqualTo(tester.getRect(row).right),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(rowText('s1', '3:00 • $manyFull'), findsOneWidget);
    expect(tester.getRect(toggle).right, lessThanOrEqualTo(320));
  });
}

class _FakeOrganizationRepository extends Fake
    implements LibraryOrganizationRepository {
  _FakeOrganizationRepository(this.classifications, {this.fail = false});

  final List<AlbumReleaseClassification> classifications;
  final bool fail;
  int reads = 0;

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async {
    reads++;
    if (fail) throw StateError('unreadable');
    return classifications;
  }
}

class _UnusedCollaborators extends Fake
    implements ProjectCollaboratorQueryRepository {}
