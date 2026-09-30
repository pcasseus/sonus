// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../application/models/playlist_summary.dart';
import '../../application/services/playlist_service.dart';

class PlaylistsController extends ChangeNotifier {
  PlaylistsController({required PlaylistService service}) : _service = service;

  final PlaylistService _service;

  List<PlaylistSummary> _playlists = const [];
  bool _isLoading = false;
  bool _isMutating = false;
  Object? _error;

  int _requestGeneration = 0;

  List<PlaylistSummary> get playlists => _playlists;

  bool get isLoading => _isLoading;

  bool get isMutating => _isMutating;

  bool get isBusy => _isLoading || _isMutating;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isEmpty => !_isLoading && _error == null && _playlists.isEmpty;

  Future<void> load() {
    if (_isLoading) {
      return Future<void>.value();
    }

    return _load();
  }

  Future<void> refresh() => _load();

  Future<bool> createPlaylist(String name) async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.createPlaylist(name: name);
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> renamePlaylist({
    required String playlistId,
    required String name,
  }) async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.renamePlaylist(playlistId: playlistId, name: name);

      await _reloadAfterMutation();
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> deletePlaylist(String playlistId) async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deletePlaylist(playlistId);
      await _reloadAfterMutation();
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final playlists = await _service.getPlaylists();

      if (generation != _requestGeneration) {
        return;
      }

      _playlists = List<PlaylistSummary>.unmodifiable(playlists);
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reloadAfterMutation() async {
    _requestGeneration++;

    _playlists = List<PlaylistSummary>.unmodifiable(
      await _service.getPlaylists(),
    );
  }
}
