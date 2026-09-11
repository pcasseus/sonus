import 'package:flutter/foundation.dart';

import '../../domain/models/app_destination.dart';

class AppShellController extends ChangeNotifier {
  AppShellController({AppDestination initialDestination = AppDestination.home})
    : _currentDestination = initialDestination;

  AppDestination _currentDestination;

  AppDestination get currentDestination => _currentDestination;

  int get currentIndex => _currentDestination.index;

  void selectDestination(AppDestination destination) {
    if (_currentDestination == destination) {
      return;
    }

    _currentDestination = destination;
    notifyListeners();
  }

  void selectIndex(int index) {
    if (index < 0 || index >= AppDestination.values.length) {
      throw RangeError.range(
        index,
        0,
        AppDestination.values.length - 1,
        'index',
      );
    }

    selectDestination(AppDestination.values[index]);
  }
}
