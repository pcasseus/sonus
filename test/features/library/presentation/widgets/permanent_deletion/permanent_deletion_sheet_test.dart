// App Update 1.2: the permanent-deletion sheet and confirmation. Synthetic
// impacts and a disposable database only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/library/presentation/widgets/permanent_deletion/permanent_deletion_sheet.dart';

PermanentDeletionImpact impact({
  PermanentDeletionTarget target = const PermanentDeletionTarget.album('a1'),
  Set<PermanentDeletionBlocker> blockers = const {},
  Set<String> shared = const {},
}) => PermanentDeletionImpact(
  target: target,
  targetName: 'Nova',
  blockers: blockers,
  songIds: const {'s1', 's2', 's3'},
  albumIds: const {'a1'},
  editionIds: const {'e1', 'e2'},
  artistIds: const {},
  sharedRecordingIds: shared,
  songsKeptLosingListing: const {},
  collaborationSongIdsKept: const {},
  creditLinksRemoved: 0,
  playbackSessionIds: const {'p1', 'p2', 'p3', 'p4'},
  qualifiedPlayIds: const {'q1', 'q2', 'q3'},
  listeningSegmentCount: 4,
  listenedMs: 3 * 60 * 60000 + 25 * 60000,
  historyRowsRepointed: 0,
  chartEntryIds: const {'c1', 'c2'},
  affectedChartWeeks: const {
    'songs:2026-10-04T04:00:00.000Z',
    'albums:2026-10-04T04:00:00.000Z',
  },
  momentIdsAboutTarget: const {'m1', 'm2'},
  momentIdsMentioningTarget: const {'m3'},
  playlists: const [
    PlaylistDeletionImpact(
      playlistId: 'pl',
      playlistName: 'Road',
      itemsRemoved: 2,
    ),
  ],
  mediaFileBindingCount: 3,
  lyricsCount: 0,
  metadataFieldStateCount: 9,
  artworkCropCount: 0,
  otherArtistsLosingProjectGrouping: const {},
  pendingCloudWriteCount: 0,
);

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  late List<PermanentDeletionOptions> previews;
  late List<PermanentDeletionImpact> deletions;
  late bool? result;

  setUp(() {
    previews = [];
    deletions = [];
    result = null;
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    PermanentDeletionImpact Function(PermanentDeletionOptions)? load,
    Future<PermanentDeletionImpact> Function(
      PermanentDeletionImpact,
      PermanentDeletionOptions,
    )?
    delete,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    double textScale = 1,
    String name = 'Nova',
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(spec),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey<String>('open'),
                onPressed: () async {
                  result = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => PermanentDeletionSheet(
                      target: const PermanentDeletionTarget.album('a1'),
                      name: name,
                      loadPreview: (options) async {
                        previews.add(options);
                        return (load ?? (_) => impact())(options);
                      },
                      delete:
                          delete ??
                          (i, o) async {
                            deletions.add(i);
                            return i;
                          },
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(_key('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows exactly what goes and what stays', (tester) async {
    await pumpSheet(tester);

    expect(_key('permanent-deletion-name'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('Release · a1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // releases
    expect(find.text('2'), findsOneWidget); // editions
    expect(find.text('3'), findsOneWidget); // songs
    expect(
      find.text('3 streams · 4 listening sessions · 3 hours 25 minutes'),
      findsOneWidget,
    );
    expect(find.textContaining('2 chart entries removed'), findsOneWidget);
    expect(find.textContaining('2 weeks recalculated'), findsOneWidget);
    expect(find.text('3 stories'), findsOneWidget);
    expect(find.text('2 entries from Road'), findsOneWidget);
    expect(find.textContaining('Your audio files stay'), findsOneWidget);
    expect(find.textContaining('can\'t be undone'), findsOneWidget);
    expect(find.textContaining('Undo'), findsNothing);
  });

  testWidgets('nothing is deleted without typing the exact name', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(_key('permanent-deletion-continue'));
    await tester.pumpAndSettle();
    expect(_key('permanent-deletion-confirm-dialog'), findsOneWidget);

    FilledButton confirm() =>
        tester.widget<FilledButton>(_key('permanent-deletion-confirm-delete'));
    expect(confirm().onPressed, isNull);
    await tester.enterText(_key('permanent-deletion-confirm-field'), 'nova');
    await tester.pump();
    expect(confirm().onPressed, isNull, reason: 'the exact name');

    // Cancelling deletes nothing and keeps the sheet open.
    await tester.tap(_key('permanent-deletion-confirm-cancel'));
    await tester.pumpAndSettle();
    expect(deletions, isEmpty);
    expect(_key('permanent-deletion-sheet'), findsOneWidget);

    await tester.tap(_key('permanent-deletion-continue'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('permanent-deletion-confirm-field'), 'Nova');
    await tester.pump();
    await tester.tap(_key('permanent-deletion-confirm-delete'));
    await tester.pumpAndSettle();

    expect(deletions, hasLength(1));
    expect(result, isTrue);
  });

  testWidgets('cancelling the sheet deletes nothing', (tester) async {
    await pumpSheet(tester);
    await tester.tap(_key('permanent-deletion-cancel'));
    await tester.pumpAndSettle();

    expect(deletions, isEmpty);
    expect(result, isFalse);
  });

  testWidgets('blocked while the cloud cannot keep the deletion', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      load: (_) =>
          impact(blockers: {PermanentDeletionBlocker.cloudDeletionUnavailable}),
    );

    expect(_key('permanent-deletion-cloud-unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(_key('permanent-deletion-continue'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('shared recordings need an explicit choice', (tester) async {
    await pumpSheet(
      tester,
      load: (options) => impact(
        target: const PermanentDeletionTarget.artist('nova'),
        shared: const {'guest'},
        blockers: options.includeSharedRecordings
            ? const {}
            : {PermanentDeletionBlocker.sharedRecordingsNotConfirmed},
      ),
    );

    expect(_key('permanent-deletion-shared'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(_key('permanent-deletion-continue'))
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(_key('permanent-deletion-include-shared'));
    await tester.pumpAndSettle();
    await tester.tap(_key('permanent-deletion-include-shared'));
    await tester.pumpAndSettle();

    expect(previews.last.includeSharedRecordings, isTrue);
    expect(
      tester
          .widget<FilledButton>(_key('permanent-deletion-continue'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a changed library reloads the preview; nothing is deleted', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      delete: (_, _) async => throw const StaleDeletionPreview(),
    );
    await tester.tap(_key('permanent-deletion-continue'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('permanent-deletion-confirm-field'), 'Nova');
    await tester.pump();
    await tester.tap(_key('permanent-deletion-confirm-delete'));
    await tester.pumpAndSettle();

    expect(_key('permanent-deletion-notice'), findsOneWidget);
    expect(previews, hasLength(2));
    expect(result, isNull, reason: 'the sheet stays open');
  });

  for (final id in SonusThemeId.values) {
    for (final (label, spec, scale) in [
      ('default', SonusAppearanceSpec(themeId: id), 1.0),
      (
        'high contrast, bold, low effects, reduced motion',
        SonusAppearanceSpec(
          themeId: id,
          highContrast: true,
          boldText: true,
          lowEffects: true,
          reduceMotion: true,
        ),
        1.0,
      ),
      ('large text', SonusAppearanceSpec(themeId: id), 2.0),
    ]) {
      testWidgets('lays out in ${id.name} ($label)', (tester) async {
        await pumpSheet(tester, spec: spec, textScale: scale);
        await tester.tap(_key('permanent-deletion-continue'));
        await tester.pumpAndSettle();
        expect(_key('permanent-deletion-confirm-dialog'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('deletes exactly the impact that was shown', (tester) async {
    final shown = impact();
    await pumpSheet(tester, load: (_) => shown);
    await tester.tap(_key('permanent-deletion-continue'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('permanent-deletion-confirm-field'), 'Nova');
    await tester.pump();
    await tester.tap(_key('permanent-deletion-confirm-delete'));
    await tester.pumpAndSettle();

    expect(deletions.single, same(shown));
  });
}
