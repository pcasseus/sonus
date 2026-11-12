// DEV-20: every Sonus build gets a versionCode above all earlier ones
// (tool/sonus-build-identity.ps1). Codes are whole minutes since
// 2026-01-01 UTC, reserved in a ledger so they can never repeat or go down.
@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _library = p.absolute('tool', 'sonus-build-identity.ps1');
const _signer =
    '92dd91c7be6e2de9d3f98b62fb61802fc2eb12ce548116a632b119a3a30776ab';

Future<ProcessResult> _ps(String body) {
  return Process.run('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    "\$ErrorActionPreference = 'Stop'; . '$_library'; $body",
  ]);
}

String _out(ProcessResult result) => '${result.stdout}\n${result.stderr}';

String _utc(String iso) =>
    "([DateTime]::Parse('$iso', [Globalization.CultureInfo]::InvariantCulture, "
    "'AdjustToUniversal,AssumeUniversal'))";

Future<String> _code(String iso) async {
  final result = await _ps('Get-SonusVersionCode -UtcNow ${_utc(iso)}');
  expect(result.exitCode, 0, reason: _out(result));
  return (result.stdout as String).trim();
}

void main() {
  group('versionCode', () {
    test('is whole minutes since 2026-01-01 UTC', () async {
      expect(await _code('2026-01-01T00:02:00Z'), '2');
      expect(await _code('2026-11-12T15:30:59Z'), '454530');
      expect(await _code('2027-01-01T00:00:00Z'), '525600');
    });

    test('rises with time and stays far below the Android limit', () async {
      final codes = [
        for (final iso in [
          '2026-11-12T15:30:00Z',
          '2026-11-12T15:31:00Z',
          '2026-12-31T23:59:00Z',
          '2030-06-01T00:00:00Z',
          '2100-01-01T00:00:00Z',
        ])
          int.parse(await _code(iso)),
      ];
      for (var i = 1; i < codes.length; i++) {
        expect(codes[i], greaterThan(codes[i - 1]));
      }
      expect(codes.last, lessThan(2100000000));
    });

    test('a local time is counted in UTC', () async {
      final result = await _ps(
        'Get-SonusVersionCode -UtcNow '
        "([DateTimeOffset]::Parse('2026-11-12T10:30:00-05:00').UtcDateTime)",
      );
      expect((result.stdout as String).trim(), '454530');
    });

    test('refuses a clock before 2026 and codes above the limit', () async {
      final early = await _ps(
        'Get-SonusVersionCode -UtcNow ${_utc('2025-12-31T23:00:00Z')}',
      );
      expect(early.exitCode, isNot(0));
      expect(_out(early), contains('Check the clock'));

      final late = await _ps(
        'Get-SonusVersionCode -UtcNow ([DateTime]::MaxValue)',
      );
      expect(late.exitCode, isNot(0));
      expect(_out(late), contains("above Android's limit"));
    });
  });

  group('ledger', () {
    late Directory dir;
    late String ledger;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sonus-ledger-');
      ledger = p.join(dir.path, 'nested', 'ledger.csv');
    });
    tearDown(() => dir.delete(recursive: true));

    Future<ProcessResult> reserve(String iso, {String flavor = 'prod'}) => _ps(
      'New-SonusVersionCode -Flavor $flavor -Commit abc1234 '
      "-Ledger '$ledger' -UtcNow ${_utc(iso)}",
    );

    test('reserves a code and records the build', () async {
      final reserved = await reserve('2026-11-12T15:30:00Z');
      expect(reserved.exitCode, 0, reason: _out(reserved));
      expect((reserved.stdout as String).trim(), '454530');

      final sha = 'a' * 64;
      final built = await _ps(
        'Add-SonusBuildRecord -VersionCode 454530 -Flavor prod '
        "-Sha256 $sha -Ledger '$ledger'",
      );
      expect(built.exitCode, 0, reason: _out(built));

      final lines = await File(ledger).readAsLines();
      expect(
        lines.first,
        'version_code,status,flavor,commit,sha256,recorded_utc',
      );
      expect(lines[1], '454530,reserved,prod,abc1234,,2026-11-12T15:30:00Z');
      expect(lines[2], startsWith('454530,built,prod,abc1234,$sha,'));
    });

    test(
      'never repeats a code: a second build in the same minute waits',
      () async {
        expect((await reserve('2026-11-12T15:30:00Z')).exitCode, 0);

        final again = await reserve('2026-11-12T15:30:40Z', flavor: 'qa');
        expect(again.exitCode, isNot(0));
        expect(
          _out(again),
          contains('not above the highest recorded (454530)'),
        );

        final next = await reserve('2026-11-12T15:31:00Z', flavor: 'qa');
        expect((next.stdout as String).trim(), '454531');
      },
    );

    test('never goes down when the clock is set back', () async {
      expect((await reserve('2026-11-12T15:30:00Z')).exitCode, 0);

      final earlier = await reserve('2026-11-11T09:00:00Z');
      expect(earlier.exitCode, isNot(0));
      expect(_out(earlier), contains('check the PC clock'));
      expect((await File(ledger).readAsLines()).length, 2);
    });

    test('two builds starting together never get the same code', () async {
      final results = await Future.wait([
        reserve('2026-11-12T15:30:00Z'),
        reserve('2026-11-12T15:30:00Z', flavor: 'qa'),
      ]);

      expect(results.where((r) => r.exitCode == 0).length, 1);
      final reserved = (await File(
        ledger,
      ).readAsLines()).skip(1).map((line) => line.split(',').first).toList();
      expect(reserved, ['454530']);
    });

    test(
      'a build is recorded only once, and only under its reservation',
      () async {
        expect((await reserve('2026-11-12T15:30:00Z')).exitCode, 0);
        final sha = 'b' * 64;
        Future<ProcessResult> record(int code, String flavor) => _ps(
          'Add-SonusBuildRecord -VersionCode $code -Flavor $flavor '
          "-Sha256 $sha -Ledger '$ledger'",
        );

        expect(
          _out(await record(454531, 'prod')),
          contains('was not reserved'),
        );
        expect(_out(await record(454530, 'qa')), contains('was not reserved'));
        expect((await record(454530, 'prod')).exitCode, 0);
        expect(
          _out(await record(454530, 'prod')),
          contains('already has a build'),
        );
      },
    );

    test('refuses a file that is not a build ledger', () async {
      await Directory(p.dirname(ledger)).create(recursive: true);
      await File(ledger).writeAsString('something else\n');

      final result = await reserve('2026-11-12T15:30:00Z');
      expect(result.exitCode, isNot(0));
      expect(_out(result), contains('is not a Sonus build ledger'));
      expect(await File(ledger).readAsString(), 'something else\n');
    });
  });

  group('APK identity', () {
    Future<ProcessResult> assertIdentity({
      String package = 'com.sonus.sonus_next',
      int versionCode = 454530,
      String authorities = "'com.sonus.sonus_next.artwork'",
      String signers = "'$_signer'",
    }) => _ps(
      '\$id = [pscustomobject]@{ Package = \'$package\'; '
      'VersionCode = $versionCode; Authorities = @($authorities); '
      'Signers = @($signers) }; '
      'Assert-SonusApkIdentity -Identity \$id -Package com.sonus.sonus_next '
      '-VersionCode 454530; "ok"',
    );

    test('accepts the real app signed by the Sonus certificate', () async {
      final result = await assertIdentity();
      expect(result.exitCode, 0, reason: _out(result));
    });

    test('refuses another package, versionCode, provider or signer', () async {
      expect(
        _out(await assertIdentity(package: 'com.sonus.sonus_next.qa')),
        contains("package 'com.sonus.sonus_next.qa'"),
      );
      expect(
        _out(await assertIdentity(versionCode: 1)),
        contains('versionCode 1, not 454530'),
      );
      expect(
        _out(await assertIdentity(authorities: "'com.other.artwork'")),
        contains('artwork provider'),
      );
      expect(
        _out(await assertIdentity(signers: "'${'0' * 64}'")),
        contains('not signed only by the Sonus certificate'),
      );
      expect(
        _out(await assertIdentity(signers: "'$_signer', '${'0' * 64}'")),
        contains('not signed only by the Sonus certificate'),
      );
    });
  });
}
