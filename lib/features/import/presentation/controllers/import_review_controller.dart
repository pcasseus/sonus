import 'package:flutter/foundation.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/services/album_profile_editing_service.dart';
import '../../../library/application/services/song_artist_credit_service.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/song_artist_credit.dart';
import '../../../library/domain/entities/release_date.dart';
import '../../application/models/import_review_queue_item.dart';
import '../../application/services/import_review_service.dart';
import '../../application/services/possible_recording_review_service.dart';
import '../../domain/models/pending_possible_recording.dart';

class ImportReviewController extends ChangeNotifier {
  ImportReviewController({
    required ImportReviewService service,
    required String? userId,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    AlbumProfileEditingService? albumProfileEditingService,
  }) : this._(
         service,
         userId?.trim(),
         artworkAssignmentService,
         artworkFilePicker,
         albumProfileEditingService,
       );

  ImportReviewController._(
    this._service,
    this._userId,
    this._artworkAssignmentService,
    this._artworkFilePicker,
    this._albumProfileEditingService,
  );

  final ImportReviewService _service;
  final String? _userId;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
  final AlbumProfileEditingService? _albumProfileEditingService;

  List<ImportReviewQueueItem> _items = const [];
  List<PossibleRecordingItem> _possibleRecordings = const [];
  final Set<String> _deferredRecordings = {};
  List<LibraryArtist> _artists = const [];
  List<LibraryAlbum> _albums = const [];
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUpdatingArtwork = false;
  bool _isUpdatingAlbumArtwork = false;
  bool _isUpdatingAlbum = false;
  bool _isCreatingArtist = false;
  bool _isHandlingRecording = false;
  Object? _error;

  List<ImportReviewQueueItem> get items => _items;

  /// Possible different recordings still waiting, without those left for
  /// later on this visit.
  List<PossibleRecordingItem> get possibleRecordings => [
    for (final item in _possibleRecordings)
      if (!_deferredRecordings.contains(item.entry.normalizedPath)) item,
  ];

  bool get isHandlingRecording => _isHandlingRecording;

  List<LibraryArtist> get artists => _artists;

  List<LibraryAlbum> get albums => _albums;

  ImportReviewQueueItem? get currentItem {
    if (_items.isEmpty) {
      return null;
    }

    return _items[_currentIndex];
  }

  int get currentPosition => _items.isEmpty ? 0 : _currentIndex + 1;

  bool get canGoPrevious => _currentIndex > 0;

  bool get canGoNext => _currentIndex + 1 < _items.length;

  int get remainingCount => _items.length;

  bool get isLoading => _isLoading;

  bool get isSaving => _isSaving;

  bool get isUpdatingArtwork => _isUpdatingArtwork;

  bool get isUpdatingAlbum => _isUpdatingAlbum;
  bool get isCreatingArtist => _isCreatingArtist;

  LibraryAlbum? get currentAlbum {
    final item = currentItem;

    if (item == null) {
      return null;
    }

    final albumId = item.track.albumId.trim();

    for (final album in _albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  bool get canEditAlbum {
    final album = currentAlbum;

    if (album == null || _albumProfileEditingService == null) {
      return false;
    }

    final editionId = album.primaryEditionId?.trim();
    return editionId != null && editionId.isNotEmpty;
  }

  bool get isUpdatingAlbumArtwork => _isUpdatingAlbumArtwork;

  bool get canEditAlbumArtwork {
    final album = currentAlbum;

    if (album == null ||
        _artworkAssignmentService == null ||
        _artworkFilePicker == null) {
      return false;
    }

    final editionId = album.primaryEditionId?.trim();
    return editionId != null && editionId.isNotEmpty;
  }

  bool get canEditArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
  }

  bool get isBusy =>
      _isLoading ||
      _isSaving ||
      _isUpdatingArtwork ||
      _isUpdatingAlbumArtwork ||
      _isUpdatingAlbum ||
      _isCreatingArtist ||
      _isHandlingRecording;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isComplete =>
      !_isLoading &&
      _items.isEmpty &&
      possibleRecordings.isEmpty &&
      _error == null;

  Future<void> load() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _items = await _service.getUnresolved();
      _currentIndex = 0;
      await _refreshPossibleRecordings();
      _artists = await _service.getArtists();
      _albums = await _service.getAlbums();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshPossibleRecordings() async {
    try {
      _possibleRecordings =
          await _service.possibleRecordings?.pending() ?? const [];
    } catch (_) {
      // The device-local list never blocks the song reviews.
      _possibleRecordings = const [];
    }
  }

  /// Imports a possible different recording as its own song, after the
  /// service checks the file again.
  Future<PossibleRecordingActionResult?> importRecordingSeparately(
    PendingPossibleRecording entry,
  ) {
    return _handleRecording((service) async {
      final result = await service.importSeparately(entry);

      if (result.outcome == PossibleRecordingOutcome.imported ||
          result.outcome == PossibleRecordingOutcome.handledByImport) {
        try {
          // The new song joins the songs to review.
          await _refreshItems(preferredSongId: currentItem?.track.songId);
        } catch (_) {
          // The import stands; the list refreshes on the next visit.
        }
      }

      return result;
    });
  }

  /// Records that the file is the same recording as its song.
  Future<bool> keepAsSameRecording(PendingPossibleRecording entry) async {
    final result = await _handleRecording((service) async {
      await service.markSameRecording(entry);
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.stillPending,
      );
    });

    return result != null;
  }

