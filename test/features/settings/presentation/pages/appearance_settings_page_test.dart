import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/sonus_typography.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/application/services/appearance_schedule_resolver.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';
import 'package:sonus_next/features/settings/presentation/pages/appearance_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/scopes/appearance_scope.dart';

import '../../application/services/appearance_test_time_zones.dart';

ValueKey<String> _key(String value) => ValueKey<String>(value);

void main() {
  late Map<String, String> storage;
  late bool failWrites;

  setUp(() {
    storage = {};
    failWrites = false;
  });

  Future<AppearanceController> pumpPage(
    WidgetTester tester, {
    Size size = const Size(420, 3200),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = AppearanceController(
      store: AppearancePreferencesStore.forTesting(
        getString: (key) async => storage[key],
        setString: (key, value) async {
          if (failWrites) throw StateError('disk full');
          storage[key] = value;
        },
      ),
      resolver: const AppearanceScheduleResolver(
        timeZone: FixedTestZone(Duration.zero),
      ),
      now: () => DateTime.utc(2026, 10, 23, 12),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceController>.value(
        value: controller,
        child: SonusThemedAppBuilder(
          builder: (context, theme, duration) => MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: textScale,
              maxScaleFactor: textScale,
              child: child!,
            ),
            home: const AppearanceSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return controller;
  }

  Map<String, Object?> stored(String key) =>
      jsonDecode(storage[key]!) as Map<String, Object?>;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('offers all nine themes with the active one selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester);

    for (final id in SonusThemeId.values) {
      final tile = find.byKey(_key('appearance-theme-${id.storageKey}'));

      expect(tile, findsOneWidget);
      expect(
        tester.getSemantics(tile),
        matchesSemantics(
          label: '${id.label} theme',
          hint: SonusThemeCatalog.of(id).identity,
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: id == SonusThemeId.concreteSpray,
          isInMutuallyExclusiveGroup: true,
        ),
        reason: id.label,
      );
    }

    semantics.dispose();
  });

  testWidgets('theme tiles in a row share one height', (tester) async {
    await pumpPage(tester);

    double heightOf(SonusThemeId id) => tester
        .getSize(find.byKey(_key('appearance-theme-${id.storageKey}')))
        .height;

    // "Concrete & Spray" wraps to two lines; its row-mates must match it.
    expect(
      heightOf(SonusThemeId.kickflip),
      heightOf(SonusThemeId.concreteSpray),
    );
    expect(
      heightOf(SonusThemeId.afterHours),
      heightOf(SonusThemeId.concreteSpray),
    );
  });

  testWidgets('choosing a theme restyles Sonus immediately and saves it', (
    tester,
  ) async {
    final controller = await pumpPage(tester);

    await tapVisible(tester, find.byKey(_key('appearance-theme-daylight')));

    final page = tester.element(find.byKey(_key('appearance-settings-page')));
    expect(
      Theme.of(page).extension<SonusColors>()!.background,
      SonusThemeCatalog.of(SonusThemeId.daylight).palette.background,
    );
    expect(controller.spec.themeId, SonusThemeId.daylight);
    expect(
      stored(AppearancePreferencesStore.preferencesKey)['theme'],
      'daylight',
    );
  });

  testWidgets('typography and decoration choices apply and persist', (
    tester,
  ) async {
    final controller = await pumpPage(tester);

    await tapVisible(
      tester,
      find.byKey(_key('appearance-typography-editorial')),
    );
    await tapVisible(tester, find.byKey(_key('appearance-decoration-off')));

    expect(controller.preferences.typography, SonusTypographyPreset.editorial);
    expect(controller.preferences.decoration, SonusDecorationIntensity.off);

    final preferences = stored(AppearancePreferencesStore.preferencesKey);
    expect(preferences['typography'], 'editorial');
    expect(preferences['decoration'], 'off');

    final chip = tester.widget<ChoiceChip>(
      find.byKey(_key('appearance-typography-editorial')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('accessibility switches apply and explain decoration limits', (
    tester,
  ) async {
    final controller = await pumpPage(tester);
    expect(find.byKey(_key('appearance-decoration-limited')), findsNothing);

    await tapVisible(tester, find.byKey(_key('appearance-high-contrast')));
    await tapVisible(tester, find.byKey(_key('appearance-reduce-motion')));
    await tapVisible(tester, find.byKey(_key('appearance-low-effects')));

    expect(controller.spec.highContrast, isTrue);
    expect(controller.spec.reduceMotion, isTrue);
    expect(controller.spec.lowEffects, isTrue);
    expect(find.byKey(_key('appearance-decoration-limited')), findsOneWidget);
    expect(stored(AppearancePreferencesStore.deviceKey)['lowEffects'], isTrue);
  });

  testWidgets('scheduling shows the active window and its themes', (
    tester,
  ) async {
    final controller = await pumpPage(tester);
    expect(find.byKey(_key('appearance-schedule-status')), findsNothing);

    await tapVisible(tester, find.byKey(_key('appearance-schedule-enabled')));

    expect(controller.preferences.schedule.enabled, isTrue);
    expect(controller.spec.themeId, SonusThemeId.daylight);
    expect(
      tester.widget<Text>(find.byKey(_key('appearance-schedule-status'))).data,
      'Day theme active. Concrete & Spray starts at 7:00 PM.',
    );

    await tapVisible(tester, find.byKey(_key('appearance-schedule-day-theme')));
    await tapVisible(
      tester,
      find.byKey(_key('appearance-schedule-choice-evergreen')),
    );

    expect(controller.preferences.schedule.dayTheme, SonusThemeId.evergreen);
    expect(controller.spec.themeId, SonusThemeId.evergreen);

    // Stop the real recheck timer before the test ends.
    await controller.updateSchedule(
      controller.preferences.schedule.copyWith(enabled: false),
    );
  });

  testWidgets('a theme chosen while scheduling overrides until the next '
      'transition and can be undone', (tester) async {
    final controller = await pumpPage(tester);
    await controller.updateSchedule(const AppearanceSchedule(enabled: true));
    await tester.pumpAndSettle();
    expect(find.byKey(_key('appearance-schedule-hint')), findsOneWidget);

    await tapVisible(tester, find.byKey(_key('appearance-theme-monochrome')));

    expect(controller.overrideActive, isTrue);
    expect(find.byKey(_key('appearance-override-notice')), findsOneWidget);
    expect(find.textContaining('Using Monochrome until 7:00 PM'), findsWidgets);

    await tapVisible(tester, find.byKey(_key('appearance-clear-override')));

    expect(controller.overrideActive, isFalse);
    expect(controller.spec.themeId, SonusThemeId.daylight);

    await controller.updateSchedule(
      controller.preferences.schedule.copyWith(enabled: false),
    );
  });

  testWidgets('previews switch between Home and an interactive Now Playing', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.byKey(_key('appearance-preview-home')), findsOneWidget);

    await tapVisible(tester, find.text('Now Playing'));

    expect(find.byKey(_key('appearance-preview-now-playing')), findsOneWidget);
    expect(find.byTooltip('Play preview'), findsOneWidget);

    await tapVisible(tester, find.byKey(_key('appearance-preview-play-pause')));
    expect(find.byTooltip('Pause preview'), findsOneWidget);

    final seek = find.byKey(_key('appearance-preview-seek'));
    await tester.tapAt(tester.getTopLeft(seek) + const Offset(30, 24));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(seek).value, lessThan(0.35));
  });

  testWidgets('reports a failed save without losing the change', (
    tester,
  ) async {
    final controller = await pumpPage(tester);
    failWrites = true;

    await tapVisible(tester, find.byKey(_key('appearance-theme-kickflip')));

    expect(controller.spec.themeId, SonusThemeId.kickflip);
    expect(find.byKey(_key('appearance-save-error')), findsOneWidget);
  });

  testWidgets('explains when appearance is unavailable', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppearanceSettingsPage()));

    expect(find.byKey(_key('appearance-unavailable')), findsOneWidget);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('lays out at 320px wide with ${textScale}x text', (
      tester,
    ) async {
      final controller = await pumpPage(
        tester,
        size: const Size(320, 6000),
        textScale: textScale,
      );
      await controller.updateSchedule(const AppearanceSchedule(enabled: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Now Playing'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Large text drops to a single column so names keep their words
      // whole; normal text keeps two columns at this width.
      final tileWidth = tester
          .getSize(find.byKey(_key('appearance-theme-monochrome')))
          .width;
      expect(tileWidth, textScale == 2 ? 320 - 40 : lessThan(160));

      for (final id in SonusThemeId.values) {
        final tile = tester.getRect(
          find.byKey(_key('appearance-theme-${id.storageKey}')),
        );
        expect(tile.right, lessThanOrEqualTo(320));
        expect(tile.height, greaterThanOrEqualTo(44));
      }

      await controller.updateSchedule(
        controller.preferences.schedule.copyWith(enabled: false),
      );
    });
  }

  testWidgets('every control is reachable by keyboard', (tester) async {
    final controller = await pumpPage(tester);

    // Tab until the Daylight tile has focus, then activate it.
    final daylight = find.byKey(_key('appearance-theme-daylight'));
    var focused = false;
    for (var i = 0; i < 40 && !focused; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      focused =
          focusedContext != null &&
          find
              .descendant(
                of: daylight,
                matching: find.byElementPredicate((e) => e == focusedContext),
              )
              .evaluate()
              .isNotEmpty;
    }

    expect(focused, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.spec.themeId, SonusThemeId.daylight);
  });
}
