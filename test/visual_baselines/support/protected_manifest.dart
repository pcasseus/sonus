// The protected-component manifest: which files each approved screen owns,
// which shared files can change its look or layout, and a SHA-256 of every
// one of them as approved. Plain Dart (no Flutter), shared by
// protected_manifest_test.dart and tool/protected_manifest_tool.dart.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String manifestPath = 'test/visual_baselines/protected_manifest.json';

/// Shared code is followed through these folders only. Feature code that a
/// protected file imports is not followed further (the shell imports every
/// page; following them would make every change "shared").
const List<String> visualRoots = ['lib/core/design/', 'lib/features/shell/'];

/// How a protected screen is defined (the parts written by hand).
class ScreenDefinition {
  const ScreenDefinition({
    required this.id,
    required this.title,
    required this.owned,
    required this.hosts,
    required this.tests,
  });

  final String id;
  final String title;

  /// Files (or `dir/**`, `dir/*.dart` patterns) the screen owns. Changing
  /// one is a protected change that needs a named approval.
  final List<String> owned;

  /// Files that host or size the screen without being imported by it (the
  /// page that shows it, the shell around it). Treated as shared.
  final List<String> hosts;

  /// Tests to run when any owned or shared file changes.
  final List<String> tests;
}

/// Files every protected screen depends on: the theme pipeline and the app
/// root that wraps every page (system bars, keyboard inset, playback host).
const List<String> globalShared = [
  'lib/app/sonus_app.dart',
  'lib/core/design/sonus_theme_factory.dart',
  'lib/core/design/sonus_theme_catalog.dart',
  'lib/core/design/sonus_theme_definition.dart',
  'lib/core/design/sonus_typography.dart',
  'lib/core/design/sonus_tokens.dart',
  'lib/core/design/sonus_theme.dart',
  'lib/features/settings/presentation/scopes/appearance_scope.dart',
  'lib/features/shell/presentation/widgets/keyboard_inset_guard.dart',
  'lib/features/shell/presentation/widgets/sonus_system_bars.dart',
];

/// The shell every protected screen sits in.
const List<String> _shellHosts = [
  'lib/features/shell/presentation/pages/app_shell_page.dart',
  'lib/features/shell/presentation/widgets/playback_host.dart',
  'lib/features/shell/presentation/widgets/shell_playback_slot.dart',
  'lib/core/design/widgets/playback/sonus_mini_player.dart',
];

const List<ScreenDefinition> protectedScreens = [
  ScreenDefinition(
    id: 'roster',
    title: 'Artist Roster (accepted at a678b95)',
    owned: [
      'lib/features/library/presentation/widgets/roster/artist_roster.dart',
      'lib/core/design/widgets/sonus_framed_artwork.dart',
    ],
    hosts: [
      'lib/features/library/presentation/pages/library_page.dart',
      ..._shellHosts,
    ],
    tests: [
      'test/visual_baselines/roster_baseline_test.dart',
      'test/features/library/presentation/widgets/roster/artist_roster_test.dart',
    ],
  ),
  ScreenDefinition(
    id: 'home',
    title: 'Home',
    owned: ['lib/features/home/**'],
    hosts: _shellHosts,
    tests: [
      'test/visual_baselines/home_baseline_test.dart',
      'test/features/home/presentation/pages/home_page_test.dart',
    ],
  ),
  ScreenDefinition(
    id: 'navigation',
    title: 'Navigation and mini-player',
    owned: [
      'lib/core/design/widgets/playback/sonus_mini_player.dart',
      'lib/features/shell/presentation/widgets/shell_playback_slot.dart',
      'lib/features/shell/presentation/widgets/playback_host.dart',
      'lib/features/shell/presentation/widgets/sonus_system_bars.dart',
      'lib/features/shell/presentation/pages/app_shell_page.dart',
    ],
    hosts: [],
    tests: [
      'test/visual_baselines/navigation_baseline_test.dart',
      'test/core/design/sonus_mini_player_test.dart',
      'test/features/shell/presentation/widgets/shell_playback_slot_test.dart',
      'test/features/shell/presentation/widgets/playback_host_test.dart',
      'test/features/shell/presentation/pages/app_shell_page_test.dart',
    ],
  ),
  ScreenDefinition(
    id: 'now_playing',
    title: 'Full-screen player (Now Playing)',
    owned: [
      'lib/core/design/widgets/playback/sonus_now_playing_view.dart',
      'lib/core/design/widgets/playback/sonus_playback_controls.dart',
      'lib/core/design/widgets/playback/sonus_playback_progress.dart',
      'lib/features/player/presentation/pages/now_playing_page.dart',
    ],
    hosts: [
      'lib/features/shell/presentation/widgets/playback_host.dart',
      'lib/core/design/widgets/playback/sonus_mini_player.dart',
    ],
    tests: [
      'test/visual_baselines/now_playing_baseline_test.dart',
      'test/core/design/sonus_playback_components_test.dart',
    ],
  ),
];