  /// Leaves the file for later; it stays listed for the next visit.
  void deferRecording(PendingPossibleRecording entry) {
    if (isBusy) return;

    _deferredRecordings.add(entry.normalizedPath);
    notifyListeners();
  }

  /// Null when nothing ran or the action failed.
  Future<PossibleRecordingActionResult?> _handleRecording(
    Future<PossibleRecordingActionResult> Function(
      PossibleRecordingReviewService service,
    )
    action,
  ) async {
    final service = _service.possibleRecordings;

    if (service == null || isBusy) return null;

    _isHandlingRecording = true;
    notifyListeners();

    try {
      return await action(service);
    } catch (_) {
      return null;
    } finally {
      await _refreshPossibleRecordings();
      _isHandlingRecording = false;
      notifyListeners();
    }
  }

  Future<void> _refreshItems({
    String? preferredSongId,
    int? fallbackIndex,
  }) async {
    final refreshedItems = await _service.getUnresolved();

    if (refreshedItems.isEmpty) {
      _items = refreshedItems;
      _currentIndex = 0;
      return;
    }

    if (preferredSongId != null) {
      final preferredIndex = refreshedItems.indexWhere(
        (item) => item.track.songId == preferredSongId,
      );

      if (preferredIndex >= 0) {
        _items = refreshedItems;
        _currentIndex = preferredIndex;
        return;
      }
    }

    final targetIndex = fallbackIndex ?? _currentIndex;

    _items = refreshedItems;
    _currentIndex = targetIndex.clamp(0, refreshedItems.length - 1);
  }

  void goPrevious() {
    if (isBusy || !canGoPrevious) {
      return;
    }

    _currentIndex--;
    _error = null;
    notifyListeners();
  }

  void goNext() {
    if (isBusy || !canGoNext) {
      return;
    }

    _currentIndex++;
    _error = null;
    notifyListeners();
  }

  Future<bool> changeCurrentArtwork() async {
    final item = currentItem;
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;

    if (item == null || isBusy || service == null || picker == null) {
      return false;
    }

    final songId = item.track.songId.trim();

    if (songId.isEmpty) {
      return false;
    }

    _isUpdatingArtwork = true;
    notifyListeners();

    try {
      final filePath = await picker.pickArtworkFile();

      if (filePath == null) {
        return false;
      }

      await service.assignSong(songId: songId, filePath: filePath);

      await _refreshItems(preferredSongId: songId);

      return true;
    } finally {
      _isUpdatingArtwork = false;
      notifyListeners();
    }
  }

  Future<bool> clearCurrentArtwork() async {
    final item = currentItem;
    final service = _artworkAssignmentService;

    if (item == null || isBusy || service == null) {
      return false;
    }

    final songId = item.track.songId.trim();

    if (songId.isEmpty) {
      return false;
    }

    _isUpdatingArtwork = true;
    notifyListeners();

    try {
      await service.clearSong(songId);

      await _refreshItems(preferredSongId: songId);

      return true;
    } finally {
      _isUpdatingArtwork = false;
      notifyListeners();
    }
  }

