import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';

void main() {
  test('starts active and completes cancellation signal', () async {
    final token = CoverArtCancellationToken();

    expect(token.isCancelled, isFalse);
    token.throwIfCancelled();

    token.cancel();

    await token.whenCancelled;
    expect(token.isCancelled, isTrue);
    expect(token.throwIfCancelled, throwsA(isA<CoverArtCancelledException>()));
  });

  test('notifies listeners exactly once', () {
    final token = CoverArtCancellationToken();
    var calls = 0;

    token.onCancel(() => calls++);

    token.cancel();
    token.cancel();

    expect(calls, 1);
  });

  test('supports unsubscribing before cancellation', () {
    final token = CoverArtCancellationToken();
    var calls = 0;

    final unsubscribe = token.onCancel(() => calls++);
    unsubscribe();

    token.cancel();

    expect(calls, 0);
  });

  test('immediately notifies late subscribers', () {
    final token = CoverArtCancellationToken();
    token.cancel();

    var calls = 0;
    token.onCancel(() => calls++);

    expect(calls, 1);
  });

  test('listener failures do not block other listeners', () {
    final token = CoverArtCancellationToken();
    var completed = false;

    token.onCancel(() => throw StateError('Listener failed'));
    token.onCancel(() => completed = true);

    token.cancel();

    expect(completed, isTrue);
    expect(token.isCancelled, isTrue);
  });

  test('independent tokens do not affect each other', () {
    final first = CoverArtCancellationToken();
    final second = CoverArtCancellationToken();

    first.cancel();

    expect(first.isCancelled, isTrue);
    expect(second.isCancelled, isFalse);
    second.throwIfCancelled();
  });
}
