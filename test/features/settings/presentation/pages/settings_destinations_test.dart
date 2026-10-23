import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_preferences_controller.dart';
import 'package:sonus_next/features/player/data/services/playback_preferences_store.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/application/controllers/metadata_intelligence_settings_controller.dart';
import 'package:sonus_next/features/settings/data/app_info_service.dart';
import 'package:sonus_next/features/settings/domain/models/settings_data_coverage.dart';
import 'package:sonus_next/features/settings/presentation/pages/about_sonus_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/accessibility_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/account_cloud_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/data_privacy_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/library_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/listening_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/playback_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/settings_page.dart';
import 'package:sonus_next/features/settings/presentation/widgets/settings/settings_section.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

import '../../../../support/settings_test_fakes.dart';

ValueKey<String> _key(String value) => ValueKey<String>(value);

/// Everything the Settings pages read, wired with test doubles.
class _Harness {
  _Harness._({
    required this.appearance,
    required this.playback,
    required this.metadata,
    required this.library,
    required this.reviews,
  });

  final AppearanceController appearance;
  final PlaybackPreferencesController playback;
  final MetadataIntelligenceSettingsController metadata;
  final FakeLibrary? library;
  final FakeReviews reviews;

  static Future<_Harness> create({bool withLibrary = true}) async {
    SharedPreferences.setMockInitialValues({});

    final appearance = await loadedAppearanceController();
    final engine = FakeModeEngine();
    final storage = <String, String>{};
    final playback = PlaybackPreferencesController(
      store: PlaybackPreferencesStore.forTesting(
        getString: (key) async => storage[key],
        setString: (key, value) async => storage[key] = value,
      ),
      coordinator: PlaybackCoordinator(engine: engine),
    );
    await playback.load();
    final metadata = MetadataIntelligenceSettingsController();
    await metadata.load();

    final harness = _Harness._(
      appearance: appearance,
      playback: playback,
      metadata: metadata,
      library: withLibrary
          ? FakeLibrary(
              tracks: [
                settingsTrack('ok'),
                settingsTrack('missing', available: false),
                settingsTrack('blocked', blocked: true),
              ],
              albumCount: 2,
              artistCount: 3,
            )
          : null,
      reviews: FakeReviews(pending: 5),
    );

    addTearDown(appearance.dispose);
    addTearDown(playback.dispose);
    addTearDown(metadata.dispose);
    addTearDown(engine.dispose);
    return harness;
  }

