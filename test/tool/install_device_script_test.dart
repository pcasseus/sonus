// DEV-20: tool/install-device.ps1 installs a Sonus build over the one on a
// device in place, keeping its data. These tests run the real script against
// stand-ins for adb, aapt and apksigner (test/tool/fakes), so no device is
// ever contacted. Each fake logs every call and refuses unknown commands.
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _serial = '192.168.1.20:37099';
const _package = 'com.sonus.sonus_next';
const _signer =
    '92dd91c7be6e2de9d3f98b62fb61802fc2eb12ce548116a632b119a3a30776ab';
const _otherSigner =
    '0000000000000000000000000000000000000000000000000000000000000001';

final _script = p.absolute('tool', 'install-device.ps1');
final _fakes = p.absolute('test', 'tool', 'fakes');

class _Rig {
  _Rig(this.root);

  final Directory root;
  late final String database = p.join(root.path, 'device.db');
  late final String state = p.join(root.path, 'state.json');
  late final String log = p.join(root.path, 'adb.log');
  late final String apkDir = p.join(root.path, 'apks');
  late final String ledger = p.join(root.path, 'ledger.csv');
  late final String backups = p.join(root.path, 'backups');

  static Future<_Rig> create() async {
    final rig = _Rig(await Directory.systemTemp.createTemp('sonus-install-'));
    await Directory(rig.apkDir).create();
    await Directory(rig.backups).create();
    await File(rig.log).writeAsString('');
    await File(
      rig.ledger,
    ).writeAsString('version_code,status,flavor,commit,sha256,recorded_utc\n');
    await rig.writeDatabase(songs: 3, plays: 5);
    return rig;
  }

  Future<void> writeDatabase({
    required int songs,
    required int plays,
    int version = 45,
  }) async {
    final file = File(database);
    if (await file.exists()) await file.delete();
    final db = await databaseFactoryFfi.openDatabase(database);
    await db.execute('CREATE TABLE songs (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE qualified_plays (id TEXT PRIMARY KEY)');
    for (var i = 0; i < songs; i++) {
      await db.insert('songs', {'id': 'song-$i'});
    }
    for (var i = 0; i < plays; i++) {
      await db.insert('qualified_plays', {'id': 'play-$i'});
    }
    await db.execute('PRAGMA user_version = $version');
    await db.close();
  }

  /// Writes an APK stand-in and registers what aapt and apksigner report
  /// for it. Returns its path.
  Future<String> apk(
    String name, {
    String package = _package,
    required int versionCode,
    bool debuggable = true,
    List<String>? authorities,
    List<String> signers = const [_signer],
    bool recorded = true,
  }) async {
    final path = p.join(root.path, '$name.apk');
    await File(path).writeAsString('apk $name $versionCode $package');
    final sha = sha256.convert(await File(path).readAsBytes()).toString();
    await File(p.join(apkDir, '$sha.json')).writeAsString(
      jsonEncode({
        'package': package,
        'versionCode': versionCode,
        'debuggable': debuggable,
        'authorities': authorities ?? ['$package.artwork'],
        'signers': signers,
      }),
    );
    if (recorded) {
      final flavor = package.endsWith('.qa') ? 'qa' : 'prod';
      await File(ledger).writeAsString(
        '$versionCode,reserved,$flavor,abc1234,,2026-11-12T15:30:00Z\n'
        '$versionCode,built,$flavor,abc1234,$sha,2026-11-12T15:35:00Z\n',
        mode: FileMode.append,
      );
    }
    return path;
  }

  Future<void> device({
    required String installedApk,
    int installedVersionCode = 1,
    bool installedDebuggable = true,
    String deviceState = 'device',
    int journalBytes = 0,
    String installOutcome = 'ok',
  }) {
    return File(state).writeAsString(
      jsonEncode({
        'devices': [
          {'serial': _serial, 'state': deviceState},
          {'serial': 'R5CY00OTHER', 'state': 'device'},
        ],
        'package': _package,
        'installed': {
          'versionCode': installedVersionCode,
          'debuggable': installedDebuggable,
          'firstInstallTime': '2026-10-25 12:00:00',
          'lastUpdateTime': '2026-11-10 16:30:57',
          'apk': installedApk,
        },
        'database': database,
        'journalBytes': journalBytes,
        'installOutcome': installOutcome,
      }),
    );
  }

  Future<ProcessResult> run({
    String serial = _serial,
    String? apk,
    bool checkOnly = false,
    String? baseline,
  }) {
    return Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        _script,
        '-Serial',
        serial,
        '-BackupRoot',
        backups,
        if (apk != null) ...['-Apk', apk],
        if (checkOnly) '-CheckOnly',
        if (baseline != null) ...['-Baseline', baseline],
        '-Ledger',
        ledger,
        '-Adb',
        p.join(_fakes, 'fake_adb.ps1'),
        '-Aapt',
        p.join(_fakes, 'fake_aapt.ps1'),
        '-Apksigner',
        p.join(_fakes, 'fake_apksigner.ps1'),
      ],
      environment: {
        'FAKE_ADB_STATE': state,
        'FAKE_ADB_LOG': log,
        'FAKE_APK_DIR': apkDir,
      },
    );
  }

  Future<List<String>> calls() async =>
      (await File(log).readAsLines()).where((l) => l.isNotEmpty).toList();

  Future<Map<String, dynamic>> deviceState() async =>
      jsonDecode(await File(state).readAsString()) as Map<String, dynamic>;
}

