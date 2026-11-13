// App Update 1.2, DEV-20: the Update Center's foundation offers an update
// only from an authentic manifest (a signature by a pinned key, not a bare
// hash), for this package and signer, newer than both the installed build
// and any manifest seen, unexpired, over HTTPS from the trusted host; and a
// downloaded APK is checked byte for byte. It ships switched off.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/updates/application/update_policy.dart';
import 'package:sonus_next/features/updates/domain/update_manifest.dart';
import 'package:sonus_next/features/updates/update_center_config.dart';

/// A stand-in for Ed25519: an HMAC with the "public key", so any change to
/// the signed bytes or signature fails, as a real verifier would.
class _HmacVerifier implements UpdateSignatureVerifier {
  @override
  Future<bool> verify({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  }) async =>
      Hmac(sha256, publicKey).convert(message).toString() ==
      utf8.decode(signature, allowMalformed: true);
}

const _signer =
    '92dd91c7be6e2de9d3f98b62fb61802fc2eb12ce548116a632b119a3a30776ab';
final _key = utf8.encode('pinned-key-1');
final _now = DateTime.utc(2026, 12, 1);

const _installed = InstalledApp(
  applicationId: 'com.sonus.sonus_next',
  versionCode: 455111,
  signerSha256: _signer,
);

Map<String, Object?> _manifest({
  int versionCode = 460000,
  String applicationId = 'com.sonus.sonus_next',
  String signer = _signer,
  String url = 'https://updates.example.test/sonus-460000.apk',
  int size = 180000000,
  String expires = '2027-01-01T00:00:00Z',
  int schema = 1,
}) => {
  'schema': schema,
  'applicationId': applicationId,
  'versionCode': versionCode,
  'versionName': '1.2.0',
  'commit': 'abc1234',
  'apkUrl': url,
  'sizeBytes': size,
  'sha256': 'a' * 64,
  'signerSha256': signer,
  'publishedAtUtc': '2026-11-30T00:00:00Z',
  'expiresAtUtc': expires,
  'releaseNotes': 'Sonus Wrapped.',
};

/// The envelope as fetched: [payload] signed with [signingKey].
String _envelope(
  Map<String, Object?> payload, {
  String keyId = 'k1',
  List<int>? signingKey,
  Map<String, Object?>? signedInstead,
}) {
  final bytes = utf8.encode(jsonEncode(payload));
  final signed = utf8.encode(jsonEncode(signedInstead ?? payload));
  final signature = Hmac(sha256, signingKey ?? _key).convert(signed).toString();
  return jsonEncode({
    'keyId': keyId,
    'payload': base64Encode(bytes),
    'signature': base64Encode(utf8.encode(signature)),
  });
}

UpdatePolicy _policy({bool enabled = true}) => UpdatePolicy(
  enabled: enabled,
  trustedKeys: {'k1': _key},
  verifier: _HmacVerifier(),
  trustedHost: 'updates.example.test',
);

Future<UpdateRejection?> _why(
  String fetched, {
  int highestSeen = 0,
  UpdatePolicy? policy,
}) async {
  final evaluation = await (policy ?? _policy()).evaluate(
    fetched: fetched,
    installed: _installed,
    highestSeenVersionCode: highestSeen,
    nowUtc: _now,
  );
  return evaluation.rejection;
}

