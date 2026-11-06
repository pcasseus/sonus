// Maintains test/visual_baselines/protected_manifest.json.
//
//   dart run test/visual_baselines/tool/protected_manifest_tool.dart check
//     Lists protected and shared files that changed since the manifest was
//     recorded, the screens they affect, and the tests to run. Exit code 1
//     when anything changed.
//
//   dart run test/visual_baselines/tool/protected_manifest_tool.dart update \
//       --approval "ROSTER-2: <what was approved, by whom, when>"
//     Records the current files and hashes and appends the approval to the
//     manifest's history. Only after the affected tests pass, or after an
//     approved visual change was re-recorded (see README.md).
//
// Run from the repository root.
import 'dart:io';

import '../support/protected_manifest.dart';

void main(List<String> args) {
  final command = args.isEmpty ? 'check' : args.first;
  switch (command) {
    case 'check':
      if (!File(manifestPath).existsSync()) {
        stderr.writeln('No manifest yet: run `update --approval ...`.');
        exitCode = 1;
        return;
      }
      final drift = compareWithDisk(readManifest());
      if (drift.isClean) {
        stdout.writeln('Protected screens unchanged since the manifest.');
        return;
      }
      stdout.write(drift.describe());
      exitCode = 1;
    case 'update':
      final index = args.indexOf('--approval');
      final approval = index < 0 || index + 1 >= args.length
          ? null
          : args[index + 1].trim();
      if (approval == null || approval.isEmpty) {
        stderr.writeln(
          'update needs --approval "<ticket and who approved it>".',
        );
        exitCode = 64;
        return;
      }
      final exists = File(manifestPath).existsSync();
      final previous = exists ? readManifest() : null;
      final drift = previous == null ? null : compareWithDisk(previous);
      final approvals = [
        ...?(previous?['approvals'] as List?)?.cast<Map<String, dynamic>>(),
        {
          'date': DateTime.now().toUtc().toIso8601String().substring(0, 10),
          'approval': approval,
          'protectedChanges': {
            for (final e in (drift?.changedOwned ?? const {}).entries)
              e.key: e.value,
          },
          'sharedChanges': {
            for (final e in (drift?.changedShared ?? const {}).entries)
              e.key: e.value,
          },
          'dependencyListChanges': drift?.membership ?? const <String>[],
        },
      ];
      writeManifest(buildManifest(approvals: approvals));
      stdout.writeln('Recorded $manifestPath ($approval).');
    default:
      stderr.writeln('Unknown command "$command" (use check or update).');
      exitCode = 64;
  }
}