String _output(ProcessResult result) => '${result.stdout}\n${result.stderr}';

/// What the script must never do, whatever happens.
Future<void> _neverDestructive(_Rig rig) async {
  for (final call in await rig.calls()) {
    if (call == 'devices') continue;
    expect(call, startsWith('-s $_serial '), reason: 'every call names it');
    expect(call, isNot(contains('uninstall')));
    expect(call, isNot(contains('pm clear')));
    expect(call, isNot(matches(RegExp(r'install\b.*\s-d\b'))));
    expect(call, isNot(contains('install-multiple')));
  }
}

Future<void> _refusedWithoutInstalling(
  _Rig rig,
  ProcessResult result,
  String reason,
) async {
  expect(result.exitCode, isNot(0), reason: _output(result));
  expect(_output(result), contains(reason));
  final calls = await rig.calls();
  expect(calls.where((c) => c.contains(' install ')), isEmpty);
  expect(
    (await rig.deviceState())['installed']['versionCode'],
    1,
    reason: 'the installed app is untouched',
  );
  await _neverDestructive(rig);
}

void main() {
  sqfliteFfiInit();

  late _Rig rig;
  late String installed;

  setUp(() async {
    rig = await _Rig.create();
    installed = await rig.apk('installed', versionCode: 1, recorded: false);
  });

  tearDown(() => rig.root.delete(recursive: true));

  test(
    'installs in place after a verified backup, then checks the result',
    () async {
      final update = await rig.apk('update', versionCode: 454530);
      await rig.device(installedApk: installed);

      final result = await rig.run(apk: update);

      expect(result.exitCode, 0, reason: _output(result));
      final calls = await rig.calls();
      expect(calls, contains('-s $_serial install -r $update'));
      final stop = calls.indexOf('-s $_serial shell am force-stop $_package');
      final firstCopy = calls.indexWhere((c) => c.contains('cat databases'));
      final install = calls.indexWhere((c) => c.contains(' install -r '));
      expect(stop, greaterThanOrEqualTo(0));
      expect(firstCopy, greaterThan(stop), reason: 'backed up when stopped');
      expect(install, greaterThan(firstCopy), reason: 'backup first');
      expect(
        calls.where((c) => c.contains('cat databases')).length,
        6,
        reason: 'three copies before and three after',
      );
      await _neverDestructive(rig);

      final state = await rig.deviceState();
      expect(state['installed']['versionCode'], 454530);
      expect(state['installed']['firstInstallTime'], '2026-10-25 12:00:00');

      final folder = Directory(rig.backups).listSync().single as Directory;
      final backup = File(p.join(folder.path, 'before-db-a.db'));
      expect(
        await backup.readAsBytes(),
        await File(rig.database).readAsBytes(),
      );
      expect(File(p.join(folder.path, 'app_data.tar')).existsSync(), isTrue);
      expect(
        File(p.join(folder.path, 'installed_base.apk')).readAsStringSync(),
        File(installed).readAsStringSync(),
        reason: 'the previous APK is kept',
      );
      final report =
          jsonDecode(
                File(p.join(folder.path, 'report.json')).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(report['database']['user_version'], 45);
      expect(report['database']['integrity_check'], ['ok']);
      expect(report['database']['counts'], {'qualified_plays': 5, 'songs': 3});
      expect(report['installed_after']['VersionCode'], 454530);
      expect(_output(result), contains('-CheckOnly -Baseline'));
    },
  );

  test('refuses a device that is not the one named', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed);

    final result = await rig.run(serial: 'R5CY00MISSING', apk: update);

    expect(result.exitCode, isNot(0));
    expect(_output(result), contains('is not connected and authorised'));
    expect(await rig.calls(), ['devices'], reason: 'nothing else was run');
  });

  test('refuses a device that has not authorised this PC', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed, deviceState: 'unauthorized');

    final result = await rig.run(apk: update);

    expect(result.exitCode, isNot(0));
    expect(_output(result), contains('is not connected and authorised'));
    expect(await rig.calls(), ['devices']);
  });

  test('refuses another package', () async {
    final qa = await rig.apk(
      'qa',
      package: 'com.sonus.sonus_next.qa',
      versionCode: 454530,
    );
    await rig.device(installedApk: installed);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: qa),
      "package 'com.sonus.sonus_next.qa', not com.sonus.sonus_next",
    );
  });

  test('refuses an APK without the Sonus artwork provider', () async {
    final update = await rig.apk(
      'update',
      versionCode: 454530,
      authorities: ['com.sonus.sonus_next.qa.artwork'],
    );
    await rig.device(installedApk: installed);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'artwork provider is not com.sonus.sonus_next.artwork',
    );
  });

  test('refuses an APK signed with another certificate', () async {
    final update = await rig.apk(
      'update',
      versionCode: 454530,
      signers: [_otherSigner],
    );
    await rig.device(installedApk: installed);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'not signed only by the Sonus certificate',
    );
  });

  test('refuses when the installed app has another certificate', () async {
    final strange = await rig.apk(
      'strange',
      versionCode: 1,
      signers: [_otherSigner],
      recorded: false,
    );
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: strange);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'not the Sonus certificate',
    );
  });

  test('refuses an APK the build scripts did not record', () async {
    final update = await rig.apk(
      'update',
      versionCode: 454530,
      recorded: false,
    );
    await rig.device(installedApk: installed);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'is not a recorded prod build',
    );
  });

  test('refuses an APK that is not debuggable', () async {
    final update = await rig.apk(
      'update',
      versionCode: 454530,
      debuggable: false,
    );
    await rig.device(installedApk: installed);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'The APK is not debuggable',
    );
  });

  for (final installedCode in [454530, 454531]) {
    test('never downgrades or reinstalls the same versionCode '
        '(installed $installedCode)', () async {
      final update = await rig.apk('update', versionCode: 454530);
      await rig.device(
        installedApk: installed,
        installedVersionCode: installedCode,
      );

      final result = await rig.run(apk: update);

      expect(result.exitCode, isNot(0));
      expect(_output(result), contains('Downgrades are never installed'));
      expect(
        (await rig.calls()).where((c) => c.contains(' install ')),
        isEmpty,
      );
      expect(
        (await rig.calls()).where((c) => c.contains('cat databases')),
        isEmpty,
        reason: 'refused before touching the data',
      );
      await _neverDestructive(rig);
    });
  }

  test('refuses when the installed app cannot be backed up', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed, installedDebuggable: false);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'is not debuggable, so its data cannot be backed up',
    );
  });

  test('refuses a database with an unfinished transaction', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed, journalBytes: 4096);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'unfinished transaction',
    );
  });

  test('refuses a database that is not readable', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await File(rig.database).writeAsString('not a database at all');
    await rig.device(installedApk: installed);

    await _refusedWithoutInstalling(
      rig,
      await rig.run(apk: update),
      'could not read the copy',
    );
  });

  test('a failed install is reported and leaves the app as it was', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed, installOutcome: 'fail');

    final result = await rig.run(apk: update);

    expect(result.exitCode, isNot(0));
    expect(_output(result), contains('INSTALL_FAILED'));
    expect((await rig.deviceState())['installed']['versionCode'], 1);
    await _neverDestructive(rig);
  });

  test('a wireless connection lost mid-install is reported; the app and '
      'the verified backup are left as they were', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed, installOutcome: 'disconnected');

    final result = await rig.run(apk: update);

    expect(result.exitCode, isNot(0));
    expect(_output(result), contains('not found'));
    expect((await rig.deviceState())['installed']['versionCode'], 1);
    final folder = Directory(rig.backups).listSync().single as Directory;
    expect(File(p.join(folder.path, 'report.json')).existsSync(), isTrue);
    expect(File(p.join(folder.path, 'before-db-a.db')).existsSync(), isTrue);
    await _neverDestructive(rig);
  });

  test('reports an install that was not in place', () async {
    final update = await rig.apk('update', versionCode: 454530);
    await rig.device(installedApk: installed, installOutcome: 'reinstalled');

    final result = await rig.run(apk: update);

    expect(result.exitCode, isNot(0));
    expect(_output(result), contains('was not updated in place'));
    await _neverDestructive(rig);
  });

  group('check only', () {
    Future<String> baseline() async {
      await rig.device(installedApk: installed);
      final first = await rig.run(checkOnly: true);
      expect(first.exitCode, 0, reason: _output(first));
      final folder = Directory(rig.backups).listSync().single;
      return p.join(folder.path, 'report.json');
    }

    test('backs up and checks without installing', () async {
      await baseline();

      final calls = await rig.calls();
      expect(calls.where((c) => c.contains(' install')), isEmpty);
      expect(calls.where((c) => c.contains('cat databases')).length, 3);
      await _neverDestructive(rig);
    });

    test('passes after an upgrade that kept every row', () async {
      final report = await baseline();
      await rig.writeDatabase(songs: 3, plays: 6, version: 46);
      await Future<void>.delayed(const Duration(seconds: 1));

      final result = await rig.run(checkOnly: true, baseline: report);

      expect(result.exitCode, 0, reason: _output(result));
      expect(_output(result), contains('No rows lost'));
    });

    test('fails when rows were lost', () async {
      final report = await baseline();
      await rig.writeDatabase(songs: 2, plays: 5);
      await Future<void>.delayed(const Duration(seconds: 1));

      final result = await rig.run(checkOnly: true, baseline: report);

      expect(result.exitCode, isNot(0));
      expect(_output(result), contains('songs has fewer rows than before'));
    });
  });
}
