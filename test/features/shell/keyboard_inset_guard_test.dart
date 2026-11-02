// SN-50 device QA: typing in a popup, leaving Sonus and coming back must
// not leave an empty gap where the keyboard was.
//
// The device sequence is reproduced with the test window: a field is
// focused and the keyboard's inset reported; Sonus goes to the background
// (inactive, hidden, paused) and returns (hidden, inactive, resumed) while
// the inset is still reported, as the device does when the keyboard does
// not come back. Without the guard the restored field asks for the
// keyboard again and the modal stays lifted by the stale inset.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/shell/presentation/widgets/keyboard_inset_guard.dart';

const _keyboard = 300.0;

Future<void> _background(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

Future<void> _resume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void _keyboardShown(WidgetTester tester, bool shown) {
  tester.view.viewInsets = shown
      ? FakeViewPadding(bottom: _keyboard * tester.view.devicePixelRatio)
      : FakeViewPadding.zero;
}

/// Lays out like a Sonus sheet: padded by the keyboard's inset.
Future<void> _openSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => Padding(
    key: const ValueKey('sheet-body'),
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('New playlist'),
        TextField(key: ValueKey('field')),
      ],
    ),
  ),
);

Future<void> _openDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const AlertDialog(
    title: Text('Rename'),
    content: TextField(key: ValueKey('field')),
  ),
);

Future<void> _openPage(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (context) => const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: TextField(key: ValueKey('field')),
      ),
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 860),
  double textScale = 1,
  bool guarded = true,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, navigator) {
        final child = MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: navigator!,
        );
        return guarded ? KeyboardInsetGuard(child: child) : child;
      },
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => _openSheet(context),
                child: const Text('sheet'),
              ),
              TextButton(
                onPressed: () => _openDialog(context),
                child: const Text('dialog'),
              ),
              TextButton(
                onPressed: () => _openPage(context),
                child: const Text('page'),
              ),
              const Expanded(child: _InsetProbe()),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What the app's pages read as the keyboard's inset.
class _InsetProbe extends StatelessWidget {
  const _InsetProbe();

  @override
  Widget build(BuildContext context) =>
      Text('inset ${MediaQuery.viewInsetsOf(context).bottom.round()}');
}

Future<void> _typeInto(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const ValueKey('field')));
  _keyboardShown(tester, true);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('field')), text);
  await tester.pump();
}

bool _fieldFocused(WidgetTester tester) {
  final state = tester.state<EditableTextState>(find.byType(EditableText));
  return state.widget.focusNode.hasFocus;
}

double _gapUnder(WidgetTester tester, Finder finder) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio -
    tester.getBottomLeft(finder).dy;

void main() {
  group('keyboard inset guard', () {
    testWidgets('reproduces the gap without the guard', (tester) async {
      await _pump(tester, guarded: false);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Road trip');
      await _background(tester);
      await _resume(tester);

      // The field is focused again and the sheet still stands on the
      // keyboard's reported space, though no keyboard came back.
      expect(_fieldFocused(tester), isTrue);
      expect(_gapUnder(tester, find.text('New playlist')), greaterThan(300));
    });

    testWidgets('a sheet drops back down after Sonus returns', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Road trip');
      final lifted = _gapUnder(tester, find.byKey(const ValueKey('field')));
      expect(lifted, greaterThanOrEqualTo(_keyboard));

      await _background(tester);
      await _resume(tester);

      expect(_fieldFocused(tester), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        lessThan(_keyboard),
      );
      // Nothing typed is lost.
      expect(find.text('Road trip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('returning with the keyboard already hidden', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Gym');
      await _background(tester);
      _keyboardShown(tester, false);
      await _resume(tester);

      expect(_fieldFocused(tester), isFalse);
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        lessThan(_keyboard),
      );
    });

    testWidgets('typing again opens the keyboard with its space', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Gym');
      await _background(tester);
      _keyboardShown(tester, false);
      await _resume(tester);

      await tester.tap(find.byKey(const ValueKey('field')));
      _keyboardShown(tester, true);
      await tester.pumpAndSettle();
      expect(_fieldFocused(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        greaterThanOrEqualTo(_keyboard),
      );

      // Closing it normally takes the space away.
      FocusManager.instance.primaryFocus?.unfocus();
      _keyboardShown(tester, false);
      await tester.pumpAndSettle();
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        lessThan(_keyboard),
      );
    });

    testWidgets('dismissing and reopening the sheet', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Gym');
      await _background(tester);
      await _resume(tester);

      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(find.text('New playlist'), findsNothing);
      // A stale inset reported with no field open reserves nothing.
      expect(find.text('inset 0'), findsOneWidget);

      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        lessThan(_keyboard),
      );
      await _typeInto(tester, 'Again');
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        greaterThanOrEqualTo(_keyboard),
      );
    });

    testWidgets('a dialog with a text field', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('dialog'));
      await tester.pumpAndSettle();
      final resting = tester.getCenter(find.byKey(const ValueKey('field'))).dy;
      await _typeInto(tester, 'Night drive');
      expect(
        tester.getCenter(find.byKey(const ValueKey('field'))).dy,
        lessThan(resting),
      );

      await _background(tester);
      await _resume(tester);

      expect(_fieldFocused(tester), isFalse);
      expect(tester.getCenter(find.byKey(const ValueKey('field'))).dy, resting);
      expect(find.text('Night drive'), findsOneWidget);
    });

    testWidgets('a full page with a text field', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('page'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Search');
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        greaterThanOrEqualTo(_keyboard),
      );

      await _background(tester);
      await _resume(tester);

      expect(_fieldFocused(tester), isFalse);
      expect(_gapUnder(tester, find.byKey(const ValueKey('field'))), 0);
    });

    testWidgets('a brief interruption keeps the field and keyboard', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'Gym');

      // The notification shade: inactive, then back, never hidden.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        greaterThanOrEqualTo(_keyboard),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(_fieldFocused(tester), isTrue);
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        greaterThanOrEqualTo(_keyboard),
      );
    });

    testWidgets('narrow screen with large text', (tester) async {
      await _pump(tester, size: const Size(320, 640), textScale: 2);
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      await _typeInto(tester, 'A long playlist name');
      await _background(tester);
      await _resume(tester);

      expect(_fieldFocused(tester), isFalse);
      expect(
        _gapUnder(tester, find.byKey(const ValueKey('field'))),
        lessThan(_keyboard),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
