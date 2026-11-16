import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/library/application/services/song_single_presentation_service.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_single_presentation_repository.dart';
import 'package:sonus_next/features/library/presentation/pages/single_presentation_editor_page.dart';
import 'package:sonus_next/features/library/presentation/pages/track_studio_page.dart';

import 'artist_profile_page_test.dart' as base;

/// App Update 1.3 (REF-1.3-04): the Single's own cover and release date,
/// edited apart from the song and its album.
class _Rows implements SongSinglePresentationRepository {
  final rows = <String, SongSinglePresentation>{};

  @override
  Future<SongSinglePresentation?> getBySongId(String songId) async =>
      rows[songId];

  @override
  Future<Map<String, SongSinglePresentation>> getAll() async => {...rows};

  @override
  Future<void> save(SongSinglePresentation presentation) async {
    if (presentation.isEmpty) {
      rows.remove(presentation.songId);
    } else {
      rows[presentation.songId] = presentation;
    }
  }

  @override
  Future<void> clear(String songId) async => rows.remove(songId);
}

class _Songs implements SongRepository {
  @override
  Future<Song?> getById(String id) async => Song(
    id: id,
    artistId: 'artist-1',
    albumId: 'album-1',
    albumEditionId: 'edition-1',
    title: 'Song',
    canonicalTitle: 'song',
    trackNumber: 1,
    durationSeconds: 200,
    isSingle: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not used: $invocation');
}

class _NoPicker implements ArtworkFilePicker {
  @override
  Future<String?> pickArtworkFile() async => null;
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

void main() {
  late _Rows rows;

  setUp(() => rows = _Rows());

  Widget app(Widget home) => MultiProvider(
    providers: [
      Provider<SongSinglePresentationService?>.value(
        value: SongSinglePresentationService(
          presentations: rows,
          songs: _Songs(),
          now: () => DateTime.utc(2026, 11, 15),
        ),
      ),
      Provider<ArtworkFilePicker?>.value(value: _NoPicker()),
    ],
    child: MaterialApp(
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      home: home,
    ),
  );

  testWidgets('shows what is set; removing the cover keeps the date and '
      'turns charts off', (tester) async {
    rows.rows['s1'] = SongSinglePresentation(
      songId: 's1',
      releaseDate: ReleaseDate.of(2024, 4),
      artworkId: 'art',
      artworkPath: '/art/missing-single.png',
      useArtworkInCharts: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      app(const SinglePresentationEditorPage(songId: 's1', songTitle: 'Hit')),
    );
    await tester.pumpAndSettle();

    expect(find.text('April 2024'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(_key('single-cover-in-charts')).value,
      isTrue,
    );
    // Approved wording (App Update 1.3): the cover reaches Moments only,
    // never chart rows.
    expect(find.text('Use this cover in Moments'), findsOneWidget);
    expect(
      find.text('Otherwise Moments keep the usual artwork.'),
      findsOneWidget,
    );

    await tester.tap(_key('single-cover-remove'));
    await tester.pumpAndSettle();

    final left = rows.rows['s1']!;
    expect(left.artworkId, isNull);
    expect(left.useArtworkInCharts, isFalse);
    expect(left.releaseDate, ReleaseDate.of(2024, 4));
    expect(find.text('April 2024'), findsOneWidget);
    expect(_key('single-cover-none'), findsOneWidget);
    expect(_key('single-cover-remove'), findsNothing);
    // Without a cover the chart switch cannot be turned on.
    expect(
      tester.widget<SwitchListTile>(_key('single-cover-in-charts')).onChanged,
      isNull,
    );
  });

  testWidgets('nothing set: no date, no cover, nothing saved', (tester) async {
    await tester.pumpWidget(
      app(const SinglePresentationEditorPage(songId: 's1', songTitle: 'Hit')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not set'), findsOneWidget);
    expect(_key('single-cover-none'), findsOneWidget);
    expect(rows.rows, isEmpty);
  });

  testWidgets('works at 320 px with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: app(
          const SinglePresentationEditorPage(
            songId: 's1',
            songTitle: 'A very long song title that wraps',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('Track Studio', () {
    Future<void> openStudio(WidgetTester tester, {required bool single}) async {
      await tester.binding.setSurfaceSize(const Size(411, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          TrackStudioPage(
            track: base.createTrack(songId: 's1', isSingle: single),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a Single offers its cover and date', (tester) async {
      await openStudio(tester, single: true);
      expect(_key('track-single-presentation'), findsOneWidget);

      await tester.ensureVisible(_key('track-single-presentation'));
      await tester.tap(_key('track-single-presentation'));
      await tester.pumpAndSettle();
      expect(_key('single-presentation-editor'), findsOneWidget);
    });

    testWidgets('a song that is not a Single does not', (tester) async {
      await openStudio(tester, single: false);
      expect(_key('track-single-presentation'), findsNothing);
    });
  });
}
