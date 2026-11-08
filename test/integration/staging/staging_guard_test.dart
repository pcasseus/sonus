// The staging harness refuses every target but the isolated local stack.
// Runs in the normal suite; connects to nothing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/staging_guard.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(claims)}.sig';
}

final _anon = _jwt({'iss': 'supabase-demo', 'role': 'anon'});
final _service = _jwt({'iss': 'supabase-demo', 'role': 'service_role'});

StagingConfig? _check({
  String url = 'http://127.0.0.1:55421',
  String? anonKey,
  String? serviceKey,
  String appSupabaseUrl = '',
  String phase = '',
}) => checkStagingTarget(
  url: url,
  anonKey: anonKey ?? _anon,
  serviceKey: serviceKey ?? _service,
  appSupabaseUrl: appSupabaseUrl,
  phase: phase,
);

Matcher _refusedFor(String fragment) => throwsA(
  isA<StagingRefused>().having(
    (e) => e.reasons.join(' | '),
    'reasons',
    contains(fragment),
  ),
);

void main() {
  test('no target: skipped, nothing refused', () {
    expect(checkStagingTarget(url: '', anonKey: '', serviceKey: ''), isNull);
  });

  test('the isolated local stack is accepted', () {
    expect(_check()!.url.port, stagingApiPort);
    expect(_check(url: 'http://localhost:55421')!.url.host, 'localhost');
  });

  test('a hosted project is refused, by URL and by key', () {
    expect(
      () => _check(url: 'https://abcdefghijklmnop.supabase.co'),
      _refusedFor('host must be'),
    );
    expect(
      () => _check(
        anonKey: _jwt({'iss': 'supabase', 'ref': 'abcdefghij', 'role': 'anon'}),
      ),
      _refusedFor('not a local demo key'),
    );
    expect(
      () => _check(
        serviceKey: _jwt({
          'iss': 'supabase-demo',
          'ref': 'abcdefghij',
          'role': 'service_role',
        }),
      ),
      _refusedFor('belongs to a hosted project'),
    );
  });

  test('other local stacks and look-alikes are refused', () {
    // The app's local development stack.
    expect(
      () => _check(url: 'http://127.0.0.1:54321'),
      _refusedFor('staging port'),
    );
    expect(
      () => _check(url: 'https://127.0.0.1:55421'),
      _refusedFor('scheme must be http'),
    );
    expect(
      () => _check(url: 'http://127.0.0.1.example.com:55421'),
      _refusedFor('host must be'),
    );
    expect(
      () => _check(url: 'http://user@127.0.0.1:55421'),
      _refusedFor('bare origin'),
    );
    expect(
      () => _check(url: 'http://192.168.1.20:55421'),
      _refusedFor('host must be'),
    );
  });

  test('keys must be present, well formed and in the right role', () {
    expect(() => _check(anonKey: 'not-a-jwt'), _refusedFor('not a JWT'));
    expect(() => _check(anonKey: _service), _refusedFor('expected anon'));
    expect(
      () => _check(url: '', anonKey: _anon, serviceKey: _service),
      _refusedFor('SONUS_STAGING_URL is missing'),
    );
  });

  test('the app configuration must not be loaded alongside', () {
    expect(
      () => _check(appSupabaseUrl: 'https://abcdefghij.supabase.co'),
      _refusedFor('app configuration'),
    );
  });

  test('only known phases', () {
    expect(_check(phase: 'no-capability')!.phase, 'no-capability');
    expect(() => _check(phase: 'production'), _refusedFor('unknown'));
  });
}
