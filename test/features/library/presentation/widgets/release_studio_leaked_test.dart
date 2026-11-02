// SN-50 A-Q2C: Release Studio's Leaked switch marks the whole release. It
// is set only by the user and is independent of song leak labels.
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
import 'package:sonus_next/features/library/presentation/widgets/album_studio/release_studio_leaked.dart';

class _Library
    implements LibraryQueryRepository, ProjectCollaboratorQueryRepository {
  @override
  Future<List<LibraryAlbum>> getAlbums() async => [
    LibraryAlbum(
      albumId: 'album-1',
      title: 'Unfinished Hours',
      artistId: 'artist-1',
      artistName: 'Ivy Calder',
      trackCount: 4,
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
  final Map<String, AlbumLeakedClassification> leaked = {};
  bool failReads = false;

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async =>
      const [];

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async => const [];

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async => const [];

  @override
  Future<List<AlbumLiveClassification>> getLiveClassifications() async =>
      const [];

  @override
  Future<List<AlbumLeakedClassification>> getLeakedClassifications() async {
    if (failReads) throw StateError('unreadable');
    return leaked.values.toList();
  }

  @override
  Future<void> saveLeakedClassification(
    AlbumLeakedClassification classification,
  ) async => leaked[classification.albumId] = classification;

  @override
  Future<void> deleteLeakedClassification(String albumId) async =>
      leaked.remove(albumId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_Organization> pump(
    WidgetTester tester, {
    _Organization? organization,
    double textScale = 1,
  }) async {
    final repository = organization ?? _Organization();
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
              ReleaseStudioLeaked(
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
      tester.widget<SwitchListTile>(key('release-studio-leaked-switch')).value;

  testWidgets('off by default, with a short explanation', (tester) async {
    final repository = await pump(tester);

    expect(switchValue(tester), isFalse);
    expect(
      find.text(
        'Mark the whole release as leaked. Song leak labels are set per song.',
      ),
      findsOneWidget,
    );
    expect(repository.leaked, isEmpty);
  });

  testWidgets('turning it on marks the release; off unmarks it', (
    tester,
  ) async {
    final repository = await pump(tester);

    await tester.tap(key('release-studio-leaked-switch'));
    await tester.pumpAndSettle();
    expect(repository.leaked.keys, ['album-1']);
    expect(switchValue(tester), isTrue);
    expect(find.text('Marked as leaked.'), findsOneWidget);

    await tester.tap(key('release-studio-leaked-switch'));
    await tester.pumpAndSettle();
    expect(repository.leaked, isEmpty);
    expect(switchValue(tester), isFalse);
  });

  testWidgets('an unreadable state is said, and the switch stays off limits', (
    tester,
  ) async {
    await pump(tester, organization: _Organization()..failReads = true);

    expect(
      tester
          .widget<SwitchListTile>(key('release-studio-leaked-switch'))
          .onChanged,
      isNull,
    );
    expect(find.textContaining('could not be read'), findsOneWidget);
  });

  testWidgets('a screen reader hears a labelled switch', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final tile = tester
        .getSemantics(key('release-studio-leaked-switch'))
        .getSemanticsData();
    expect(tile.label, startsWith('Leaked release'));
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
