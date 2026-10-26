import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonus_next/core/network/timed_http_client.dart';

const _short = Duration(milliseconds: 80);

TimedHttpClient _client(http.Client inner) => TimedHttpClient(
  inner: inner,
  connectTimeout: _short,
  responseTimeout: _short,
  transferIdleTimeout: _short,
);

Matcher _timeout(NetworkTimeoutPhase phase) =>
    isA<NetworkTimeoutException>().having((e) => e.phase, 'phase', phase);

void main() {
  final url = Uri.parse('https://cloud.invalid/rest/v1/albums');

  test('a request that never completes fails as a response timeout', () async {
    final client = _client(
      MockClient.streaming((_, _) => Completer<http.StreamedResponse>().future),
    );

    await expectLater(
      client.get(url),
      throwsA(_timeout(NetworkTimeoutPhase.response)),
    );
  });

  test('a connection that cannot be made fails as a connect timeout', () async {
    final client = _client(
      MockClient(
        (_) => throw const SocketException(
          'HTTP connection timed out after 0:00:15.000000, host: cloud.invalid',
        ),
      ),
    );

    await expectLater(
      client.get(url),
      throwsA(_timeout(NetworkTimeoutPhase.connect)),
    );
  });

  test('other connection failures keep their own error', () async {
    final client = _client(
      MockClient((_) => throw const SocketException('Network is unreachable')),
    );

    await expectLater(client.get(url), throwsA(isA<SocketException>()));
  });

  test(
    'a response that starts and then stalls fails as a transfer timeout',
    () async {
      final client = _client(
        MockClient.streaming((_, _) async {
          final body = StreamController<List<int>>();
          body.add([1, 2, 3]);
          return http.StreamedResponse(body.stream, 200);
        }),
      );

      await expectLater(
        client.get(url),
        throwsA(_timeout(NetworkTimeoutPhase.transfer)),
      );
    },
  );

  test('a prompt response passes through unchanged', () async {
    final client = _client(
      MockClient((_) async => http.Response('[]', 200, headers: {'a': 'b'})),
    );

    final response = await client.get(url);

    expect(response.statusCode, 200);
    expect(response.body, '[]');
    expect(response.headers['a'], 'b');
  });

  test('a server error is a response, not a timeout', () async {
    final client = _client(MockClient((_) async => http.Response('{}', 503)));

    expect((await client.get(url)).statusCode, 503);
  });

  test('larger uploads get proportionally more time', () {
    final client = TimedHttpClient(minUploadBytesPerSecond: 1000);

    expect(
      client.responseAllowance(5000) - client.responseAllowance(0),
      const Duration(seconds: 5),
    );
  });

  test('timeouts look like network failures to retrying clients', () {
    final error = NetworkTimeoutException(
      NetworkTimeoutPhase.response,
      _short,
      url,
    );

    expect(error, isA<http.ClientException>());
    expect(error, isA<TimeoutException>());
  });

  test('over a real socket, a server that never answers is bounded', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final held = <HttpRequest>[];
    server.listen(held.add);
    addTearDown(() async {
      for (final request in held) {
        await request.response.close();
      }
      await server.close(force: true);
    });

    final client = TimedHttpClient(
      connectTimeout: _short,
      responseTimeout: _short,
      transferIdleTimeout: _short,
    );
    addTearDown(client.close);

    final stopwatch = Stopwatch()..start();
    await expectLater(
      client.get(Uri.parse('http://127.0.0.1:${server.port}/rest/v1/songs')),
      throwsA(_timeout(NetworkTimeoutPhase.response)),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
