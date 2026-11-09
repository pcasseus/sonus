// App Update 1.2 patches, Checkpoint 4 (BUG-04): the shared Back to top
// button used by Charts (and its Moments) and Tracks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/widgets/sonus_scroll_to_top.dart';

const _button = ValueKey<String>('scroll-to-top');

class _Page extends StatefulWidget {
  const _Page({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int rows = 200;

  void show(int count) => setState(() => rows = count);

  @override
  Widget build(BuildContext context) {
    return SonusScrollToTop(
      controller: widget.controller,
      child: ListView(
        controller: widget.controller,
        children: [
          // A horizontal list inside the page: its scrolling is not the
          // page's.
          SizedBox(
            height: 60,
            child: ListView(
              key: const ValueKey<String>('rail'),
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(width: 120, child: Text('Card $i')),
              ],
            ),
          ),
          for (var i = 0; i < rows; i++)
            SizedBox(height: 50, child: Text('Row $i')),
        ],
      ),
    );
  }
}

void main() {
  late ScrollController controller;

  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  Future<GlobalKey<_PageState>> pump(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    final key = GlobalKey<_PageState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(
          SonusAppearanceSpec(reduceMotion: reduceMotion),
        ),
        home: Scaffold(
          body: _Page(key: key, controller: controller),
        ),
      ),
    );
    return key;
  }

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(_button),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('hidden near the top, shown far down, and returns to the top', (
    tester,
  ) async {
    await pump(tester);
    expect(opacity(tester), 0);

    controller.jumpTo(400);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0, reason: 'not yet far enough');

    controller.jumpTo(2000);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);

    await tester.tap(find.byKey(_button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0), reason: 'animated');
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(opacity(tester), 0);
  });

  testWidgets('with Reduce motion it jumps to the top', (tester) async {
    await pump(tester, reduceMotion: true);
    controller.jumpTo(2000);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_button));
    await tester.pump();

    expect(controller.offset, 0);
  });

  testWidgets('content that shrinks without a scroll hides it', (tester) async {
    final page = await pump(tester);
    controller.jumpTo(5000);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);

    // A filter or another board: far fewer rows, the page back near the
    // top with no scroll gesture.
    page.currentState!.show(5);
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(SonusScrollToTop.defaultShowAfter));
    expect(opacity(tester), 0);
  });

  testWidgets('scrolling a list inside the page does not show it', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(
      find.byKey(const ValueKey<String>('rail')),
      const Offset(-3000, 0),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
    expect(opacity(tester), 0);
  });

  testWidgets('while hidden it cannot be tapped or focused by a screen '
      'reader', (tester) async {
    bool excluded() => tester
        .widget<ExcludeSemantics>(
          find
              .ancestor(
                of: find.byKey(_button),
                matching: find.byType(ExcludeSemantics),
              )
              .first,
        )
        .excluding;
    bool ignored() => tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byKey(_button),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;

    await pump(tester);
    expect(excluded(), isTrue);
    expect(ignored(), isTrue);

    controller.jumpTo(2000);
    await tester.pumpAndSettle();
    expect(excluded(), isFalse);
    expect(ignored(), isFalse);
  });
}
