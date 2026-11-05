// A2 Settings › Library & Imports › Artists: artists by state with what
// refers to them; removal only for removable artists, one at a time, after
// confirming, through the guarded service.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/artist_retirement_service.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_reference_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_reference_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_removal_message.dart';
import 'package:sonus_next/features/settings/presentation/pages/artists_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/library_settings_page.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../../../support/artist_reference_fixtures.dart';

ValueKey<String> _key(String value) => ValueKey<String>(value);

const _active = ArtistReferenceSummary(
  artistId: 'active',
  name: 'Active Artist',
  songs: 2,
  albums: 1,
  qualifiedPlays: 30,
);
const _retired = ArtistReferenceSummary(
  artistId: 'retired',
  name: 'Retired Artist',
  qualifiedPlays: 12,
  listeningSessions: 14,
  chartEntries: 5,
  chartWeeks: 3,
  moments: 4,
);
const _pending = ArtistReferenceSummary(
  artistId: 'pending',
  name: 'Pending Artist',
  pendingCloudWrites: 1,
);
const _free = ArtistReferenceSummary(artistId: 'free', name: 'Free Artist');

class _Summaries implements ArtistReferenceSummaryRepository {
  _Summaries(this.summaries);

  List<ArtistReferenceSummary> summaries;

  @override
  Future<List<ArtistReferenceSummary>> summarizeAll() async => summaries;

  @override
  Future<Set<String>> findRetiredArtistIds() async => {
    for (final s in summaries)
      if (s.state == ArtistLibraryState.retired) s.artistId,
  };
}

class _NoRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) => throw UnimplementedError();
}

class _Editing extends ArtistProfileEditingService {
  _Editing({this.onRemove}) : super(mutationRunner: _NoRunner());

  final Future<void> Function(String artistId)? onRemove;
  final removed = <String>[];

  @override
  Future<void> removeArtist({
    required String? userId,
    required String artistId,
  }) async {
    removed.add(artistId);
    await onRemove?.call(artistId);
  }
}

