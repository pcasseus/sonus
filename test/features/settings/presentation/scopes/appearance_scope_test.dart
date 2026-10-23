import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/application/services/appearance_schedule_resolver.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';
import 'package:sonus_next/features/settings/presentation/scopes/appearance_scope.dart';

import '../../application/services/appearance_test_time_zones.dart';

void main() {
  late DateTime clock;

  AppearanceController buildController() {
    final storage = <String, String>{};
    final controller = AppearanceController(
      store: AppearancePreferencesStore.forTesting(
        getString: (key) async => storage[key],
        setString: (key, value) async => storage[key] = value,
      ),
      resolver: const AppearanceScheduleResolver(
        timeZone: FixedTestZone(Duration.zero),
      ),
      now: () => clock,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() => clock = DateTime.utc(2026, 10, 23, 12));

  final durations = <Duration>[];

  Widget app({AppearanceController? controller}) {
    final builder = SonusThemedAppBuilder(
      builder: (context, theme, duration) {
        durations.add(duration);
        return MaterialApp(
          theme: theme,
          themeAnimationDuration: duration,
          home: const Scaffold(body: Text('content')),
        );
      },
    );

    return controller == null
        ? builder
        : AppearanceScope(controller: controller, child: builder);
  }

  Color background(WidgetTester tester) => Theme.of(
    tester.element(find.text('content')),
  ).extension<SonusColors>()!.background;

  setUp(durations.clear);

  testWidgets('without a scope the app uses Concrete & Spray', (tester) async {
    await tester.pumpWidget(app());

    expect(
      background(tester),
      SonusThemeCatalog.of(SonusThemeId.concreteSpray).palette.background,
    );
  });

  testWidgets('applies the controller theme, switching without animation '
      'on first load', (tester) async {
    final controller = buildController();
    await controller.selectTheme(SonusThemeId.daylight);
    await tester.pumpWidget(app(controller: controller));

    await controller.load();
    await tester.pump();

    expect(durations.last, Duration.zero);

    await controller.selectTheme(SonusThemeId.evergreen);
    await tester.pumpAndSettle();

    expect(durations.last, kThemeAnimationDuration);
    expect(
      background(tester),
      SonusThemeCatalog.of(SonusThemeId.evergreen).palette.background,
    );
  });

  testWidgets('reduced motion switches themes instantly', (tester) async {
    final controller = buildController();
    await controller.load();
    await controller.setReduceMotion(true);
    await tester.pumpWidget(app(controller: controller));

    await controller.selectTheme(SonusThemeId.kickflip);
    await tester.pump();

    expect(durations.last, Duration.zero);
    expect(
      background(tester),
      SonusThemeCatalog.of(SonusThemeId.kickflip).palette.background,
    );
  });

  testWidgets('re-evaluates the schedule when the app resumes', (tester) async {
    clock = DateTime.utc(2026, 10, 23, 18);
    final controller = buildController();
    await controller.load();
    await controller.updateSchedule(
      const AppearanceSchedule(
        enabled: true,
        dayTheme: SonusThemeId.daylight,
        nightTheme: SonusThemeId.afterHours,
      ),
    );
    await tester.pumpWidget(app(controller: controller));

    // The device slept through the transition; no timer ran meanwhile.
    clock = DateTime.utc(2026, 10, 23, 22);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(controller.resolved.phase, AppearancePhase.night);
    expect(
      background(tester),
      SonusThemeCatalog.of(SonusThemeId.afterHours).palette.background,
    );

    // Stop the scope's recheck timer before the test ends.
    await controller.updateSchedule(
      controller.preferences.schedule.copyWith(enabled: false),
    );
  });

  testWidgets('follows the device high-contrast and reduced-motion settings', (
    tester,
  ) async {
    final controller = buildController();
    await controller.load();
    await tester.pumpWidget(app(controller: controller));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true, reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    expect(controller.systemHighContrast, isTrue);
    expect(controller.systemReduceMotion, isTrue);
    expect(controller.spec.highContrast, isTrue);
    expect(controller.preferences.highContrast, isFalse);
  });

  testWidgets('does not dispose a controller it was given', (tester) async {
    final controller = buildController();
    await controller.load();
    await tester.pumpWidget(app(controller: controller));

    await tester.pumpWidget(const SizedBox());

    // A disposed ChangeNotifier would throw here.
    controller.addListener(() {});
    unawaited(controller.selectTheme(SonusThemeId.kickflip));
  });
}
