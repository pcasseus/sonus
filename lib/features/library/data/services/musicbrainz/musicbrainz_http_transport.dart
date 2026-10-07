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
  DartIoMusicBrainzHttpTransport({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient(),
      _ownsClient = httpClient == null;

  final HttpClient _httpClient;
  final bool _ownsClient;

  @override
  Future<MusicBrainzHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final request = await _httpClient.getUrl(uri);

    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

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