Widget _app(
  Widget home, {
  ArtistRetirementService? service,
  ArtistProfileEditingService? editing,
  double textScale = 1,
  SonusThemeId theme = SonusThemeId.concreteSpray,
}) {
  return MultiProvider(
    providers: [
      Provider<ArtistRetirementService?>.value(value: service),
      Provider<ArtistProfileEditingService?>.value(value: editing),
    ],
    child: MaterialApp(
      theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: theme)),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  late _Summaries summaries;
  late ArtistRetirementService service;
  late _Editing editing;
  late LibraryChangeSignal signal;

  setUp(() {
    summaries = _Summaries([_active, _retired, _pending, _free]);
    service = ArtistRetirementService(() async => summaries);
    editing = _Editing();
    signal = LibraryChangeSignal();
  });

  Future<void> pumpPage(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      _app(
        ArtistsSettingsPage(changes: signal),
        service: service,
        editing: editing,
        textScale: textScale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, ArtistLibraryState state) async {
    await tester.tap(find.byKey(_key('artists-filter-${state.name}')));
    await tester.pumpAndSettle();
  }

  String reason(WidgetTester tester, String id) =>
      tester.widget<Text>(find.byKey(_key('artists-reason-$id'))).data!;

  testWidgets('lists each state with counts and reasons', (tester) async {
    await pumpPage(tester);

    expect(find.text('In use (1)'), findsOneWidget);
    expect(find.text('Kept for history (1)'), findsOneWidget);
    expect(find.text('Waiting for sync (1)'), findsOneWidget);
    expect(find.text('Removable (1)'), findsOneWidget);

    // In use is shown first.
    expect(find.byKey(_key('artists-row-active')), findsOneWidget);
    expect(reason(tester, 'active'), '2 songs · 1 album · 30 plays');
    expect(find.byKey(_key('artists-row-retired')), findsNothing);

    await choose(tester, ArtistLibraryState.retired);
    expect(reason(tester, 'retired'), '12 plays · 3 chart weeks · 4 Moments');
    expect(
      tester.widget<Text>(find.byKey(_key('artists-state-explanation'))).data,
      contains('cannot be removed'),
    );

    await choose(tester, ArtistLibraryState.waitingForSync);
    expect(reason(tester, 'pending'), 'changes syncing');

    await choose(tester, ArtistLibraryState.removable);
    expect(reason(tester, 'free'), 'Nothing refers to this artist.');
  });

  testWidgets('Remove is offered only for removable artists', (tester) async {
    await pumpPage(tester);

    for (final state in ArtistLibraryState.values) {
      await choose(tester, state);
    }
    await choose(tester, ArtistLibraryState.active);
    expect(find.textContaining('Remove'), findsNothing);
    await choose(tester, ArtistLibraryState.retired);
    expect(find.byKey(_key('artists-remove-retired')), findsNothing);
    expect(find.textContaining('Remove'), findsNothing);
    await choose(tester, ArtistLibraryState.waitingForSync);
    expect(find.byKey(_key('artists-remove-pending')), findsNothing);
    await choose(tester, ArtistLibraryState.removable);
    expect(find.byKey(_key('artists-remove-free')), findsOneWidget);
    expect(find.text('Remove all'), findsNothing);
  });

  testWidgets('waiting for sync is hidden when no artist waits', (
    tester,
  ) async {
    summaries.summaries = [_active, _free];
    await pumpPage(tester);

    expect(find.byKey(_key('artists-filter-waitingForSync')), findsNothing);
  });

  testWidgets('removal needs confirmation; cancel changes nothing', (
    tester,
  ) async {
    await pumpPage(tester);
    await choose(tester, ArtistLibraryState.removable);

    await tester.tap(find.byKey(_key('artists-remove-free')));
    await tester.pumpAndSettle();

    expect(find.byKey(_key('artists-remove-dialog')), findsOneWidget);
    expect(find.text('Remove Free Artist?'), findsOneWidget);
    expect(editing.removed, isEmpty);

    await tester.tap(find.byKey(_key('artists-remove-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(_key('artists-remove-dialog')), findsNothing);
    expect(editing.removed, isEmpty);
    expect(find.byKey(_key('artists-row-free')), findsOneWidget);
  });

  testWidgets('confirmed removal goes through the service and reloads', (
    tester,
  ) async {
    editing = _Editing(
      onRemove: (id) async {
        summaries.summaries = [
          for (final s in summaries.summaries)
            if (s.artistId != id) s,
        ];
      },
    );
    await pumpPage(tester);
    await choose(tester, ArtistLibraryState.removable);

    await tester.tap(find.byKey(_key('artists-remove-free')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_key('artists-remove-confirm')));
    await tester.pumpAndSettle();

    expect(editing.removed, ['free']);
    expect(find.byKey(_key('artists-removed-message')), findsOneWidget);
    expect(find.byKey(_key('artists-row-free')), findsNothing);
    expect(find.text('Removable (0)'), findsOneWidget);
    expect(find.byKey(_key('artists-empty')), findsOneWidget);
  });

  testWidgets('a refused removal explains why and keeps the artist', (
    tester,
  ) async {
    editing = _Editing(
      onRemove: (_) async => throw const ArtistStillReferencedException({
        ArtistReference.listeningHistory,
      }),
    );
    await pumpPage(tester);
    await choose(tester, ArtistLibraryState.removable);

    await tester.tap(find.byKey(_key('artists-remove-free')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_key('artists-remove-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(_key('artists-remove-referenced-message')),
      findsOneWidget,
    );
    expect(
      find.text(
        artistRemovalBlockedMessage({ArtistReference.listeningHistory}),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_key('artists-row-free')), findsOneWidget);
  });

  testWidgets('a kept artist explains why it cannot be removed', (
    tester,
  ) async {
    await pumpPage(tester);
    await choose(tester, ArtistLibraryState.retired);

    await tester.tap(find.byKey(_key('artists-row-retired')));
    await tester.pumpAndSettle();

    expect(find.byKey(_key('artists-kept-dialog')), findsOneWidget);
    expect(
      find.textContaining(
        'Sonus keeps this artist because it still has listening history, '
        'chart history and Moments.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('refreshes after a library change', (tester) async {
    await pumpPage(tester);
    expect(find.text('In use (1)'), findsOneWidget);

    summaries.summaries = [
      _active,
      const ArtistReferenceSummary(
        artistId: 'new',
        name: 'New Artist',
        songs: 1,
      ),
    ];
    signal.notify(LibraryChangeKind.importCompleted);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('In use (2)'), findsOneWidget);
    expect(find.byKey(_key('artists-row-new')), findsOneWidget);
  });

  testWidgets('says so while the library is still opening', (tester) async {
    await tester.pumpWidget(_app(const ArtistsSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(_key('artists-unavailable')), findsOneWidget);
  });

  testWidgets('lays out at 320dp with 2x text in every state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(tester, textScale: 2);

    for (final state in ArtistLibraryState.values) {
      final chip = find.byKey(_key('artists-filter-${state.name}'));
      await tester.scrollUntilVisible(
        chip,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: state.name);
    }

    final remove = find.byKey(_key('artists-remove-free'));
    await tester.scrollUntilVisible(
      remove,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library & Imports links to the Artists page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(const LibrarySettingsPage(), service: service, editing: editing),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_key('library-settings-artists')));
    await tester.pumpAndSettle();

    expect(find.byKey(_key('artists-settings-page')), findsOneWidget);
    expect(find.byKey(_key('artists-row-active')), findsOneWidget);
  });

  group('with a real library', () {
    setUpAll(sqfliteFfiInit);

    testWidgets('removes a removable artist through the guard; kept '
        'artists and their history stay', (tester) async {
      late AppDatabase appDatabase;
      late ArtistReferenceFixtures fixtures;
      late Map<String, int> historyBefore;

      await tester.runAsync(() async {
        appDatabase = AppDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        );
        final db = await appDatabase.database;
        fixtures = ArtistReferenceFixtures(db);
        await fixtures.artist('kept', 'Kept Artist');
        await fixtures.play('kept');
        await fixtures.chartEntry('kept');
        await fixtures.moment(entityArtistId: 'kept');
        await fixtures.artist('free', 'Free Artist');
        historyBefore = await fixtures.referenceRowCounts();
      });
      addTearDown(() => tester.runAsync(appDatabase.close));

      final realService = ArtistRetirementService(
        () async => SqliteArtistReferenceRepository(await appDatabase.database),
      );
      final realEditing = ArtistProfileEditingService(
        mutationRunner: SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          changes: LibraryChangeSignal(),
        ),
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _app(
            ArtistsSettingsPage(changes: signal),
            service: realService,
            editing: realEditing,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      await choose(tester, ArtistLibraryState.removable);
      expect(find.byKey(_key('artists-remove-kept')), findsNothing);
      await tester.tap(find.byKey(_key('artists-remove-free')));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(_key('artists-remove-confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // Real database work finishes in real time; frames are pumped by
      // hand, since the reload's progress bar never settles meanwhile.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(_key('artists-removed-message')), findsOneWidget);
      expect(find.byKey(_key('artists-row-free')), findsNothing);

      await tester.runAsync(() async {
        final db = await appDatabase.database;
        expect(await ArtistDao(db).findById('free'), isNull);
        expect(await ArtistDao(db).findById('kept'), isNotNull);
        final after = await fixtures.referenceRowCounts();
        expect(after['artists'], historyBefore['artists']! - 1);
        expect(
          {...after}..remove('artists'),
          {...historyBefore}..remove('artists'),
        );
      });
    });
  });
}
