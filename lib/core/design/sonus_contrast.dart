import 'package:flutter/painting.dart';

/// WCAG 2 contrast arithmetic.
abstract final class SonusContrast {
  /// Contrast ratio between two opaque colours, from 1 to 21.
  static double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;

    return (lighter + 0.05) / (darker + 0.05);
  }
}
