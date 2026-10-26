import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/shell/presentation/widgets/sonus_system_bars.dart';

void main() {
  test('dark themes get light icons on clear, scrim-free bars', () {
    final style = SonusSystemBars.styleFor(Brightness.dark);

    expect(style.statusBarColor, Colors.transparent);
    expect(style.systemNavigationBarColor, Colors.transparent);
    expect(style.systemNavigationBarDividerColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    // No grey contrast panel drawn by Android over the navigation area.
    expect(style.systemNavigationBarContrastEnforced, isFalse);
    expect(style.systemStatusBarContrastEnforced, isFalse);
  });

  test('light themes get dark icons', () {
    final style = SonusSystemBars.styleFor(Brightness.light);

    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('the whole app is covered by the theme-aware style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        builder: (context, child) => SonusSystemBars(child: child!),
        home: const SizedBox.shrink(),
      ),
    );

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value, SonusSystemBars.styleFor(Brightness.light));
  });
}
