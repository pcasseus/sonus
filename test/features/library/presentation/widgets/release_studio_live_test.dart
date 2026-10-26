// SN-49: Release Studio's Live switch. Live sits beside the format; the
// user's answer, yes or no, is kept and can be removed again.
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';
import 'package:sonus_next/features/library/presentation/widgets/album_studio/release_studio_live.dart';

class _Library
    implements LibraryQueryRepository, ProjectCollaboratorQueryRepository {
  @override
  Future<List<LibraryAlbum>> getAlbums() async => [
    LibraryAlbum(
      albumId: 'album-1',
      title: 'Live Session',
      artistId: 'artist-1',
      artistName: 'Artist',
      trackCount: 3,
      dateAdded: DateTime(2026),
    ),
  ];

  @override
  Future<List<ProjectCollaborator>> getProjectCollaborators({
    String? albumId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Organization implements LibraryOrganizationRepository {
  final Map<String, AlbumLiveClassification> lives = {};

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async =>
      const [];

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async => const [];

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async => const [];

  @override
  Future<List<AlbumLiveClassification>> getLiveClassifications() async =>
      lives.values.toList();

  @override
  Future<void> saveLiveClassification(AlbumLiveClassification live) async =>
      lives[live.albumId] = live;

  @override
  Future<void> deleteLiveClassification(String albumId) async =>
      lives.remove(albumId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final at = DateTime.utc(2026, 10, 26);

  Future<_Organization> pump(
    WidgetTester tester, {
    AlbumLiveClassification? existing,
    double textScale = 1,
  }) async {
    final repository = _Organization();
    if (existing != null) repository.lives[existing.albumId] = existing;
    final library = _Library();
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              ReleaseStudioLive(
                albumId: 'album-1',
                service: LibraryOrganizationService(
                  library: library,
                  collaborators: library,
                  organization: repository,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  bool switchValue(WidgetTester tester) =>
      tester.widget<SwitchListTile>(key('release-studio-live-switch')).value;

  testWidgets('unstated is off and nothing is saved', (tester) async {
    final repository = await pump(tester);

    expect(switchValue(tester), isFalse);
    expect(key('release-studio-live-reset'), findsNothing);
    expect(repository.lives, isEmpty);
  });

  testWidgets('turning it on saves the user\'s live; off is kept as "not '
      'live"; removing the choice forgets it', (tester) async {
    final repository = await pump(tester);

    await tester.tap(key('release-studio-live-switch'));
    await tester.pumpAndSettle();
    expect(repository.lives['album-1']!.isLive, isTrue);
    expect(
      repository.lives['album-1']!.authority,
      ReleaseClassificationAuthority.manual,
    );
    expect(
      find.text('Set by you. Metadata lookups never change it.'),
      findsOneWidget,
    );

    await tester.tap(key('release-studio-live-switch'));
    await tester.pumpAndSettle();
    expect(repository.lives['album-1']!.isLive, isFalse);

    await tester.tap(key('release-studio-live-reset'));
    await tester.pumpAndSettle();
    expect(repository.lives, isEmpty);
    expect(switchValue(tester), isFalse);
  });

  testWidgets('a MusicBrainz suggestion says where it came from', (
    tester,
  ) async {
    await pump(
      tester,
      existing: AlbumLiveClassification(
        albumId: 'album-1',
        isLive: true,
        authority: ReleaseClassificationAuthority.external,
        createdAt: at,
        updatedAt: at,
      ),
    );

    expect(switchValue(tester), isTrue);
    expect(find.text('Suggested by MusicBrainz.'), findsOneWidget);
    expect(key('release-studio-live-reset'), findsNothing);
  });

  testWidgets('a screen reader hears a labelled switch', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    // The switch's toggle merges into the labelled tile: one focus stop
    // that reads "Live recording", its explanation, and on or off.
    final tile = tester
        .getSemantics(key('release-studio-live-switch'))
        .getSemanticsData();
    expect(tile.label, startsWith('Live recording'));
    expect(tile.flagsCollection.isToggled, Tristate.isFalse);
    expect(tile.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('fits 320dp at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
