import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_segmented_selector.dart';
import 'package:sonus_next/features/analytics/application/services/listening_history_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/listening_history_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/listening_history_page.dart';
import 'package:sonus_next/features/analytics/presentation/pages/listening_insights_page.dart';

// SN-48K1 K1-6: Listening History and the Insights hub in the Sonus theme.
void main() {
  group('Listening History', () {
    Future<ListeningHistoryController> pump(
      WidgetTester tester, {
      ThemeData? theme,
      Size size = const Size(411, 1600),
      double textScale = 1,
      int sessions = 3,
      int pageSize = 50,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final controller = ListeningHistoryController(
        service: ListeningHistoryService(
          playbackSessions: _Sessions([
            for (var i = 0; i < sessions; i++)
              _session('s$i', DateTime.utc(2026, 10, 20, 12, i)),
          ]),
          qualifiedPlays: _QualifiedPlays(),
        ),
        pageSize: pageSize,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? SonusThemeFactory.build(const SonusAppearanceSpec()),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: ListeningHistoryPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      return controller;
    }

    testWidgets('entries sit on the theme surface with tabular details', (
      tester,
    ) async {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
      final colors = theme.extension<SonusColors>()!;
      await pump(tester, theme: theme);

      final entry = tester.widget<Container>(
        find.byKey(const ValueKey<String>('listening-history-entry-s0')),
      );
      expect((entry.decoration! as BoxDecoration).color, colors.surface);

      final duration = tester.widget<Text>(
        find.byKey(const ValueKey<String>('listening-history-duration-s0')),
      );
      expect(
        duration.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('qualification is shown in words, not colour alone', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Not qualified'), findsWidgets);
    });

    testWidgets('Load more is still offered when another page exists', (
      tester,
    ) async {
      await pump(tester, sessions: 5, pageSize: 2);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('listening-history-load-more')),
        300,
      );
      expect(
        find.byKey(const ValueKey<String>('listening-history-load-more')),
        findsOneWidget,
      );
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 4000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Insights hub', () {
    Future<void> pumpHub(
      WidgetTester tester, {
      Size size = const Size(411, 900),
      double textScale = 1,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const Scaffold(body: ListeningInsightsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('uses the shared Sonus selector', (tester) async {
      await pumpHub(tester);

      expect(
        find.byKey(const ValueKey<String>('listening-insights-view-selector')),
        findsOneWidget,
      );
      expect(find.byType(SonusSegmentedSelector<dynamic>), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString().startsWith(
            'SonusSegmentedSelector',
          ),
        ),
        findsOneWidget,
      );
      // The selected segment is marked with a checkmark, not colour alone.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('fits 320dp at 2x text, dropping decorative icons', (
      tester,
    ) async {
      await pumpHub(tester, size: const Size(320, 900), textScale: 2);

      // Scoped to the selector: the Monthly view's own message reuses the
      // same icon.
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('listening-insights-view-selector'),
          ),
          matching: find.byIcon(Icons.query_stats_rounded),
        ),
        findsNothing,
      );
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

PlaybackSession _session(String id, DateTime startedAt) {
  return PlaybackSession(
    id: id,
    songId: 'song_$id',
    artistId: 'artist_$id',
    albumId: 'album_$id',
    albumEditionId: 'edition_$id',
    songTitle: 'A long song title for $id that needs room',
    artistName: 'Artist $id',
    albumTitle: 'Album $id',
    albumEditionTitle: 'Deluxe',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 2)),
    listenedDuration: const Duration(seconds: 80),
    trackDuration: const Duration(minutes: 3),
    finalPosition: const Duration(seconds: 80),
    endReason: PlaybackSessionEndReason.skipped,
    sourceContext: 'library',
    createdAt: startedAt,
    updatedAt: startedAt.add(const Duration(minutes: 2)),
  );
}

/// Sessions served newest first, as the real repository pages them.
class _Sessions implements PlaybackSessionRepository {
  _Sessions(this.sessions);

  final List<PlaybackSession> sessions;

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final sorted = [...sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final remaining = before == null
        ? sorted
        : sorted.where((s) => s.startedAt.isBefore(before.startedAt)).toList();

    return remaining.take(limit).toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No session in these fixtures qualified.
class _QualifiedPlays implements QualifiedPlayRepository {
  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
