// BUG-10: fills the release date editor (year, optional month and day)
// the way a person does, for tests that save a date.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enters [iso] (`2026`, `2026-04` or `2026-04-17`) into the open release
/// date editor without saving it. Parts left out are set to "Unknown".
Future<void> enterReleaseDate(WidgetTester tester, String iso) async {
  final parts = iso.split('-');
  await tester.enterText(
    find.byKey(const ValueKey<String>('release-date-year-field')),
    parts[0],
  );
  await tester.pump();
  await chooseReleaseDateMonth(
    tester,
    parts.length > 1 ? int.parse(parts[1]) : null,
  );
  if (parts.length > 2) {
    await chooseReleaseDateDay(tester, int.parse(parts[2]));
  }
}

/// Picks [month] (1-12), or "Unknown" when null, in the month field.
Future<void> chooseReleaseDateMonth(WidgetTester tester, int? month) => _choose(
  tester,
  find.byKey(const ValueKey<String>('release-date-month')),
  'release-date-month-item-${month ?? 'none'}',
);

/// Picks [day], or "Unknown" when null, in the day field.
Future<void> chooseReleaseDateDay(WidgetTester tester, int? day) => _choose(
  tester,
  find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'release-date-day-',
        ) &&
        widget is DropdownButtonFormField,
  ),
  'release-date-day-item-${day ?? 'none'}',
);

Future<void> _choose(WidgetTester tester, Finder field, String item) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  // Long menus build only what is on screen, and open at the chosen
  // option: start from the top, then scroll down to the option.
  final menu = find.byType(Scrollable).last;
  await tester.fling(menu, const Offset(0, 3000), 6000);
  await tester.pumpAndSettle();
  final inMenu = find.descendant(
    of: menu,
    matching: find.byKey(ValueKey<String>(item)),
  );
  for (var step = 0; inMenu.evaluate().isEmpty; step++) {
    if (step == 40) fail('The option $item never appeared in the menu.');
    await tester.drag(menu, const Offset(0, -96));
    await tester.pumpAndSettle();
  }
  // The option's label: the item itself is wider than what it hit-tests.
  final option = find.descendant(of: inMenu, matching: find.byType(Text)).first;
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}
