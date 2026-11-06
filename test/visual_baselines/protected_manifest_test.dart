// The protected-component manifest is current: no protected screen's own
// files, and none of the shared files that shape it, changed without the
// manifest being re-recorded with a named approval. When this fails, its
// message lists what changed, which screens it affects and which tests to
// run (see README.md).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/protected_manifest.dart';

void main() {
  test('every file the protected screens are defined by exists', () {
    final missing = [
      for (final screen in protectedScreens) ...[
        for (final pattern in screen.owned)
          if (expandPattern(pattern).isEmpty ||
              expandPattern(pattern).any((p) => !File(p).existsSync()))
            '${screen.id} owned: $pattern',
        for (final host in screen.hosts)
          if (!File(host).existsSync()) '${screen.id} host: $host',
        for (final test in screen.tests)
          if (!File(test).existsSync()) '${screen.id} test: $test',
      ],
      for (final path in globalShared)
        if (!File(path).existsSync()) 'global shared: $path',
    ];
    expect(missing, isEmpty);
  });

  test('the manifest records the current protected and shared files', () {
    final manifest = readManifest();
    final drift = compareWithDisk(manifest);
    if (!drift.isClean) fail(drift.describe());
  });

  test('every recorded state carries a named approval', () {
    final approvals = (readManifest()['approvals'] as List)
        .cast<Map<String, dynamic>>();
    expect(approvals, isNotEmpty);
    for (final approval in approvals) {
      expect(
        (approval['approval'] as String?)?.trim(),
        isNotEmpty,
        reason: 'an approval without a name',
      );
    }
  });

  test('the dependency guard sees shared design code and the hosts', () {
    final roster = filesOf(
      protectedScreens.firstWhere((s) => s.id == 'roster'),
    );
    // The picture's framing and the mini-player's height both changed the
    // Roster on the phone without artist_roster.dart changing.
    expect(
      roster.shared,
      containsAll([
        'lib/core/design/widgets/playback/sonus_mini_player.dart',
        'lib/features/shell/presentation/widgets/playback_host.dart',
        'lib/features/library/presentation/pages/library_page.dart',
        'lib/core/design/sonus_theme_factory.dart',
        'lib/core/design/widgets/sonus_glass_panel.dart',
      ]),
    );
    expect(
      roster.owned,
      contains(
        'lib/features/library/presentation/widgets/roster/artist_roster.dart',
      ),
    );
  });
}
