import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/shell/application/controllers/app_shell_controller.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';

void main() {
  group('AppShellController', () {
    test('starts on home by default', () {
      final controller = AppShellController();

      expect(controller.currentDestination, AppDestination.home);
      expect(controller.currentIndex, 0);
    });

    test('can start on another destination', () {
      final controller = AppShellController(
        initialDestination: AppDestination.library,
      );

      expect(controller.currentDestination, AppDestination.library);
      expect(controller.currentIndex, AppDestination.library.index);
    });

    test('selectDestination changes the active destination', () {
      final controller = AppShellController();

      controller.selectDestination(AppDestination.tracks);

      expect(controller.currentDestination, AppDestination.tracks);
      expect(controller.currentIndex, AppDestination.tracks.index);
    });

    test('selectIndex changes the active destination', () {
      final controller = AppShellController();

      controller.selectIndex(AppDestination.settings.index);

      expect(controller.currentDestination, AppDestination.settings);
      expect(controller.currentIndex, AppDestination.settings.index);
    });

    test('notifies listeners when the destination changes', () {
      final controller = AppShellController();
      var notificationCount = 0;

      controller.addListener(() {
        notificationCount++;
      });

      controller.selectDestination(AppDestination.hot100);

      expect(notificationCount, 1);
    });

    test('does not notify when selecting the current destination', () {
      final controller = AppShellController();
      var notificationCount = 0;

      controller.addListener(() {
        notificationCount++;
      });

      controller.selectDestination(AppDestination.home);

      expect(notificationCount, 0);
    });

    test('rejects an index below the destination range', () {
      final controller = AppShellController();

      expect(() => controller.selectIndex(-1), throwsRangeError);
    });

    test('rejects an index above the destination range', () {
      final controller = AppShellController();

      expect(
        () => controller.selectIndex(AppDestination.values.length),
        throwsRangeError,
      );
    });
  });
}
