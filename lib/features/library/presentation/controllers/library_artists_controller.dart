import 'package:flutter/foundation.dart';

import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
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
  List<LibraryAlbum> _albums = const [];
  List<LibraryTrack> _tracks = const [];

  bool _isLoading = false;
  Object? _error;

  List<LibraryArtist> get artists => _artists;

  List<LibraryAlbum> get albums => _albums;

  List<LibraryTrack> get tracks => _tracks;

  bool get isLoading => _isLoading;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isEmpty => !_isLoading && _artists.isEmpty;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait<Object>([
        _repository.getArtists(),
        _repository.getAlbums(),
        _repository.getTracks(),
      ]);

      _artists = results[0] as List<LibraryArtist>;
      _albums = results[1] as List<LibraryAlbum>;
      _tracks = results[2] as List<LibraryTrack>;
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
