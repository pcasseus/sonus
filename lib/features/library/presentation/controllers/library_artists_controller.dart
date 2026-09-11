import 'package:flutter/foundation.dart';

import '../../application/models/library_artist.dart';
import '../../application/repositories/library_query_repository.dart';

class LibraryArtistsController extends ChangeNotifier {
  factory LibraryArtistsController({
    required LibraryQueryRepository repository,
  }) {
    return LibraryArtistsController._(repository);
  }

  LibraryArtistsController._(this._repository);

  final LibraryQueryRepository _repository;

  List<LibraryArtist> _artists = const [];

  bool _isLoading = false;
  Object? _error;

  List<LibraryArtist> get artists => _artists;

  bool get isLoading => _isLoading;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isEmpty => !_isLoading && _artists.isEmpty;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _artists = await _repository.getArtists();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() {
    return load();
  }
}