  Widget app(
    Widget home, {
    SonusThemeId theme = SonusThemeId.concreteSpray,
    double textScale = 1,
    AccountController? account,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppearanceController>.value(value: appearance),
        ChangeNotifierProvider<PlaybackPreferencesController>.value(
          value: playback,
        ),
        ChangeNotifierProvider<MetadataIntelligenceSettingsController>.value(
          value: metadata,
        ),
        Provider<LibraryQueryRepository?>.value(value: library),
        Provider<ImportWorkflowService?>.value(
          value: library == null ? null : FakeImports(sourceCount: 2),
        ),
        Provider<ImportReviewService?>.value(
          value: library == null ? null : reviews,
        ),
        ChangeNotifierProvider<AccountController?>.value(value: account),
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
}

Future<void> _openFromLanding(WidgetTester tester, String key) async {
  final tile = find.byKey(_key(key));
  await tester.scrollUntilVisible(
    tile,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  group('landing page', () {
    testWidgets('groups every area into sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final harness = await _Harness.create();

      await tester.pumpWidget(
        harness.app(const Scaffold(body: SettingsPage())),
      );
      await tester.pumpAndSettle();

      for (final section in [
        'Account',
        'Experience',
        'Library',
        'Listening',
        'Data',
        'About',
      ]) {
        expect(
          tester.getSemantics(find.text(section)),
          matchesSemantics(label: section, isHeader: true),
          reason: section,
        );
      }
      for (final key in [
        'settings-account-cloud',
        'settings-appearance',
        'settings-accessibility',
        'settings-playback',
        'settings-library',
        'settings-metadata-intelligence',
        'settings-listening',
        'settings-backup-restore',
        'settings-data-privacy',
        'settings-about',
      ]) {
        expect(find.byKey(_key(key)), findsOneWidget, reason: key);
      }
      semantics.dispose();
    });

    testWidgets('summaries reflect the live preferences', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _Harness.create();

      await tester.pumpWidget(
        harness.app(const Scaffold(body: SettingsPage())),
      );
      await tester.pumpAndSettle();

      String summary(String key) =>
          tester.widget<Text>(find.byKey(_key(key))).data!;

      expect(
        summary('settings-appearance-subtitle'),
        'Concrete & Spray · Street Bold',
      );
      expect(
        summary('settings-metadata-intelligence-subtitle'),
        'On, with cover art suggestions.',
      );
      expect(
        summary('settings-accessibility-subtitle'),
        'Contrast, motion and visual effects.',
      );
      expect(
        summary('settings-playback-subtitle'),
        'Shuffle and repeat, and how playback behaves.',
      );

      await harness.appearance.setHighContrast(true);
      await harness.playback.setRememberShuffleAndRepeat(true);
      await harness.metadata.setOnlineMetadataLookupEnabled(false);
      await tester.pumpAndSettle();

      expect(summary('settings-accessibility-subtitle'), 'High contrast on');
      expect(
        summary('settings-playback-subtitle'),
        'Remembers shuffle and repeat.',
      );
      expect(
        summary('settings-metadata-intelligence-subtitle'),
        'Off. Metadata lookups stay offline.',
      );
    });

    testWidgets('every row opens its destination', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      stubAppInfoChannel(tester, null);
      final harness = await _Harness.create();

      for (final (row, page) in [
        ('settings-account-cloud', 'account-cloud-settings-page'),
        ('settings-appearance', 'appearance-settings-page'),
        ('settings-accessibility', 'accessibility-settings-page'),
        ('settings-playback', 'playback-settings-page'),
        ('settings-library', 'library-settings-page'),
        (
          'settings-metadata-intelligence',
          'metadata-intelligence-settings-page',
        ),
        ('settings-listening', 'listening-settings-page'),
        ('settings-backup-restore', 'recovery-unavailable'),
        ('settings-data-privacy', 'data-privacy-page'),
        ('settings-about', 'about-sonus-page'),
      ]) {
        await tester.pumpWidget(
          harness.app(const Scaffold(body: SettingsPage())),
        );
        await tester.pumpAndSettle();

        await _openFromLanding(tester, row);

        expect(find.byKey(_key(page)), findsOneWidget, reason: row);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    for (final themeId in SonusThemeId.values) {
      testWidgets('lays out in ${themeId.label} at 320dp with 2x text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harness = await _Harness.create();

        await tester.pumpWidget(
          harness.app(
            const Scaffold(body: SettingsPage()),
            theme: themeId,
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('account summary', () {
    AccountController account({bool signedIn = true}) => AccountController(
      repository: FakeSettingsAccountRepository(
        currentUser: signedIn ? settingsTestUser : null,
      ),
    );

    SyncRunResult success() => SyncRunResult(
      userId: 'user-1',
      startedAt: DateTime.utc(2026, 10, 6, 18),
      completedAt: DateTime.utc(2026, 10, 6, 18, 1),
      claimedUnownedCount: 0,
      pendingBeforePush: 0,
      pulledRecordCount: 0,
      pendingAfterSync: 0,
    );

    test('explains unconfigured and signed-out states', () {
      expect(accountCloudSummary(null, null), (
        'Sign-in is not configured for this build.',
        false,
      ));
      expect(accountCloudSummary(account(signedIn: false), null), (
        'Not signed in. Sonus works fully offline.',
        false,
      ));
    });

    test('shows the signed-in name and sync state', () async {
      final sync = SyncController.forTesting(
        synchronize: (_) async => success(),
      );

      expect(accountCloudSummary(account(), sync), (
        'Person Example · Ready to sync',
        false,
      ));

      await sync.synchronize('user-1');
      expect(accountCloudSummary(account(), sync), (
        'Person Example · Up to date',
        false,
      ));
    });

    test('flags conflicts, recovery holds and failures', () async {
      final conflict = SyncController.forTesting(
        synchronize: (_) async => throw const LocalAccountBindingConflict(
          boundUserId: 'user-old',
          requestedUserId: 'user-1',
        ),
      );
      await conflict.synchronize('user-1');
      expect(accountCloudSummary(account(), conflict), (
        'This library is linked to a different account.',
        true,
      ));

      final held = SyncController.forTesting(
        synchronize: (_) async =>
            throw const SyncHeldForRecovery(SyncHoldReason.assessmentRequired),
      );
      await held.synchronize('user-1');
      expect(accountCloudSummary(account(), held), (
        'Cloud sync is paused for recovery review.',
        true,
      ));

      final failing = SyncController.forTesting(
        synchronize: (_) async => throw StateError('network'),
      );
      await failing.synchronize('user-1');
      expect(accountCloudSummary(account(), failing), (
        'Sync could not finish. Sonus will try again.',
        true,
      ));
    });
  });

  group('Playback', () {
    testWidgets('remembering shuffle and repeat is a real, saved choice', (
      tester,
    ) async {
      final harness = await _Harness.create();
      await tester.pumpWidget(harness.app(const PlaybackSettingsPage()));
      await tester.pumpAndSettle();

      expect(
        find.text('Off: every launch starts with shuffle and repeat off.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(_key('playback-remember-shuffle-repeat')));
      await tester.pumpAndSettle();

      expect(harness.playback.preferences.rememberShuffleAndRepeat, isTrue);
      expect(find.text('Saved: shuffle off, repeat off.'), findsOneWidget);
    });

    testWidgets('offers no controls the player cannot honour', (tester) async {
      final harness = await _Harness.create();
      await tester.pumpWidget(harness.app(const PlaybackSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsOneWidget);
      for (final missing in [
        'Equalizer',
        'Crossfade',
        'Gapless',
        'ReplayGain',
        'Normalization',
      ]) {
        expect(find.textContaining(missing), findsNothing, reason: missing);
      }
    });

    testWidgets('explains when playback settings are unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PlaybackSettingsPage()));

      expect(find.byKey(_key('playback-settings-unavailable')), findsOneWidget);
    });
  });

  group('Library & Imports', () {
    testWidgets('summarises the library and links to every tool', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const LibrarySettingsPage()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(_key('library-settings-counts'))).data,
        '3 songs · 2 albums · 3 artists',
      );
      expect(find.text('2 music folders'), findsOneWidget);
      expect(find.text('5 songs need review.'), findsOneWidget);
      expect(find.text('1 song cannot be played.'), findsOneWidget);
      expect(find.text('1 song excluded from playback.'), findsOneWidget);
    });

    testWidgets('lists unavailable songs read-only', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const LibrarySettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_key('library-settings-unavailable-songs')));
      await tester.pumpAndSettle();

      expect(find.byKey(_key('unavailable-songs-page')), findsOneWidget);
      expect(find.byKey(_key('unavailable-song-missing')), findsOneWidget);
      expect(find.byKey(_key('unavailable-song-ok')), findsNothing);
      expect(find.text('1 unavailable song'), findsOneWidget);
    });

    testWidgets('keeps its links while the library is still opening', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _Harness.create(withLibrary: false);

      await tester.pumpWidget(harness.app(const LibrarySettingsPage()));
      await tester.pumpAndSettle();

      expect(find.byKey(_key('library-settings-unavailable')), findsOneWidget);
      expect(find.byKey(_key('settings-blacklisted-songs')), findsOneWidget);
      expect(find.byKey(_key('library-settings-imports')), findsOneWidget);
      expect(
        tester
            .widget<SettingsNavTile>(
              find.byKey(_key('library-settings-review')),
            )
            .onTap,
        isNull,
      );
    });

    testWidgets('a failed summary can be retried', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _Harness.create();
      harness.library!.fail = true;

      await tester.pumpWidget(harness.app(const LibrarySettingsPage()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_key('library-settings-summary-error')),
        findsOneWidget,
      );

      harness.library!.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(_key('library-settings-counts')), findsOneWidget);
    });
  });

  group('Listening & Charts', () {
    testWidgets('links to history, insights and charts', (tester) async {
      final harness = await _Harness.create();
      await tester.pumpWidget(harness.app(const ListeningSettingsPage()));
      await tester.pumpAndSettle();

      for (final key in [
        'settings-listening-history',
        'settings-monthly-insights',
        'settings-year-in-sonus',
        'settings-personal-charts',
      ]) {
        expect(find.byKey(_key(key)), findsOneWidget, reason: key);
      }
      expect(find.textContaining('cannot be edited'), findsOneWidget);
    });
  });

  group('Your data & privacy', () {
    testWidgets('lists exactly what backups include and leave out', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const DataPrivacyPage()));
      await tester.pumpAndSettle();

      final included = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(_key('data-privacy-in-backups')),
                  matching: find.byType(Text),
                )
                .last,
          )
          .data!;
      for (final item in SettingsDataCoverage.inBackups) {
        expect(included, contains(item));
      }
      expect(
        find.descendant(
          of: find.byKey(_key('data-privacy-not-in-backups')),
          matching: find.textContaining('Audio files'),
        ),
        findsOneWidget,
      );
    });
  });

  group('About Sonus', () {
    testWidgets('shows the installed version and schema', (tester) async {
      stubAppInfoChannel(tester, {'versionName': '1.0.0', 'buildNumber': '1'});
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const AboutSonusPage()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(_key('about-version'))).data,
        '1.0.0 (build 1)',
      );
      expect(
        tester.widget<Text>(find.byKey(_key('about-database-version'))).data,
        'Schema version ${AppDatabase.databaseVersion}',
      );
      expect(find.byKey(_key('about-sonus-mark')), findsOneWidget);
    });

    testWidgets('says the version is unavailable rather than guessing', (
      tester,
    ) async {
      stubAppInfoChannel(tester, null);
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const AboutSonusPage()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(_key('about-version'))).data,
        'Unavailable',
      );
    });

    testWidgets('opens the open-source licenses', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      stubAppInfoChannel(tester, null);
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const AboutSonusPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_key('about-licenses')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  group('Accessibility', () {
    testWidgets('uses the same appearance preferences', (tester) async {
      final harness = await _Harness.create();

      await tester.pumpWidget(harness.app(const AccessibilitySettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_key('appearance-reduce-motion')));
      await tester.pumpAndSettle();

      expect(harness.appearance.preferences.reduceMotion, isTrue);
      expect(harness.appearance.spec.reduceMotion, isTrue);
    });

    testWidgets('explains when accessibility settings are unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: AccessibilitySettingsPage()),
      );

      expect(find.byKey(_key('accessibility-unavailable')), findsOneWidget);
    });
  });

  testWidgets('every detail page lays out at 320dp with 2x text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    stubAppInfoChannel(tester, {'versionName': '1.0.0', 'buildNumber': '1'});
    final harness = await _Harness.create();

    for (final page in const <Widget>[
      AccountCloudSettingsPage(),
      AccessibilitySettingsPage(),
      PlaybackSettingsPage(),
      LibrarySettingsPage(),
      ListeningSettingsPage(),
      DataPrivacyPage(),
      AboutSonusPage(),
    ]) {
      await tester.pumpWidget(harness.app(page, textScale: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
  });

  testWidgets('the app-info service reports a malformed reply as unknown', (
    tester,
  ) async {
    stubAppInfoChannel(tester, {'versionName': 1});

    expect(await const AppInfoService().load(), isNull);
  });
}
