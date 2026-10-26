// SN-45: Release Studio's Format control. One field, three choices; the
// user's choice is saved as manual and can be removed again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';
import 'package:sonus_next/features/library/presentation/widgets/album_studio/release_studio_format.dart';

class _Library
    implements LibraryQueryRepository, ProjectCollaboratorQueryRepository {
  @override
  Future<List<LibraryAlbum>> getAlbums() async => [
    LibraryAlbum(
      albumId: 'album-1',
      title: '15 Minutes',
      artistId: 'artist-1',
      artistName: 'Madison Beer',
      trackCount: 1,
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
  final Map<String, AlbumReleaseFormat> formats = {};

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async =>
      formats.values.toList();

  @override
  Future<void> saveFormat(AlbumReleaseFormat format) async =>
      formats[format.albumId] = format;

  @override
  Future<void> deleteFormat(String albumId) async => formats.remove(albumId);

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async =>
      const [];

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_Organization> pump(
    WidgetTester tester, {
    AlbumReleaseFormat? existing,
    double textScale = 1,
  }) async {
    final repository = _Organization();
    if (existing != null) repository.formats[existing.albumId] = existing;
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
              ReleaseStudioFormat(
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

  testWidgets('an unstated format shows as Album and says so', (tester) async {
    await pump(tester);

    final choice = tester.widget<SegmentedButton<ReleaseFormat>>(
      key('release-studio-format-choice'),
    );
    expect(choice.selected, {ReleaseFormat.album});
    expect(find.text('Not stated, so it counts as an Album.'), findsOneWidget);
    expect(key('release-studio-format-reset'), findsNothing);
  });

  testWidgets('marking it a Single saves a manual choice', (tester) async {
    final repository = await pump(tester);

    await tester.tap(key('release-studio-format-single'));
    await tester.pumpAndSettle();

    final saved = repository.formats['album-1']!;
    expect(saved.format, ReleaseFormat.single);
    expect(saved.authority, ReleaseClassificationAuthority.manual);
    expect(find.text('Saved as a Single.'), findsOneWidget);
    expect(
      find.text(
        'Singles chart through their songs on the Sonus Hot 100, not as a '
        'release.',
      ),
      findsOneWidget,
    );

    await tester.tap(key('release-studio-format-reset'));
    await tester.pumpAndSettle();
    expect(repository.formats, isEmpty);
  });

  testWidgets('a MusicBrainz suggestion says where it came from', (
    tester,
  ) async {
    await pump(
      tester,
      existing: AlbumReleaseFormat(
        albumId: 'album-1',
        format: ReleaseFormat.ep,
        authority: ReleaseClassificationAuthority.external,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

    expect(find.text('Suggested by MusicBrainz.'), findsOneWidget);
    expect(key('release-studio-format-reset'), findsNothing);
  });

  testWidgets('fits 320dp at 2x text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    final single = tester.getSize(key('release-studio-format-choice'));
    expect(single.height, greaterThanOrEqualTo(44));
  });
}
