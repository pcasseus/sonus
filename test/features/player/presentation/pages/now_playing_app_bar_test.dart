import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import '../../../shell/presentation/widgets/shell_playback_slot_test.dart'
    as shell;

// Regression (UI integration emulator QA, 320dp at 2x): scrolling Now
// Playing slid the artwork under the transparent app bar, behind the title
// and Close.
void main() {
  testWidgets('the app bar turns solid when content scrolls under it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
    final background = theme.extension<SonusColors>()!.background;
    final engine = shell.FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [shell.track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );
    addTearDown(engine.dispose);

    await tester.pumpWidget(shell.buildSubject(engine, theme: theme));
    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    Color? barColor() => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;

    expect(barColor(), Colors.transparent);

    await tester.drag(
      find.byKey(const ValueKey<String>('now-playing-title')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(barColor(), background);
  });
}