/// A screen's files as they are on disk now.
class ScreenFiles {
  ScreenFiles(this.owned, this.shared);

  final List<String> owned;
  final List<String> shared;
}

String _normalize(String path) =>
    path.replaceAll(r'\', '/').replaceAll(RegExp('/+'), '/');

/// Expands `dir/**` (every .dart file below) and `dir/*.dart` (one level).
List<String> expandPattern(String pattern) {
  if (pattern.endsWith('/**') || pattern.endsWith('/*.dart')) {
    final recursive = pattern.endsWith('/**');
    final dir = Directory(pattern.substring(0, pattern.lastIndexOf('/')));
    if (!dir.existsSync()) return const [];
    return [
      for (final entity in dir.listSync(recursive: recursive))
        if (entity is File && entity.path.endsWith('.dart'))
          _normalize(entity.path),
    ]..sort();
  }
  return [pattern];
}

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<String> importsOf(String path) {
  final file = File(path);
  if (!file.existsSync()) return const [];
  final result = <String>[];
  for (final match in _directive.allMatches(file.readAsStringSync())) {
    final uri = match.group(1)!;
    if (uri.startsWith('dart:')) continue;
    if (uri.startsWith('package:')) {
      const own = 'package:sonus_next/';
      if (uri.startsWith(own)) result.add('lib/${uri.substring(own.length)}');
      continue;
    }
    result.add(_resolve(path, uri));
  }
  return result;
}

String _resolve(String from, String relative) {
  final parts = from.split('/')..removeLast();
  for (final segment in relative.split('/')) {
    if (segment == '..') {
      parts.removeLast();
    } else if (segment != '.') {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

bool _isVisual(String path) => visualRoots.any(path.startsWith);

/// Owned files, and shared files: everything in [visualRoots] reachable by
/// imports from the owned files and hosts (following imports only through
/// owned, host and visual files), plus the hosts and [globalShared].
ScreenFiles filesOf(ScreenDefinition screen) {
  final owned = {for (final p in screen.owned) ...expandPattern(p)};
  final starts = {...owned, ...screen.hosts};
  final seen = <String>{};
  final stack = [...starts];
  final shared = <String>{...screen.hosts, ...globalShared};
  while (stack.isNotEmpty) {
    final path = stack.removeLast();
    if (!seen.add(path)) continue;
    if (!File(path).existsSync()) continue;
    if (!starts.contains(path) && !_isVisual(path)) continue;
    if (_isVisual(path)) shared.add(path);
    stack.addAll(importsOf(path));
  }
  shared.removeAll(owned);
  return ScreenFiles(owned.toList()..sort(), shared.toList()..sort());
}

/// SHA-256 of the file with line endings normalised to LF, so a Windows
/// checkout (CRLF) and a Linux one hash the same.
String hashOf(String path) {
  final text = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  return sha256.convert(utf8.encode(text)).toString();
}

/// The manifest as it should be for the files on disk now (hashes of the
/// current contents). [approvals] are carried over.
Map<String, dynamic> buildManifest({
  required List<Map<String, dynamic>> approvals,
}) {
  final screens = <String, dynamic>{};
  final allFiles = <String>{};
  for (final screen in protectedScreens) {
    final files = filesOf(screen);
    allFiles
      ..addAll(files.owned)
      ..addAll(files.shared);
    screens[screen.id] = {
      'title': screen.title,
      'tests': screen.tests,
      'ownedPatterns': screen.owned,
      'hosts': screen.hosts,
      'owned': files.owned,
      'shared': files.shared,
    };
  }
  return {
    'version': 1,
    'about':
        'Protected visual baselines. Do not edit by hand: see '
        'test/visual_baselines/README.md.',
    'screens': screens,
    'hashes': {
      for (final path in allFiles.toList()..sort())
        path: File(path).existsSync() ? hashOf(path) : 'MISSING',
    },
    'approvals': approvals,
  };
}

Map<String, dynamic> readManifest() =>
    jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;

void writeManifest(Map<String, dynamic> manifest) {
  File(manifestPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}

/// What differs between the recorded manifest and the files on disk.
class ManifestDrift {
  ManifestDrift({
    required this.changedOwned,
    required this.changedShared,
    required this.membership,
  });

  /// screen id -> owned files whose contents changed (or appeared/vanished).
  final Map<String, List<String>> changedOwned;

  /// screen id -> shared files whose contents changed.
  final Map<String, List<String>> changedShared;

  /// Differences in which files belong to a screen (a new import, a new
  /// file under an owned folder).
  final List<String> membership;

  bool get isClean =>
      changedOwned.isEmpty && changedShared.isEmpty && membership.isEmpty;

  Set<String> get affectedScreens => {
    ...changedOwned.keys,
    ...changedShared.keys,
  };

  List<String> get testsToRun => <String>{
    for (final screen in protectedScreens)
      if (affectedScreens.contains(screen.id)) ...screen.tests,
  }.toList();

  String describe() {
    final out = StringBuffer();
    if (changedOwned.isNotEmpty) {
      out.writeln(
        'PROTECTED FILES CHANGED (needs a named approval for that screen):',
      );
      changedOwned.forEach((screen, files) {
        for (final f in files) {
          out.writeln('  [$screen] $f');
        }
      });
    }
    if (changedShared.isNotEmpty) {
      out.writeln('Shared dependencies of protected screens changed:');
      final byFile = <String, List<String>>{};
      changedShared.forEach((screen, files) {
        for (final f in files) {
          (byFile[f] ??= []).add(screen);
        }
      });
      byFile.forEach((f, screens) {
        out.writeln('  $f  (affects: ${screens.join(', ')})');
      });
    }
    if (membership.isNotEmpty) {
      out.writeln('Dependency lists changed:');
      for (final line in membership) {
        out.writeln('  $line');
      }
    }
    if (affectedScreens.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Run the affected protected tests:')
        ..writeln('  flutter test ${testsToRun.join(' ')}');
    }
    out
      ..writeln()
      ..writeln(
        'If they pass (or an approved visual change was re-recorded), record '
        'the new state:',
      )
      ..writeln(
        '  dart run test/visual_baselines/tool/protected_manifest_tool.dart '
        'update --approval "<ticket and approval>"',
      );
    return out.toString();
  }
}

ManifestDrift compareWithDisk(Map<String, dynamic> recorded) {
  final current = buildManifest(approvals: const []);
  final recordedHashes = (recorded['hashes'] as Map).cast<String, dynamic>();
  final currentHashes = (current['hashes'] as Map).cast<String, dynamic>();
  final recordedScreens = (recorded['screens'] as Map).cast<String, dynamic>();
  final currentScreens = (current['screens'] as Map).cast<String, dynamic>();

  final changedOwned = <String, List<String>>{};
  final changedShared = <String, List<String>>{};
  final membership = <String>[];

  for (final screen in protectedScreens) {
    final now = (currentScreens[screen.id] as Map).cast<String, dynamic>();
    final before = (recordedScreens[screen.id] as Map?)
        ?.cast<String, dynamic>();
    if (before == null) {
      membership.add('${screen.id}: not in the manifest yet');
      continue;
    }
    for (final kind in ['owned', 'shared']) {
      final a = (before[kind] as List).cast<String>().toSet();
      final b = (now[kind] as List).cast<String>().toSet();
      for (final added in b.difference(a)) {
        membership.add('${screen.id}: $kind now includes $added');
      }
      for (final removed in a.difference(b)) {
        membership.add('${screen.id}: $kind no longer includes $removed');
      }
      final target = kind == 'owned' ? changedOwned : changedShared;
      for (final file in b) {
        if (recordedHashes[file] != currentHashes[file]) {
          (target[screen.id] ??= []).add(file);
        }
      }
      if (kind == 'owned') {
        for (final file in a.difference(b)) {
          (target[screen.id] ??= []).add(file);
        }
      }
    }
  }
  return ManifestDrift(
    changedOwned: changedOwned,
    changedShared: changedShared,
    membership: membership,
  );
}
