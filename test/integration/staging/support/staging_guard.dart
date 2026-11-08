// App Update 1.2 staging harness: refuses any target except the isolated
// local Supabase stack. Read before anything connects.
//
// The harness reads only its own --dart-define values (SONUS_STAGING_*),
// never the app's configuration or the process environment, so neither a
// config file nor an environment variable can point it anywhere else.
import 'dart:convert';

/// The dedicated API port of the isolated stack (project sonus_pd_staging;
/// the app's local development stack uses 54321).
const int stagingApiPort = 55421;

/// The marker row that exists only in the staging database.
const String stagingMarkerName = 'sonus_pd_staging';

const String _url = String.fromEnvironment('SONUS_STAGING_URL');
const String _anonKey = String.fromEnvironment('SONUS_STAGING_ANON_KEY');
const String _serviceKey = String.fromEnvironment('SONUS_STAGING_SERVICE_KEY');
const String _phase = String.fromEnvironment('SONUS_STAGING_PHASE');

/// The app's own configuration; must be absent from a staging run.
const String _appSupabaseUrl = String.fromEnvironment('SUPABASE_URL');

class StagingConfig {
  const StagingConfig({
    required this.url,
    required this.anonKey,
    required this.serviceKey,
    this.phase = '',
  });

  final Uri url;
  final String anonKey;
  final String serviceKey;

  /// '' for the main run; 'no-capability' for the run against a server
  /// with migration 20261108000001 rolled back.
  final String phase;
}

class StagingRefused implements Exception {
  StagingRefused(this.reasons);

  final List<String> reasons;

  @override
  String toString() =>
      'Staging harness refused to run:\n- ${reasons.join('\n- ')}';
}

/// Null when no staging target was given: the harness is skipped (as in
/// the normal test suite). Throws [StagingRefused] when a target was given
/// but is not the isolated local stack.
StagingConfig? stagingConfig() => checkStagingTarget(
  url: _url,
  anonKey: _anonKey,
  serviceKey: _serviceKey,
  appSupabaseUrl: _appSupabaseUrl,
  phase: _phase,
);

StagingConfig? checkStagingTarget({
  required String url,
  required String anonKey,
  required String serviceKey,
  String appSupabaseUrl = '',
  String phase = '',
}) {
  if (url.isEmpty && anonKey.isEmpty && serviceKey.isEmpty) return null;

  final reasons = <String>[];
  if (appSupabaseUrl.isNotEmpty) {
    reasons.add(
      'the app configuration (SUPABASE_URL) is loaded; run without '
      '--dart-define-from-file',
    );
  }
  final uri = Uri.tryParse(url);
  if (uri == null || url.isEmpty) {
    reasons.add('SONUS_STAGING_URL is missing or not a URL');
  } else {
    if (uri.scheme != 'http') reasons.add('scheme must be http (local)');
    if (!const {'127.0.0.1', 'localhost'}.contains(uri.host)) {
      reasons.add('host must be 127.0.0.1 or localhost, not "${uri.host}"');
    }
    if (uri.port != stagingApiPort) {
      reasons.add('port must be the staging port $stagingApiPort');
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      reasons.add('the URL must have no path');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      reasons.add('the URL must be a bare origin');
    }
  }
  for (final (name, key, role) in [
    ('SONUS_STAGING_ANON_KEY', anonKey, 'anon'),
    ('SONUS_STAGING_SERVICE_KEY', serviceKey, 'service_role'),
  ]) {
    final claims = _claims(key);
    if (claims == null) {
      reasons.add('$name is missing or not a JWT');
      continue;
    }
    // Keys of hosted projects name the project ("ref") and are issued by
    // "supabase"; the local CLI's demo keys are issued by "supabase-demo".
    if (claims['iss'] != 'supabase-demo') {
      reasons.add('$name is not a local demo key (iss=${claims['iss']})');
    }
    if (claims.containsKey('ref')) {
      reasons.add('$name belongs to a hosted project');
    }
    if (claims['role'] != role) {
      reasons.add('$name has role ${claims['role']}, expected $role');
    }
  }
  if (!const {'', 'no-capability', 'old-b', 'old-d'}.contains(phase)) {
    reasons.add('unknown SONUS_STAGING_PHASE "$phase"');
  }
  if (reasons.isNotEmpty) throw StagingRefused(reasons);

  return StagingConfig(
    url: Uri.parse(url),
    anonKey: anonKey,
    serviceKey: serviceKey,
    phase: phase,
  );
}

Map<String, Object?>? _claims(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
