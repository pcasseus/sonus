import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MusicBrainzHttpResponse {
  const MusicBrainzHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

abstract interface class MusicBrainzHttpTransport {
  Future<MusicBrainzHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  });
}

class DartIoMusicBrainzHttpTransport implements MusicBrainzHttpTransport {
  DartIoMusicBrainzHttpTransport({
    HttpClient? httpClient,
    this.connectionTimeout = const Duration(seconds: 15),
    this.responseHeaderTimeout = const Duration(seconds: 20),
    this.responseBodyTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsClient = httpClient == null {
    if (connectionTimeout <= Duration.zero ||
        responseHeaderTimeout <= Duration.zero ||
        responseBodyTimeout <= Duration.zero) {
      throw ArgumentError('Timeouts must be positive.');
    }

    _httpClient.connectionTimeout = connectionTimeout;
  }

  final HttpClient _httpClient;
  final bool _ownsClient;

  final Duration connectionTimeout;
  final Duration responseHeaderTimeout;
  final Duration responseBodyTimeout;

  @override
  Future<MusicBrainzHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final request = await _httpClient.getUrl(uri);

    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }

    final response = await request.close().timeout(
      responseHeaderTimeout,
      onTimeout: () {
        request.abort();
        throw TimeoutException('Metadata response headers timed out.');
      },
    );

    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(
          responseBodyTimeout,
          onTimeout: () {
            throw TimeoutException('Metadata response body timed out.');
          },
        );

    final responseHeaders = <String, String>{};

    response.headers.forEach((name, values) {
      responseHeaders[name] = values.join(',');
    });

    return MusicBrainzHttpResponse(
      statusCode: response.statusCode,
      body: body,
      headers: responseHeaders,
    );
  }

  void close() {
    if (_ownsClient) {
      _httpClient.close(force: true);
    }
  }
}
