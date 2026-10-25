import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import '../../../shell/presentation/widgets/shell_playback_slot_test.dart'
    as shell;

// Reordering the queue without dragging: keyboard and screen-reader users
// get "Move up" and "Move down", which move a song exactly as a drag does.
void main() {
  Future<shell.FakePlaybackEngine> openQueue(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = shell.FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(
          tracks: [shell.track1, shell.track2, shell.track3],
          currentIndex: 0,
        ),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );
    addTearDown(engine.dispose);
    await tester.pumpWidget(shell.buildSubject(engine));
    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();
    return engine;
  }

  Object customAction(String label) =>
      CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label));

  testWidgets('Move down and Move up reorder like a drag', (tester) async {
    final semantics = tester.ensureSemantics();
    final engine = await openQueue(tester);

    final second = find.semantics.byPredicate(
      (node) =>
          node.getSemanticsData().customSemanticsActionIds?.isNotEmpty ==
              true &&
          node.getSemanticsData().label.contains('Second Song'),
    );

    tester.semantics.performAction(
      second,
      SemanticsAction.customAction,
      args: customAction('Move down'),
    );
    await tester.pump();
    expect(engine.lastMoveOldIndex, 1);
    expect(engine.lastMoveNewIndex, 2);

    tester.semantics.performAction(
      second,
      SemanticsAction.customAction,
      args: customAction('Move up'),
    );
    await tester.pump();
    expect(engine.lastMoveOldIndex, 1);
    expect(engine.lastMoveNewIndex, 0);

    semantics.dispose();
  });
}
