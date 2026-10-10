import 'dart:async';
import 'dart:io';

import 'cover_art_cancellation.dart';

class CoverArtBinaryResponse {
  const CoverArtBinaryResponse({
    required this.statusCode,
    required this.bytes,
    this.contentLength,
    this.contentType,
    this.location,
  });

  final int statusCode;
  final Stream<List<int>> bytes;
  final int? contentLength;
  final String? contentType;
  final String? location;
}

abstract interface class CoverArtBinaryTransport {
  Future<CoverArtBinaryResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    CoverArtCancellationToken? cancellationToken,
  });
}

class DartIoCoverArtBinaryTransport implements CoverArtBinaryTransport {
  DartIoCoverArtBinaryTransport({
    HttpClient? httpClient,
    this.responseHeaderTimeout = const Duration(seconds: 20),
    this.connectionTimeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsClient = httpClient == null {
    if (responseHeaderTimeout <= Duration.zero ||
        connectionTimeout <= Duration.zero) {
      throw ArgumentError('Timeouts must be positive.');
    }

    _httpClient.connectionTimeout = connectionTimeout;
  }

  final HttpClient _httpClient;
  final bool _ownsClient;
  final Duration responseHeaderTimeout;
  final Duration connectionTimeout;

  @override
  Future<CoverArtBinaryResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    CoverArtCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    HttpClientRequest? activeRequest;
    final unsubscribe = cancellationToken?.onCancel(() {
      activeRequest?.abort(const CoverArtCancelledException());
    });

    try {
      final pendingRequest = _httpClient.getUrl(uri).then((request) {
        activeRequest = request;

        if (cancellationToken?.isCancelled ?? false) {
          request.abort(const CoverArtCancelledException());
          throw const CoverArtCancelledException();
        }

        return request;
      });

      final request = await _awaitCancellation(
        pendingRequest,
        cancellationToken,
      );

      request.followRedirects = false;

      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }

      final pendingResponse = request.close().timeout(
        responseHeaderTimeout,
        onTimeout: () {
          request.abort();
          throw TimeoutException('Artwork response headers timed out.');
        },
      );

      final response = await _awaitCancellation(
        pendingResponse,
        cancellationToken,
      );

      if (cancellationToken?.isCancelled ?? false) {
        await response.drain<void>();
        throw const CoverArtCancelledException();
      }

      return CoverArtBinaryResponse(
        statusCode: response.statusCode,
        bytes: response,
        contentLength: response.contentLength >= 0
            ? response.contentLength
            : null,
        contentType: response.headers.contentType?.mimeType,
        location: response.headers.value(HttpHeaders.locationHeader),
      );
    } on CoverArtCancelledException {
      activeRequest?.abort(const CoverArtCancelledException());
      rethrow;
    } finally {
      unsubscribe?.call();
    }
  }

  static Future<T> _awaitCancellation<T>(
    Future<T> operation,
    CoverArtCancellationToken? token,
  ) {
    if (token == null) {
      return operation;
    }

    return Future.any<T>([
      operation,
      token.whenCancelled.then<T>(
        (_) => throw const CoverArtCancelledException(),
      ),
    ]);
  }

  void close() {
    if (_ownsClient) {
      _httpClient.close(force: true);
    }
  }
}
