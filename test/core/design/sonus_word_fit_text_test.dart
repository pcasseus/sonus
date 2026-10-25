import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/widgets/sonus_word_fit_text.dart';

// Regression (SN-48 QA): a single word wider than a 320dp card at 2x text,
// such as "Extraordinarily", broke mid-word.
void main() {
  Future<double?> fontSizeOf(
    WidgetTester tester,
    String text, {
    double width = 120,
    double scale = 2,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: width,
              child: SonusWordFitText(
                text,
                textKey: const ValueKey<String>('fit'),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
    return tester
        .widget<Text>(find.byKey(const ValueKey<String>('fit')))
        .style
        ?.fontSize;
  }

  testWidgets('a word wider than the space shrinks just enough', (
    tester,
  ) async {
    final size = await fontSizeOf(tester, 'Extraordinarily');

    expect(size, lessThan(20));
    expect(size, greaterThanOrEqualTo(12), reason: 'never below 60%');
  });

  testWidgets('ordinary titles keep their size and wrap between words', (
    tester,
  ) async {
    expect(await fontSizeOf(tester, 'A day in the life', scale: 1), 20);
    expect(await fontSizeOf(tester, 'Short', width: 400), 20);
  });
}
