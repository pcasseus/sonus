import 'dart:convert';

import 'musicbrainz_http_transport.dart';
import 'musicbrainz_rate_limiter.dart';

enum MusicBrainzEntity { artist, recording, release, releaseGroup }

extension MusicBrainzEntityPath on MusicBrainzEntity {
  String get path {
    switch (this) {
      case MusicBrainzEntity.artist:
        return 'artist';
      case MusicBrainzEntity.recording:
        return 'recording';
      case MusicBrainzEntity.release:
        return 'release';
      case MusicBrainzEntity.releaseGroup:
        return 'release-group';
    }
  }
}

class MusicBrainzApiException implements Exception {
  const MusicBrainzApiException({
    required this.message,
    required this.uri,
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final Uri uri;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() {
    return 'MusicBrainzApiException('
        'message: $message, '
        'statusCode: $statusCode, '
        'uri: $uri'
        ')';
  }
}

class MusicBrainzApiClient {
  MusicBrainzApiClient({
    required this.transport,
    required this.userAgent,
    MusicBrainzRateLimiter? rateLimiter,
    Uri? baseUri,
  }) : rateLimiter = rateLimiter ?? MusicBrainzRateLimiter(),
       baseUri = baseUri ?? Uri.parse('https://musicbrainz.org/ws/2/');

  final MusicBrainzHttpTransport transport;
  final MusicBrainzRateLimiter rateLimiter;
  final String userAgent;
  final Uri baseUri;

  Future<Map<String, dynamic>> search({
    required MusicBrainzEntity entity,
    required String query,
    int limit = 10,
    int offset = 0,
  }) async {
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      throw ArgumentError.value(
        query,
        'query',
        'MusicBrainz search query cannot be blank.',
      );
    }

    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(
        limit,
        'limit',
        'MusicBrainz search limit must be between 1 and 100.',
      );
    }

    if (offset < 0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'MusicBrainz search offset cannot be negative.',
      );
    }

    return _getJson(
      entity.path,
      queryParameters: {
        'query': normalizedQuery,
        'fmt': 'json',
        'limit': '$limit',
        'offset': '$offset',
      },
    );
  }

  Future<Map<String, dynamic>> lookup({
    required MusicBrainzEntity entity,
    required String id,
    List<String> includes = const [],
  }) async {
    final normalizedId = id.trim();

    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'MusicBrainz entity ID cannot be blank.',
      );
    }

    final queryParameters = <String, String>{'fmt': 'json'};

    final normalizedIncludes = includes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (normalizedIncludes.isNotEmpty) {
      queryParameters['inc'] = normalizedIncludes.join('+');
    }

    return _getJson(
      '${entity.path}/$normalizedId',
      queryParameters: queryParameters,
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String relativePath, {
    required Map<String, String> queryParameters,
  }) async {
    final trimmedUserAgent = userAgent.trim();

    if (trimmedUserAgent.isEmpty) {
      throw StateError('MusicBrainz requests require a non-empty User-Agent.');
    }

    await rateLimiter.waitForTurn();

    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';

    final uri = baseUri.replace(
      path: '$basePath$relativePath',
      queryParameters: queryParameters,
    );

    final response = await transport.get(
      uri,
      headers: {'Accept': 'application/json', 'User-Agent': trimmedUserAgent},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MusicBrainzApiException(
        message: 'MusicBrainz request failed.',
        uri: uri,
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'MusicBrainz response root is not an object.',
        );
      }

      return decoded;
    } on FormatException catch (error) {
      throw MusicBrainzApiException(
        message: 'MusicBrainz returned invalid JSON: $error',
        uri: uri,
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }
}