void main() {
  test('this build ships it switched off, with no keys and no host', () async {
    expect(UpdateCenterConfig.enabled, isFalse);
    expect(UpdateCenterConfig.trustedKeys, isEmpty);
    expect(UpdateCenterConfig.trustedHost, isEmpty);
    expect(
      await _why(_envelope(_manifest()), policy: _policy(enabled: false)),
      UpdateRejection.disabled,
    );
  });

  test('an authentic, newer manifest for this app is offered', () async {
    final evaluation = await _policy().evaluate(
      fetched: _envelope(_manifest()),
      installed: _installed,
      highestSeenVersionCode: 455111,
      nowUtc: _now,
    );
    expect(evaluation.isOffer, isTrue);
    expect(evaluation.manifest?.versionCode, 460000);
    expect(evaluation.manifest?.releaseNotes, 'Sonus Wrapped.');
  });

  group('authenticity, not a hash, decides trust', () {
    test('a manifest changed after signing is refused', () async {
      expect(
        await _why(
          _envelope(
            _manifest(url: 'https://updates.example.test/evil.apk'),
            signedInstead: _manifest(),
          ),
        ),
        UpdateRejection.badSignature,
      );
    });

    test(
      'a key this build does not pin, or a forged signature, is refused',
      () async {
        expect(
          await _why(_envelope(_manifest(), keyId: 'k9')),
          UpdateRejection.untrustedKey,
        );
        expect(
          await _why(_envelope(_manifest(), signingKey: utf8.encode('other'))),
          UpdateRejection.badSignature,
        );
      },
    );

    test('not an envelope, or a signed but unreadable manifest', () async {
      expect(await _why('{}'), UpdateRejection.malformedEnvelope);
      expect(await _why('not json'), UpdateRejection.malformedEnvelope);
      expect(
        await _why(_envelope(_manifest(schema: 2))),
        UpdateRejection.malformedManifest,
      );
      final missing = _manifest()..remove('sha256');
      expect(await _why(_envelope(missing)), UpdateRejection.malformedManifest);
    });
  });

  group('identity and order', () {
    test('another package or signing certificate is refused', () async {
      expect(
        await _why(_envelope(_manifest(applicationId: 'com.other.app'))),
        UpdateRejection.wrongPackage,
      );
      expect(
        await _why(_envelope(_manifest(signer: 'b' * 64))),
        UpdateRejection.wrongSigner,
      );
    });

    test('never a downgrade or a reinstall of the same build', () async {
      expect(
        await _why(_envelope(_manifest(versionCode: 455111))),
        UpdateRejection.notNewer,
      );
      expect(
        await _why(_envelope(_manifest(versionCode: 455067))),
        UpdateRejection.notNewer,
      );
    });

    test('a replayed older manifest is refused', () async {
      expect(
        await _why(
          _envelope(_manifest(versionCode: 458000)),
          highestSeen: 460000,
        ),
        UpdateRejection.replayed,
      );
    });

    test('an expired manifest is refused', () async {
      expect(
        await _why(_envelope(_manifest(expires: '2026-11-30T23:59:59Z'))),
        UpdateRejection.expired,
      );
    });
  });

  group('where the APK comes from', () {
    test('only HTTPS from the trusted host', () async {
      for (final url in [
        'http://updates.example.test/sonus.apk',
        'https://elsewhere.example.test/sonus.apk',
        'https://user:pw@updates.example.test/sonus.apk',
        'file:///sdcard/sonus.apk',
      ]) {
        expect(
          await _why(_envelope(_manifest(url: url))),
          UpdateRejection.untrustedLocation,
          reason: url,
        );
      }
    });

    test('an impossible size is refused', () async {
      expect(
        await _why(_envelope(_manifest(size: 0))),
        UpdateRejection.badSize,
      );
      expect(
        await _why(_envelope(_manifest(size: 600 * 1024 * 1024))),
        UpdateRejection.badSize,
      );
    });
  });

  group('the downloaded file', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('sonus-upd'));
    tearDown(() => dir.delete(recursive: true));

    UpdateManifest manifestFor(List<int> bytes) => UpdateManifest(
      applicationId: 'com.sonus.sonus_next',
      versionCode: 460000,
      versionName: '1.2.0',
      commit: 'abc1234',
      apkUrl: Uri.parse('https://updates.example.test/s.apk'),
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      signerSha256: _signer,
      publishedAtUtc: _now,
      expiresAtUtc: _now,
      releaseNotes: '',
    );

    test('matches size and SHA-256 exactly, or is refused', () async {
      final bytes = utf8.encode('apk bytes');
      final manifest = manifestFor(bytes);
      final file = File('${dir.path}/s.apk');
      const verifier = UpdateDownloadVerifier();

      expect(await verifier.check(file, manifest), DownloadRejection.missing);
      await file.writeAsBytes(bytes);
      expect(await verifier.check(file, manifest), isNull);
      await file.writeAsBytes(utf8.encode('apk bytes!'));
      expect(await verifier.check(file, manifest), DownloadRejection.wrongSize);
      await file.writeAsBytes(utf8.encode('apk bytez'));
      expect(await verifier.check(file, manifest), DownloadRejection.wrongHash);
    });
  });
}
