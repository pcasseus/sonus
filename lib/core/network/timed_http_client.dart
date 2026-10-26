import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Which stage of a request ran out of time.
enum NetworkTimeoutPhase {
  /// No connection to the server.
  connect,

  /// Connected and sent, but no response arrived.
  response,

  /// The response started, then stopped arriving.
  transfer,
}

/// A request that ran out of time. It is a [http.ClientException], so
/// libraries that treat client errors as retryable network failures (the
/// auth client does) handle it the same way.
class NetworkTimeoutException extends http.ClientException
    implements TimeoutException {
  NetworkTimeoutException(this.phase, this.duration, Uri? uri)
    : super('No ${phase.name} within ${duration.inSeconds}s', uri);

  final NetworkTimeoutPhase phase;

  @override
  final Duration duration;
}

/// An HTTP client whose requests always finish: they either complete or
/// fail with a [NetworkTimeoutException].
///
/// Timing out only fails the caller's await; the caller's own error
/// handling then runs as for any network failure. A request that timed out
/// may still have reached the server, so writes through this client must
/// be safe to retry (cloud sync writes are keyed by permanent IDs and
/// conditional on server revisions).
class TimedHttpClient extends http.BaseClient {
  TimedHttpClient({
    http.Client? inner,
    this.connectTimeout = const Duration(seconds: 15),
    this.responseTimeout = const Duration(seconds: 30),
    this.transferIdleTimeout = const Duration(seconds: 30),
    this.minUploadBytesPerSecond = 16 * 1024,
  }) : _inner =
           inner ?? IOClient(HttpClient()..connectionTimeout = connectTimeout);

  final http.Client _inner;

  /// How long to wait for a connection.
  final Duration connectTimeout;

  /// How long to wait for a response once the request is under way, before
  /// any extra time for uploading the request body.
  final Duration responseTimeout;

  /// How long a response body may pause between chunks.
  final Duration transferIdleTimeout;

  /// The slowest upload allowed for; a larger body gets more time.
  final int minUploadBytesPerSecond;

  /// The response deadline for a request with [bodyBytes] to upload.
  Duration responseAllowance(int bodyBytes) =>
      connectTimeout +
      responseTimeout +
      Duration(milliseconds: bodyBytes * 1000 ~/ minUploadBytesPerSecond);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final allowance = responseAllowance(request.contentLength ?? 0);

    final http.StreamedResponse response;
    try {
      response = await _inner
          .send(request)
          .timeout(
            allowance,
            onTimeout: () => throw NetworkTimeoutException(
              NetworkTimeoutPhase.response,
              allowance,
              request.url,
            ),
          );
    } on SocketException catch (error) {
      if (error.message.contains('timed out')) {
        throw NetworkTimeoutException(
          NetworkTimeoutPhase.connect,
          connectTimeout,
          request.url,
        );
      }
      rethrow;
    }

    final body = response.stream.timeout(
      transferIdleTimeout,
      onTimeout: (sink) {
        sink.addError(
          NetworkTimeoutException(
            NetworkTimeoutPhase.transfer,
            transferIdleTimeout,
            request.url,
          ),
        );
        sink.close();
      },
    );

    return http.StreamedResponse(
      http.ByteStream(body),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
