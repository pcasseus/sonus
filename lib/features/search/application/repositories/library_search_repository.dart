import '../models/library_search_results.dart';

abstract interface class LibrarySearchRepository {
  Future<LibrarySearchResults> search(String query);
}
