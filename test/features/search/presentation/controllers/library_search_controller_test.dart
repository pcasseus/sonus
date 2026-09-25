import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/search/application/models/library_search_results.dart';
import 'package:sonus_next/features/search/application/repositories/library_search_repository.dart';
import 'package:sonus_next/features/search/presentation/controllers/library_search_controller.dart';

void main() {
  group('LibrarySearchController', () {
    test('starts empty', () {
      final controller = LibrarySearchController(
        repository: _FakeSearchRepository(),
      );

      expect(controller.query, isEmpty);
      expect(controller.results.isEmpty, isTrue);
      expect(controller.isSearching, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.hasQuery, isFalse);
      expect(controller.hasResults, isFalse);
      expect(controller.showEmptyState, isFalse);

      controller.dispose();
    });

    test('blank query clears results without searching', () async {
      final repository = _FakeSearchRepository(
        result: const LibrarySearchResults(),
      );

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: Duration.zero,
      );

      controller.updateQuery('   ');

      await Future<void>.delayed(Duration.zero);

      expect(repository.queries, isEmpty);
      expect(controller.query, '   ');
      expect(controller.hasQuery, isFalse);
      expect(controller.isSearching, isFalse);
      expect(controller.results.isEmpty, isTrue);

      controller.dispose();
    });

    test('debounces search requests', () async {
      final repository = _FakeSearchRepository();

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: const Duration(milliseconds: 30),
      );

      controller.updateQuery('m');
      controller.updateQuery('ma');
      controller.updateQuery('mad');

      expect(controller.isSearching, isTrue);
      expect(repository.queries, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(repository.queries, ['mad']);
      expect(controller.isSearching, isFalse);

      controller.dispose();
    });

    test('exposes successful search results', () async {
      final expected = const LibrarySearchResults();

      final repository = _FakeSearchRepository(result: expected);

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: Duration.zero,
      );

      controller.updateQuery('query');

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(repository.queries, ['query']);
      expect(controller.results, same(expected));
      expect(controller.isSearching, isFalse);
      expect(controller.hasError, isFalse);

      controller.dispose();
    });

    test('reports repository error', () async {
      final repository = _FakeSearchRepository(
        error: StateError('search failed'),
      );

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: Duration.zero,
      );

      controller.updateQuery('query');

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isSearching, isFalse);
      expect(controller.results.isEmpty, isTrue);

      controller.dispose();
    });

    test('retry repeats current query after failure', () async {
      final repository = _SequencedSearchRepository();

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: Duration.zero,
      );

      controller.updateQuery('query');

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.hasError, isTrue);

      await controller.retry();

      expect(repository.queries, ['query', 'query']);
      expect(controller.hasError, isFalse);
      expect(controller.isSearching, isFalse);

      controller.dispose();
    });

    test('clear resets query, state, error and results', () async {
      final repository = _FakeSearchRepository(
        error: StateError('search failed'),
      );

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: Duration.zero,
      );

      controller.updateQuery('query');

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.clear();

      expect(controller.query, isEmpty);
      expect(controller.hasQuery, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.isSearching, isFalse);
      expect(controller.results.isEmpty, isTrue);

      controller.dispose();
    });

    test('ignores stale results from an older query', () async {
      final first = Completer<LibrarySearchResults>();
      final second = Completer<LibrarySearchResults>();

      final repository = _CompleterSearchRepository(
        completers: [first, second],
      );

      final controller = LibrarySearchController(
        repository: repository,
        debounceDuration: Duration.zero,
      );

      controller.updateQuery('first');

      await Future<void>.delayed(Duration.zero);

      controller.updateQuery('second');

      await Future<void>.delayed(Duration.zero);

      second.complete(const LibrarySearchResults());

      await Future<void>.delayed(Duration.zero);

      expect(controller.query, 'second');
      expect(controller.isSearching, isFalse);

      first.complete(const LibrarySearchResults());

      await Future<void>.delayed(Duration.zero);

      expect(controller.query, 'second');
      expect(repository.queries, ['first', 'second']);

      controller.dispose();
    });
  });
}

class _FakeSearchRepository implements LibrarySearchRepository {
  _FakeSearchRepository({
    this.result = const LibrarySearchResults(),
    this.error,
  });

  final LibrarySearchResults result;
  final Object? error;

  final List<String> queries = [];

  @override
  Future<LibrarySearchResults> search(String query) async {
    queries.add(query);

    if (error != null) {
      throw error!;
    }

    return result;
  }
}

class _SequencedSearchRepository implements LibrarySearchRepository {
  final List<String> queries = [];

  int _calls = 0;

  @override
  Future<LibrarySearchResults> search(String query) async {
    queries.add(query);
    _calls++;

    if (_calls == 1) {
      throw StateError('first search fails');
    }

    return const LibrarySearchResults();
  }
}

class _CompleterSearchRepository implements LibrarySearchRepository {
  _CompleterSearchRepository({required this.completers});

  final List<Completer<LibrarySearchResults>> completers;

  final List<String> queries = [];

  int _index = 0;

  @override
  Future<LibrarySearchResults> search(String query) {
    queries.add(query);

    final completer = completers[_index];
    _index++;

    return completer.future;
  }
}