  Future<bool> changeCurrentAlbumArtwork() async {
    final album = currentAlbum;
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;

    if (album == null || service == null || picker == null || isBusy) {
      return false;
    }

    final primaryEditionId = album.primaryEditionId?.trim();

    if (primaryEditionId == null || primaryEditionId.isEmpty) {
      return false;
    }

    _isUpdatingAlbumArtwork = true;
    notifyListeners();

    try {
      final filePath = await picker.pickArtworkFile();

      if (filePath == null) {
        return false;
      }

      await service.assignAlbumEdition(
        albumEditionId: primaryEditionId,
        filePath: filePath,
      );

      // Artwork cleanup must not resolve the song review.
      await _refreshItems(preferredSongId: currentItem?.track.songId);
      _albums = await _service.getAlbums();

      return true;
    } finally {
      _isUpdatingAlbumArtwork = false;
      notifyListeners();
    }
  }

  Future<bool> clearCurrentAlbumArtwork() async {
    final album = currentAlbum;
    final service = _artworkAssignmentService;

    if (album == null || service == null || isBusy) {
      return false;
    }

    final primaryEditionId = album.primaryEditionId?.trim();

    if (primaryEditionId == null || primaryEditionId.isEmpty) {
      return false;
    }

    _isUpdatingAlbumArtwork = true;
    notifyListeners();

    try {
      await service.clearAlbumEdition(primaryEditionId);

      // Artwork cleanup must not resolve the song review.
      await _refreshItems(preferredSongId: currentItem?.track.songId);
      _albums = await _service.getAlbums();

      return true;
    } finally {
      _isUpdatingAlbumArtwork = false;
      notifyListeners();
    }
  }

  Future<bool> updateCurrentAlbum({
    required String title,
    required String artistId,
    required String editionTitle,
    required AlbumEditionType editionType,
    required DateTime? releaseDate,
    required String? genre,
    ReleaseDatePrecision? releaseDatePrecision,
  }) async {
    final album = currentAlbum;
    final service = _albumProfileEditingService;

    if (album == null || service == null || isBusy) {
      return false;
    }

    final primaryEditionId = album.primaryEditionId?.trim();

    if (primaryEditionId == null || primaryEditionId.isEmpty) {
      return false;
    }

    _isUpdatingAlbum = true;
    notifyListeners();

    try {
      await service.updateProfile(
        userId: _userId,
        albumId: album.albumId,
        primaryEditionId: primaryEditionId,
        title: title,
        editionTitle: editionTitle,
        editionType: editionType,
        releaseDate: releaseDate,
        releaseDatePrecision: releaseDatePrecision,
        genre: genre,
        artistId: artistId,
      );

      // Album editing is contextual cleanup only. It must not resolve the
      // current song's import review.
      await _refreshItems(preferredSongId: currentItem?.track.songId);
      _artists = await _service.getArtists();
      _albums = await _service.getAlbums();

      return true;
    } finally {
      _isUpdatingAlbum = false;
      notifyListeners();
    }
  }

  Future<LibraryArtist?> createOrReuseArtist(String name) async {
    if (isBusy) {
      return null;
    }

    _isCreatingArtist = true;
    _error = null;
    notifyListeners();

    try {
      final artist = await _service.createOrReuseArtist(
        userId: _userId,
        name: name,
      );

      _artists = await _service.getArtists();

      return artist;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isCreatingArtist = false;
      notifyListeners();
    }
  }

  /// The current song's stored credits; throws when they cannot be read,
  /// so the editor never opens without them.
  Future<List<SongArtistCredit>> loadCurrentCredits() async {
    final item = currentItem;

    if (item == null) {
      return const [];
    }

    return _service.getCredits(item.track.songId);
  }

  Future<bool> resolveCurrent({
    required String title,
    required int trackNumber,
    required int discNumber,
    required Iterable<SongArtistCreditInput> additionalCredits,
    required bool isSingle,
    required String artistId,
    required String albumId,
    String? moveToEditionId,
    String? placementEditionId,
  }) async {
    final item = currentItem;

    if (item == null || _isSaving) {
      return false;
    }

    final resolvedSongId = item.track.songId;
    final resolvedIndex = _currentIndex;

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await _service.updateTrackAndResolve(
        userId: _userId,
        item: item,
        title: title,
        trackNumber: trackNumber,
        discNumber: discNumber,
        additionalCredits: additionalCredits,
        isSingle: isSingle,
        artistId: artistId,
        albumId: albumId,
        moveToEditionId: moveToEditionId,
        placementEditionId: placementEditionId,
      );

      await _refreshItems(fallbackIndex: resolvedIndex);

      return true;
    } catch (error) {
      _error = error;

      try {
        await _refreshItems(
          preferredSongId: resolvedSongId,
          fallbackIndex: resolvedIndex,
        );
      } catch (_) {
        // Preserve the original resolve failure.
      }

      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
