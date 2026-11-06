import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/library_organization_service.dart';
import '../../../../core/state/dispose_safe_notifier.dart';

class LibraryArtistsController extends ChangeNotifier with DisposeSafeNotifier {
  factory LibraryArtistsController({
    required LibraryQueryRepository repository,
    LibraryOrganizationService? organization,
  }) {
    return LibraryArtistsController._(repository, organization);
  }

  LibraryArtistsController._(this._repository, this._organizationService);

  final LibraryQueryRepository _repository;

  /// Soundtrack grouping and "Assign to Project"; every artist is shown
  /// without it.
  final LibraryOrganizationService? _organizationService;
  ArtistLibraryOrganization? _organization;

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

  /// Whether the artist has its own Library entry. Grouped performers are
  /// listed under their project's collaborators instead; their profiles,
  /// credits and search results are unchanged.
  bool isShownInLibrary(String artistId) =>
      _organization?.isShownInLibrary(artistId) ?? true;

  /// The artists the Library lists, in [artists] order: those with a
  /// playable track of their own, or on an album they own, that have their
  /// own Library entry ([isShownInLibrary]). Computed once per load.
  List<LibraryArtist> get visibleArtists =>
      _visibleArtists ??= _computeVisibleArtists();
  List<LibraryArtist>? _visibleArtists;

  List<LibraryArtist> _computeVisibleArtists() {
    final albumOwnerById = {
      for (final album in _albums) album.albumId: album.artistId,
    };
    final withPlayableMusic = <String>{};
    for (final track in _tracks) {
      if (!_hasAvailableMedia(track)) continue;
      withPlayableMusic.add(track.artistId);
      final owner = albumOwnerById[track.albumId];
      if (owner != null) withPlayableMusic.add(owner);
    }
    return List.unmodifiable([
      for (final artist in _artists)
        if (withPlayableMusic.contains(artist.artistId) &&
            isShownInLibrary(artist.artistId))
          artist,
    ]);
  }

  static bool _hasAvailableMedia(LibraryTrack track) =>
      track.isAvailable &&
      track.filePath != null &&
      track.filePath!.trim().isNotEmpty;

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
      _organization = await _loadOrganization();
      _visibleArtists = null;
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fails open: if organization can't be read, every artist is shown.
  Future<ArtistLibraryOrganization?> _loadOrganization() async {
    final service = _organizationService;
    if (service == null) return null;

    try {
      return await service.load();
    } catch (error, stackTrace) {
      developer.log(
        'Library organization could not be read (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> refresh() {
    return load();
  }
}
