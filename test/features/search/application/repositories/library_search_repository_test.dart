import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/search/application/models/library_search_results.dart';
import 'package:sonus_next/features/search/application/repositories/library_search_repository.dart';

void main() {
  test('LibrarySearchRepository exposes grouped library search', () async {
    final repository = _FakeLibrarySearchRepository();

    final results = await repository.search('query');

    expect(repository.lastQuery, 'query');
    expect(results.isEmpty, isTrue);
  });
}

class _FakeLibrarySearchRepository implements LibrarySearchRepository {
  String? lastQuery;

  @override
  Future<LibrarySearchResults> search(String query) async {
    lastQuery = query;
    return const LibrarySearchResults();
  }
}
