import 'dart:convert';

import '../../../../library/data/services/musicbrainz/musicbrainz_http_transport.dart';
import '../../../application/models/cover_art_archive_image.dart';

class CoverArtArchiveException implements Exception {
  const CoverArtArchiveException({
    required this.message,
    required this.uri,
    this.statusCode,
  });

  final String message;
  final Uri uri;
  final int? statusCode;

  @override
  String toString() =>
      'CoverArtArchiveException($message, statusCode: $statusCode, uri: $uri)';
}

class CoverArtArchiveClient {
  CoverArtArchiveClient({
    required this.transport,
    required this.userAgent,
    Uri? baseUri,
  }) : baseUri = baseUri ?? Uri.parse('https://coverartarchive.org/');

  final MusicBrainzHttpTransport transport;
  final String userAgent;
  final Uri baseUri;

  static final RegExp _mbidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<List<CoverArtArchiveImage>> lookup({
    required CoverArtArchiveEntity entity,
    required String id,
  }) async {
    final normalizedId = id.trim().toLowerCase();

    if (!_mbidPattern.hasMatch(normalizedId)) {
      throw ArgumentError.value(
        id,
        'id',
        'Cover Art Archive requires a valid MusicBrainz UUID.',
      );
    }

    final agent = userAgent.trim();
    if (agent.isEmpty) {
      throw StateError('Cover Art Archive requires a User-Agent.');
    }

    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';

    final uri = baseUri.replace(
      path: '$basePath${entity.path}/$normalizedId',
      query: null,
      fragment: null,
    );

    final response = await transport.get(
      uri,
      headers: {'Accept': 'application/json', 'User-Agent': agent},
    );

    if (response.statusCode == 404) {
      return const [];
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CoverArtArchiveException(
        message: 'Cover Art Archive request failed.',
        uri: uri,
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> || decoded['images'] is! List) {
        throw const FormatException('Missing images array.');
      }

      final images = <CoverArtArchiveImage>[];

      for (final entry in decoded['images'] as List) {
        if (entry is! Map) {
          continue;
        }

        final url = entry['image'];
        if (url is! String || !_isHttpsUrl(url)) {
          continue;
        }

        final thumbnails = entry['thumbnails'];
        String? thumbnail;

        if (thumbnails is Map) {
          for (final key in ['250', 'small', '500', 'large']) {
            final candidate = thumbnails[key];
            if (candidate is String && _isHttpsUrl(candidate)) {
              thumbnail = candidate;
              break;
            }
          }
        }

        final rawTypes = entry['types'];
        final types = rawTypes is List
            ? rawTypes.whereType<String>().toList(growable: false)
            : <String>[];

        final rawImageId = entry['id'];

        images.add(
          CoverArtArchiveImage(
            entity: entity,
            entityId: normalizedId,
            imageUrl: url,
            imageId: rawImageId == null ? null : '$rawImageId',
            thumbnailUrl: thumbnail,
            front: entry['front'] == true,
            back: entry['back'] == true,
            types: List.unmodifiable(types),
            approved: entry['approved'] == true,
          ),
        );
      }

      return List.unmodifiable(images);
    } on FormatException catch (error) {
      throw CoverArtArchiveException(
        message: 'Invalid Cover Art Archive JSON: $error',
        uri: uri,
        statusCode: response.statusCode,
      );
    }
  }

  static bool _isHttpsUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}
