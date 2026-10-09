import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'cover_art_archive_binary_transport.dart';
import 'cover_art_cancellation.dart';

enum CoverArtImageFormat { jpeg, png, webp }

extension CoverArtImageFormatExtension on CoverArtImageFormat {
  String get extension => switch (this) {
    CoverArtImageFormat.jpeg => 'jpg',
    CoverArtImageFormat.png => 'png',
    CoverArtImageFormat.webp => 'webp',
  };
}

class CoverArtDownloadException implements Exception {
  const CoverArtDownloadException(this.message);

  final String message;

  @override
  String toString() => 'CoverArtDownloadException: $message';
}

class CoverArtDownloadResult {
  const CoverArtDownloadResult({
    required this.filePath,
    required this.temporaryDirectoryPath,
    required this.format,
    required this.byteLength,
  });

  final String filePath;
  final String temporaryDirectoryPath;
  final CoverArtImageFormat format;
  final int byteLength;

  Future<void> deleteTemporaryFiles() async {
    final directory = Directory(temporaryDirectoryPath);

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

typedef CoverArtTemporaryDirectoryProvider = Future<Directory> Function();

class CoverArtArchiveDownloader {
  CoverArtArchiveDownloader({
    required this.transport,
    required this.userAgent,
    CoverArtTemporaryDirectoryProvider? temporaryDirectoryProvider,
    this.maximumBytes = 10 * 1024 * 1024,
    this.maximumRedirects = 5,
    this.inactivityTimeout = const Duration(seconds: 20),
    this.overallTimeout = const Duration(seconds: 60),
  }) : temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? _systemTemporaryDirectory {
    if (maximumBytes < 12) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    if (overallTimeout <= Duration.zero) {
      throw ArgumentError.value(overallTimeout, 'overallTimeout');
    }
    if (inactivityTimeout <= Duration.zero) {
      throw ArgumentError.value(inactivityTimeout, 'inactivityTimeout');
    }
    if (maximumRedirects < 0) {
      throw ArgumentError.value(maximumRedirects, 'maximumRedirects');
    }
  }

  final CoverArtBinaryTransport transport;
  final String userAgent;
  final CoverArtTemporaryDirectoryProvider temporaryDirectoryProvider;
  final int maximumBytes;
  final int maximumRedirects;
  final Duration inactivityTimeout;
  final Duration overallTimeout;

  static Future<Directory> _systemTemporaryDirectory() async =>
      Directory.systemTemp;

  Future<CoverArtDownloadResult> download(
    Uri initialUri, {
    CoverArtCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final operationToken = CoverArtCancellationToken();
    final unsubscribe = cancellationToken?.onCancel(operationToken.cancel);

    try {
      return await _download(initialUri, cancellationToken: operationToken);
    } on TimeoutException {
      operationToken.cancel();
      rethrow;
    } finally {
      unsubscribe?.call();
    }
  }

  Future<CoverArtDownloadResult> _download(
    Uri initialUri, {
    required CoverArtCancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    final agent = userAgent.trim();

    if (agent.isEmpty) {
      throw const CoverArtDownloadException(
        'A non-empty User-Agent is required.',
      );
    }

    final clock = Stopwatch()..start();
    var uri = _validateUri(initialUri);

    for (var redirectCount = 0; ; redirectCount++) {
      cancellationToken.throwIfCancelled();
      final pendingResponse = transport.get(
        uri,
        headers: {
          'User-Agent': agent,
          'Accept': 'image/jpeg, image/png, image/webp',
        },
        cancellationToken: cancellationToken,
      );

      var abandoned = false;

      unawaited(
        pendingResponse.then<void>((lateResponse) {
          if (abandoned || cancellationToken.isCancelled) {
            unawaited(_cancelResponse(lateResponse).catchError((Object _) {}));
          }
        }, onError: (Object _, StackTrace _) {}),
      );

      late final CoverArtBinaryResponse response;

      try {
        response = await pendingResponse.timeout(_remaining(clock));
      } catch (_) {
        abandoned = true;
        rethrow;
      }

      if (cancellationToken.isCancelled) {
        await _cancelResponse(response);
        throw const CoverArtCancelledException();
      }

      if (_isRedirect(response.statusCode)) {
        await _cancelResponse(response);

        if (redirectCount >= maximumRedirects) {
          throw const CoverArtDownloadException('Too many artwork redirects.');
        }

        final location = response.location;

        if (location == null || location.trim().isEmpty) {
          throw const CoverArtDownloadException(
            'Artwork redirect has no destination.',
          );
        }

        uri = _validateUri(uri.resolve(location));
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        await _cancelResponse(response);
        throw CoverArtDownloadException(
          'Artwork request failed with HTTP ${response.statusCode}.',
        );
      }

      if (response.contentLength != null &&
          response.contentLength! > maximumBytes) {
        await _cancelResponse(response);
        throw const CoverArtDownloadException(
          'Artwork exceeds the maximum download size.',
        );
      }

      cancellationToken.throwIfCancelled();
      final temporaryRoot = await temporaryDirectoryProvider();
      final directory = await temporaryRoot.createTemp('sonus_cover_art_');

      final partialFile = File(
        '${directory.path}${Platform.pathSeparator}artwork.download',
      );

      IOSink? sink;

      try {
        cancellationToken.throwIfCancelled();
        sink = partialFile.openWrite();

        final signature = BytesBuilder(copy: false);
        var total = 0;

        final iterator = StreamIterator<List<int>>(response.bytes);

        try {
          while (true) {
            final remaining = _remaining(clock);
            final wait = remaining < inactivityTimeout
                ? remaining
                : inactivityTimeout;

            final hasChunk = await _moveNext(iterator, wait, cancellationToken);
            cancellationToken.throwIfCancelled();

            if (!hasChunk) {
              break;
            }

            _remaining(clock);

            final chunk = iterator.current;
            total += chunk.length;

            if (total > maximumBytes) {
              throw const CoverArtDownloadException(
                'Artwork exceeds the maximum download size.',
              );
            }

            if (signature.length < 12) {
              final needed = 12 - signature.length;
              signature.add(
                chunk.length <= needed ? chunk : chunk.sublist(0, needed),
              );
            }

            sink.add(chunk);
          }
        } finally {
          await iterator.cancel();
        }

        cancellationToken.throwIfCancelled();
        _remaining(clock);

        await sink.flush();
        await sink.close();
        sink = null;

        final format = _detectFormat(signature.toBytes());

        if (format == null) {
          throw const CoverArtDownloadException(
            'Downloaded content is not a supported image.',
          );
        }

        final imageFile = File(
          '${directory.path}${Platform.pathSeparator}'
          'artwork.${format.extension}',
        );

        cancellationToken.throwIfCancelled();
        await partialFile.rename(imageFile.path);
        cancellationToken.throwIfCancelled();

        return CoverArtDownloadResult(
          filePath: imageFile.path,
          temporaryDirectoryPath: directory.path,
          format: format,
          byteLength: total,
        );
      } catch (_) {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {
            // Preserve the original download failure.
          }
        }

        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }

        rethrow;
      }
    }
  }

  Future<bool> _moveNext(
    StreamIterator<List<int>> iterator,
    Duration wait,
    CoverArtCancellationToken? token,
  ) {
    final operation = iterator.moveNext().timeout(wait);

    if (token == null) {
      return operation;
    }

    token.throwIfCancelled();

    return Future.any<bool>([
      operation,
      token.whenCancelled.then<bool>(
        (_) => throw const CoverArtCancelledException(),
      ),
    ]);
  }

  Duration _remaining(Stopwatch clock) {
    final remaining = overallTimeout - clock.elapsed;

    if (remaining <= Duration.zero) {
      throw TimeoutException('Overall artwork download deadline exceeded.');
    }

    return remaining;
  }

  static Future<void> _cancelResponse(CoverArtBinaryResponse response) async {
    final subscription = response.bytes.listen((_) {});
    await subscription.cancel();
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  static Uri _validateUri(Uri uri) {
    final host = uri.host.toLowerCase();

    final trusted =
        host == 'coverartarchive.org' ||
        host.endsWith('.coverartarchive.org') ||
        host == 'archive.org' ||
        host.endsWith('.archive.org');

    if (uri.scheme != 'https' ||
        !trusted ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443) {
      throw const CoverArtDownloadException(
        'Artwork URL is not a trusted HTTPS destination.',
      );
    }

    return uri;
  }

  static CoverArtImageFormat? _detectFormat(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return CoverArtImageFormat.jpeg;
    }

    const png = [137, 80, 78, 71, 13, 10, 26, 10];

    if (bytes.length >= 8 &&
        List.generate(
          8,
          (i) => bytes[i] == png[i],
        ).every((matches) => matches)) {
      return CoverArtImageFormat.png;
    }

    if (bytes.length >= 12 &&
        bytes[0] == 82 &&
        bytes[1] == 73 &&
        bytes[2] == 70 &&
        bytes[3] == 70 &&
        bytes[8] == 87 &&
        bytes[9] == 69 &&
        bytes[10] == 66 &&
        bytes[11] == 80) {
      return CoverArtImageFormat.webp;
    }

    return null;
  }
}
