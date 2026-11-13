import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_crop_service.dart';
import '../../../artwork/domain/entities/artwork_crop.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../player/presentation/controllers/playback_shuffle_mode.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/album_edition_track_ordering_service.dart';
import '../../domain/repositories/album_edition_disc_label_repository.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../../domain/entities/song.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';

class AlbumProfileController extends ChangeNotifier with PlaybackShuffleMode {
  AlbumProfileController({
    required LibraryQueryRepository repository,
    required String albumId,
    String? initialEditionId,
    PlaybackCoordinator? playbackCoordinator,
    AlbumProfileEditingService? albumProfileEditingService,
    AlbumEditionTrackOrderingService? albumEditionTrackOrderingService,
    SongArtistCreditRepository? songArtistCreditRepository,
    TrackProfileEditingService? trackProfileEditingService,
    SongBlockService? songBlockService,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    ArtworkCropService? artworkCropService,
    AlbumEditionDiscLabelRepository? discLabelRepository,
    Random? random,
  }) : this._(
         repository,
         albumId,
         playbackCoordinator,
         albumProfileEditingService,
         albumEditionTrackOrderingService,
         songArtistCreditRepository,
         trackProfileEditingService,
         songBlockService,
         artworkAssignmentService,
         artworkFilePicker,
         artworkCropService,
         random ?? Random(),
         initialEditionId,
         discLabelRepository,
       );

  AlbumProfileController._(
    this._repository,
    this._albumId,
    this._playbackCoordinator,
    this._albumProfileEditingService,
    this._albumEditionTrackOrderingService,
    this._songArtistCreditRepository,
    this._trackProfileEditingService,
    this._songBlockService,
    this._artworkAssignmentService,
    this._artworkFilePicker,
    this._artworkCropService,
    this._random,
    this._initialEditionId,
    this._discLabelRepository,
  ) {
    watchPlaybackShuffle();
  }

  final LibraryQueryRepository _repository;
  final String _albumId;
  final PlaybackCoordinator? _playbackCoordinator;
  final AlbumProfileEditingService? _albumProfileEditingService;
  final AlbumEditionTrackOrderingService? _albumEditionTrackOrderingService;
  final SongArtistCreditRepository? _songArtistCreditRepository;
  final TrackProfileEditingService? _trackProfileEditingService;
  final SongBlockService? _songBlockService;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
  final ArtworkCropService? _artworkCropService;
  final Random _random;

  /// The edition to open on, such as the one a linked song is on. If it is
  /// not one of this album's editions, the primary edition opens instead.
  final String? _initialEditionId;

  /// Disc names (REF-13c); without it discs are shown by number only.
  final AlbumEditionDiscLabelRepository? _discLabelRepository;

  LibraryAlbum? _album;
  List<LibraryAlbumEdition> _editions = const [];
  LibraryAlbumEdition? _selectedEdition;
  List<LibraryTrack> _tracks = const [];
  Map<int, String> _discLabels = const {};

  /// The selected edition's disc names, by disc number (REF-13c).
  Map<int, String> get discLabels => _discLabels;

  bool _isLoading = false;
  Object? _error;

  String get albumId => _albumId;

  LibraryAlbum? get album => _album;

  List<LibraryAlbumEdition> get editions => _editions;

  LibraryAlbumEdition? get selectedEdition => _selectedEdition;

  bool get hasEditionQueryCapability =>
      _repository is AlbumEditionQueryRepository;
  List<LibraryTrack> get tracks => _tracks;

  /// The cover shown for the selected edition. Each edition keeps its own
  /// cover (SN-45); an edition without one shows the album's primary cover.
  String? get artworkPath {
    final editionPath = _selectedEdition?.artworkPath?.trim();

    if (editionPath != null && editionPath.isNotEmpty) {
      return editionPath;
    }

    final primaryPath = _editions
        .where((edition) => edition.isPrimary)
        .firstOrNull
        ?.artworkPath
        ?.trim();

    if (primaryPath != null && primaryPath.isNotEmpty) {
      return primaryPath;
    }

    final path = _album?.artworkPath?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return path;
  }

  /// Whether the selected edition has a cover of its own.
  bool get selectedEditionHasOwnArtwork {
    final editionPath = _selectedEdition?.artworkPath?.trim();
    return editionPath != null && editionPath.isNotEmpty;
  }

  /// The edition that artwork changes apply to: the one on screen, or the
  /// primary edition when editions cannot be read.
  String? get _artworkEditionId {
    final selected = _selectedEdition?.editionId.trim();

    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    final primary = _album?.primaryEditionId?.trim();
    return primary == null || primary.isEmpty ? null : primary;
  }

  bool canEditAlbumProfile(String? userId) {
    final primaryEditionId = _album?.primaryEditionId;

    return _albumProfileEditingService != null &&
        primaryEditionId != null &&
        primaryEditionId.trim().isNotEmpty;
  }

  /// Keeps the current owner as the user's choice. False when it can't.
  Future<bool> confirmOwner() async {
    final service = _albumProfileEditingService;
    if (service == null || _album == null) return false;
    await service.confirmOwner(albumId: _albumId);
    return true;
  }

  Future<bool> updateProfile({
    String? userId,
    required String title,
    required String editionTitle,
    required AlbumEditionType editionType,
    required DateTime? releaseDate,
    required String? genre,
    ReleaseDatePrecision? releaseDatePrecision,
    String? artistId,
  }) async {
    final service = _albumProfileEditingService;
    final album = _album;
    final primaryEditionId = album?.primaryEditionId;

    if (service == null ||
        album == null ||
        primaryEditionId == null ||
        primaryEditionId.trim().isEmpty) {
      return false;
    }

    await service.updateProfile(
      userId: userId,
      albumId: _albumId,
      primaryEditionId: primaryEditionId,
      title: title,
      editionTitle: editionTitle,
      editionType: editionType,
      releaseDate: releaseDate,
      releaseDatePrecision: releaseDatePrecision,
      genre: genre,
      artistId: artistId,
    );

    await refresh();

    return true;
  }

  /// Sets the selected edition's own release date (SN-50 A-Q6C), or the
  /// primary edition's when editions cannot be read. Null clears it.
  Future<bool> updateSelectedEditionReleaseDate({
    String? userId,
    required ReleaseDate? releaseDate,
  }) async {
    final service = _albumProfileEditingService;
    final editionId =
        _selectedEdition?.editionId ?? _album?.primaryEditionId?.trim();

    if (service == null || editionId == null || editionId.isEmpty) {
      return false;
    }

    await service.updateEditionReleaseDate(
      userId: userId,
      editionId: editionId,
      releaseDate: releaseDate?.instant,
      releaseDatePrecision: releaseDate?.precision,
    );

    await refresh();

    return true;
  }

  bool get canEditArtwork {
    final primaryEditionId = _album?.primaryEditionId;

    return _artworkAssignmentService != null &&
        _artworkFilePicker != null &&
        primaryEditionId != null &&
        primaryEditionId.trim().isNotEmpty;
  }

  bool get canEditTrackArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
  }

  bool canEditAlbumStudio(String? userId) {
    return _albumEditionTrackOrderingService != null &&
        _selectedEdition != null &&
        _repository is AlbumEditionQueryRepository;
  }

  Future<bool> reorderSelectedEdition({
    String? userId,
    required List<String> orderedSongIds,
    bool autoRenumber = false,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;

    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository) {
      return false;
    }

    final result = await service.reorderEdition(
      albumEditionId: selectedEdition.editionId,
      orderedSongIds: orderedSongIds,
      userId: userId,
      autoRenumber: autoRenumber,
    );

    if (!result.changed) {
      return false;
    }

    await refresh();

    return true;
  }

  /// "Sort by disc & track" for the selected edition: back to automatic
  /// order. Returns false when nothing changed.
  Future<bool> sortSelectedEditionByDiscAndTrack({String? userId}) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;

    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository) {
      return false;
    }

    final result = await service.sortByDiscAndTrack(
      albumEditionId: selectedEdition.editionId,
      userId: userId,
    );

    if (!result.changed) {
      return false;
    }

    await refresh();

    return true;
  }

  /// Saves [track]'s placement on the selected edition. Returns null when
  /// nothing changed.
  Future<AlbumEditionTrackPlacementResult?>
  updateSelectedEditionTrackPlacement({
    String? userId,
    required LibraryTrack track,
    required int discNumber,
    required int trackNumber,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;

    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository ||
        track.albumEditionId != selectedEdition.editionId) {
      return null;
    }

    final result = await service.updateTrackPlacement(
      userId: userId,
      albumEditionId: selectedEdition.editionId,
      songId: track.songId,
      discNumber: discNumber,
      trackNumber: trackNumber,
    );

    if (!result.changed) {
      return null;
    }

    await refresh();

    return result;
  }

  Future<List<SongArtistCredit>> getTrackAdditionalCredits(
    String songId,
  ) async {
    final repository = _songArtistCreditRepository;

    if (repository == null) {
      return const [];
    }

    final credits = await repository.getBySongId(songId);

    final additionalCredits =
        credits
            .where((credit) => credit.role != SongArtistCreditRole.primary)
            .toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position));

    return List<SongArtistCredit>.unmodifiable(additionalCredits);
  }

  bool canEditTrack(String? userId) {
    return _trackProfileEditingService != null;
  }

  Future<bool> updateTrack({
    String? userId,
    required LibraryTrack track,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
  }) async {
    final service = _trackProfileEditingService;

    if (service == null) {
      return false;
    }

    await service.updateTrack(
      userId: userId,
      songId: track.songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      featuredArtists: featuredArtists,
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
    );

    await refresh();

    return true;
  }

  Future<bool> updateTrackWithCredits({
    String? userId,
    required LibraryTrack track,
    required String title,
    required int trackNumber,
    required int discNumber,
    required Iterable<SongArtistCreditInput> additionalCredits,
    required bool isSingle,
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
    SongReleaseStatus releaseStatus = SongReleaseStatus.released,
    bool isLeak = false,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? placementEditionId,
  }) async {
    final service = _trackProfileEditingService;

    if (service == null) {
      return false;
    }

    final result = await service.updateTrackWithCredits(
      userId: userId,
      songId: track.songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      additionalCredits: additionalCredits,
      isSingle: isSingle,
      versionLabel: versionLabel,
      versionCharacteristics: versionCharacteristics,
      releaseStatus: releaseStatus,
      isLeak: isLeak,
      updateVersionMetadata: true,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      placementEditionId: placementEditionId,
    );

    await refresh();

    return result.changed;
  }

  /// Saves only [track]'s additional credits, at once, from Track Studio's
  /// credit editor (UI redesign E1), against the stored song and its stored
  /// primary artist; then reloads. Null without an editing service.
  Future<TrackCreditSaveResult?> saveTrackCredits({
    String? userId,
    required LibraryTrack track,
    required Iterable<SongArtistCreditInput> additionalCredits,
  }) async {
    final service = _trackProfileEditingService;

    if (service == null) {
      return null;
    }

    final result = await service.updateTrackCredits(
      userId: userId,
      songId: track.songId,
      expectedPrimaryArtistId: track.artistId,
      additionalCredits: additionalCredits,
    );

    if (result.changed) {
      await refresh();
    }

    return result;
  }

  bool canSetTrackBlocked(String? userId) {
    return _songBlockService != null;
  }

  Future<bool> setTrackBlocked({
    String? userId,
    required LibraryTrack track,
    required bool isBlocked,
  }) async {
    final service = _songBlockService;

    if (service == null) {
      return false;
    }

    final normalizedUserId = userId?.trim();

    await service.setBlocked(
      userId: normalizedUserId == null || normalizedUserId.isEmpty
          ? null
          : normalizedUserId,
      songId: track.songId,
      isBlocked: isBlocked,
    );

    if (isBlocked) {
      final playbackCoordinator = _playbackCoordinator;

      if (playbackCoordinator != null) {
        await playbackCoordinator.removeBlockedSongFromQueue(track.songId);
      }
    }

    await refresh();

    return true;
  }

  /// Whether covers can be cropped and repositioned (SN-45).
  bool get canCropArtwork => _artworkCropService != null && canEditArtwork;

  /// Lets the user choose an image; null when cancelled or unavailable.
  Future<String?> pickArtworkFile() async =>
      _artworkFilePicker?.pickArtworkFile();

  /// Crops [sourcePath] to [rect] and makes it the selected edition's
  /// cover. The original is kept so the crop can be moved or reset.
  Future<bool> applyArtworkCrop({
    required String sourcePath,
    required CropRect rect,
  }) async {
    final service = _artworkCropService;
    final editionId = _artworkEditionId;

    if (service == null || editionId == null) {
      return false;
    }

    await service.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: sourcePath,
      rect: rect,
    );

    await refresh();
    return true;
  }

  /// What "Reposition cover" opens for the selected edition, or null when
  /// it has no cover of its own.
  Future<ArtworkCropSource?> artworkRepositionSource() async {
    final service = _artworkCropService;
    final editionId = _artworkEditionId;
    final edition = _selectedEdition;

    if (service == null ||
        editionId == null ||
        edition == null ||
        !selectedEditionHasOwnArtwork) {
      return null;
    }

    return service.repositionSource(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      currentArtworkId: edition.artworkId,
      currentArtworkPath: edition.artworkPath,
    );
  }

  /// Restores the selected edition's full, uncropped original cover.
  Future<bool> resetArtworkCrop() async {
    final service = _artworkCropService;
    final editionId = _artworkEditionId;

    if (service == null || editionId == null) {
      return false;
    }

    final reset = await service.reset(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      currentArtworkId: _selectedEdition?.artworkId,
    );

    if (reset) {
      await refresh();
    }

    return reset;
  }

  /// Replaces the selected edition's cover. Other editions keep theirs.
  Future<bool> changeArtwork() async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;
    final editionId = _artworkEditionId;

    if (service == null || picker == null || editionId == null) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignAlbumEdition(
      albumEditionId: editionId,
      filePath: filePath,
    );

    await refresh();

    return true;
  }

  /// Clears the selected edition's own cover. Other editions keep theirs.
  Future<bool> clearArtwork() async {
    final service = _artworkAssignmentService;
    final editionId = _artworkEditionId;

    if (service == null || editionId == null) {
      return false;
    }

    await service.clearAlbumEdition(editionId);

    await refresh();

    return true;
  }

  Future<bool> changeTrackArtwork(LibraryTrack track) async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;
    final songId = track.songId.trim();

    if (service == null || picker == null || songId.isEmpty) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignSong(songId: songId, filePath: filePath);

    await refresh();

    return true;
  }

  Future<bool> clearTrackArtwork(LibraryTrack track) async {
    final service = _artworkAssignmentService;
    final songId = track.songId.trim();

    if (service == null || songId.isEmpty) {
      return false;
    }

    await service.clearSong(songId);

    await refresh();

    return true;
  }

  bool get isLoading => _isLoading;

  @override
  PlaybackCoordinator? get shufflePlayback => _playbackCoordinator;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isNotFound {
    return !_isLoading && _error == null && _album == null;
  }

  bool get hasPlayableTracks {
    return _tracks.any(_isPlayable);
  }

  int get totalDurationSeconds {
    var total = 0;

    for (final track in _tracks) {
      if (track.durationSeconds > 0) {
        total += track.durationSeconds;
      }
    }

    return total;
  }

  Duration get totalDuration {
    return Duration(seconds: totalDurationSeconds);
  }

  int get playableTrackCount {
    var count = 0;

    for (final track in _tracks) {
      if (_isPlayable(track)) {
        count++;
      }
    }

    return count;
  }

  int get unavailableTrackCount {
    return _tracks.where((track) => !_isAvailable(track)).length;
  }

  bool get hasUnavailableTracks {
    return unavailableTrackCount > 0;
  }

  int get editionCount {
    if (_editions.isNotEmpty) {
      return _editions.length;
    }

    return _tracks.map((track) => track.albumEditionId).toSet().length;
  }

  bool get hasMultipleEditions {
    return editionCount > 1;
  }

  List<String> get editionTitles {
    if (_editions.isNotEmpty) {
      return List<String>.unmodifiable(
        _editions
            .map((edition) => edition.title.trim())
            .where((title) => title.isNotEmpty),
      );
    }

    final editionIds = <String>{};
    final titles = <String>[];

    for (final track in _tracks) {
      if (!editionIds.add(track.albumEditionId)) {
        continue;
      }

      final title = track.albumEditionTitle.trim();

      if (title.isNotEmpty) {
        titles.add(title);
      }
    }

    return List<String>.unmodifiable(titles);
  }

  /// Each load and each edition switch takes the next number. A result is
  /// applied only while its number is still the latest, so an older, slower
  /// read can never undo a newer choice (App Update 1.2, PATCH-01: a
  /// refresh started before a tap used to finish after it and switch the
  /// edition back).
  int _viewRequest = 0;

  /// The edition most recently chosen, while its songs are still being
  /// read. Null once the view shows it.
  String? _pendingEditionId;

  bool _disposed = false;

  /// The edition the selector shows: the one most recently chosen, even
  /// before its songs have been read. Everything else on the page follows
  /// [selectedEdition], which changes together with its songs.
  String? get chosenEditionId =>
      _pendingEditionId ?? _selectedEdition?.editionId;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final request = ++_viewRequest;
    _isLoading = true;
    _error = null;
    _notify();

    try {
      final view = await _readView(
        _pendingEditionId ?? _selectedEdition?.editionId ?? _initialEditionId,
      );
      if (request != _viewRequest) return;
      _apply(view);
    } catch (error, stackTrace) {
      if (request != _viewRequest) return;
      developer.log(
        'Album $_albumId could not be loaded (${error.runtimeType})',
        name: 'sonus.library.album_profile',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      _pendingEditionId = null;
      _error = error;
    } finally {
      if (request == _viewRequest) {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// Reads the album, its editions and the songs, disc names of the
  /// edition to show: [preferredEditionId] when it is still one of them.
  Future<_AlbumView> _readView(String? preferredEditionId) async {
    final album = await _repository.getAlbumById(_albumId);
    if (album == null) return const _AlbumView.missing();

    final Object repository = _repository;
    if (repository is AlbumEditionQueryRepository) {
      final editions = await repository.getAlbumEditions(_albumId);
      if (editions.isNotEmpty) {
        final edition = _chooseEdition(
          editions,
          preferredEditionId: preferredEditionId,
          primaryEditionId: album.primaryEditionId,
        );
        final tracks = await repository.getTracksByAlbumEditionId(
          edition.editionId,
        );
        return _AlbumView(
          album: album,
          editions: editions,
          edition: edition,
          tracks: tracks,
          discLabels: await _labelsOf(edition.editionId),
        );
      }
    }
    return _AlbumView(
      album: album,
      editions: const [],
      edition: null,
      tracks: await _repository.getTracksByAlbumId(_albumId),
      discLabels: const {},
    );
  }

  /// Shows [view] all at once: the edition never changes without its songs.
  void _apply(_AlbumView view) {
    _album = view.album;
    _editions = view.editions;
    _selectedEdition = view.edition;
    _tracks = view.tracks;
    _discLabels = view.discLabels;
    _pendingEditionId = null;
  }

  Future<void> refresh() {
    return load();
  }

  /// [editionId]'s disc names. They are an extra: one that cannot be read
  /// leaves the discs shown by number.
  Future<Map<int, String>> _labelsOf(String editionId) async {
    final labels = _discLabelRepository;
    if (labels == null) return const {};
    try {
      return {
        for (final label in await labels.getByEditionId(editionId))
          label.discNumber: label.label,
      };
    } on Object {
      return const {};
    }
  }

  /// Lays out the selected edition as [placements] says: its order, each
  /// song's disc and automatic numbering (REF-13). Null when nothing
  /// changed or editing is unavailable.
  Future<AlbumEditionArrangeResult?> arrangeSelectedEdition({
    String? userId,
    required List<EditionPlacement> placements,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;
    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository) {
      return null;
    }

    final result = await service.arrangeEdition(
      albumEditionId: selectedEdition.editionId,
      placements: placements,
      userId: userId,
    );
    await refresh();
    return result.changed ? result : null;
  }

  /// Deletes [disc] of the selected edition (PATCH-02): [placements] is
  /// the edition afterwards and [removeSongIds] the listings it no longer
  /// has. One transaction; null when editing is unavailable. Throws
  /// [DiscDeletionException] when refused, with nothing changed.
  Future<DiscDeletionResult?> deleteSelectedEditionDisc({
    required int disc,
    required List<EditionPlacement> placements,
    Set<String> removeSongIds = const {},
    String? userId,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;
    if (service == null || selectedEdition == null) return null;

    final result = await service.deleteDisc(
      albumEditionId: selectedEdition.editionId,
      discNumber: disc,
      placements: placements,
      removeSongIds: removeSongIds,
      userId: userId,
    );
    await refresh();
    return result;
  }

  /// Names [disc] of the selected edition, or clears its name when [label]
  /// is blank (REF-13c).
  Future<bool> setSelectedEditionDiscLabel({
    required int disc,
    required String? label,
    String? userId,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;
    if (service == null || selectedEdition == null) return false;

    await service.setDiscLabel(
      albumEditionId: selectedEdition.editionId,
      discNumber: disc,
      label: label,
      userId: userId,
    );
    final labels = await _labelsOf(selectedEdition.editionId);
    // Another edition may have been chosen meanwhile: never show these
    // names on it.
    if (_selectedEdition?.editionId == selectedEdition.editionId) {
      _discLabels = labels;
      _notify();
    }
    return true;
  }

  /// Shows [editionId]. The selector moves at once ([chosenEditionId]); the
  /// edition's songs, disc names, date and cover follow together when read.
  /// The latest choice always wins, whatever order the reads finish in.
  /// Only reads: no edition is changed.
  ///
  /// False when [editionId] is not one of this album's editions or could
  /// not be read; the edition on screen then stays. True otherwise, also
  /// when a later choice has since replaced this one.
  Future<bool> selectEdition(String editionId) async {
    if (_repository is! AlbumEditionQueryRepository) return false;

    final id = editionId.trim();
    if (!_editions.any((edition) => edition.editionId == id)) return false;
    if (id == chosenEditionId) return true;

    final request = ++_viewRequest;
    _pendingEditionId = id;
    _notify();

    try {
      final view = await _readView(id);
      if (request != _viewRequest) return true;
      _apply(view);
      _isLoading = false;
      _notify();
      return true;
    } catch (error, stackTrace) {
      if (request != _viewRequest) return true;
      developer.log(
        'Edition $id of album $_albumId could not be read '
        '(${error.runtimeType}); the edition on screen stays',
        name: 'sonus.library.album_profile',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      _pendingEditionId = null;
      _isLoading = false;
      _notify();
      return false;
    }
  }

  LibraryAlbumEdition _chooseEdition(
    List<LibraryAlbumEdition> editions, {
    String? preferredEditionId,
    String? primaryEditionId,
  }) {
    final normalizedPreferredEditionId = preferredEditionId?.trim();

    if (normalizedPreferredEditionId != null &&
        normalizedPreferredEditionId.isNotEmpty) {
      for (final edition in editions) {
        if (edition.editionId == normalizedPreferredEditionId) {
          return edition;
        }
      }
    }

    final normalizedPrimaryEditionId = primaryEditionId?.trim();

    if (normalizedPrimaryEditionId != null &&
        normalizedPrimaryEditionId.isNotEmpty) {
      for (final edition in editions) {
        if (edition.editionId == normalizedPrimaryEditionId) {
          return edition;
        }
      }
    }

    for (final edition in editions) {
      if (edition.isPrimary) {
        return edition;
      }
    }

    return editions.first;
  }

  Future<void> playTrack(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    final startIndex = _tracks.indexWhere(
      (candidate) => candidate.songId == track.songId,
    );

    if (startIndex == -1) {
      await playbackCoordinator.playTrack(track);
      return;
    }

    await playbackCoordinator.playTracks(_tracks, startIndex: startIndex);
  }

  Future<void> playAll() async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || _tracks.isEmpty) {
      return;
    }

    final playableIndexes = <int>[];

    for (var index = 0; index < _tracks.length; index++) {
      if (_isPlayable(_tracks[index])) {
        playableIndexes.add(index);
      }
    }

    if (playableIndexes.isEmpty) {
      return;
    }

    final startIndex = isShuffleEnabled
        ? playableIndexes[_random.nextInt(playableIndexes.length)]
        : playableIndexes.first;

    await playbackCoordinator.playTracks(_tracks, startIndex: startIndex);
  }

  Future<void> playNext(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    await playbackCoordinator.playNext(track);
  }

  Future<void> addToQueue(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    await playbackCoordinator.addToQueue(track);
  }

  bool isTrackPlayable(LibraryTrack track) {
    return _isPlayable(track);
  }

  bool _isAvailable(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  bool _isPlayable(LibraryTrack track) {
    return !track.isBlocked && _isAvailable(track);
  }
}

/// One consistent read of the album page: an edition with its own songs
/// and disc names.
class _AlbumView {
  const _AlbumView({
    required this.album,
    required this.editions,
    required this.edition,
    required this.tracks,
    required this.discLabels,
  });

  const _AlbumView.missing()
    : album = null,
      editions = const [],
      edition = null,
      tracks = const [],
      discLabels = const {};

  final LibraryAlbum? album;
  final List<LibraryAlbumEdition> editions;
  final LibraryAlbumEdition? edition;
  final List<LibraryTrack> tracks;
  final Map<int, String> discLabels;
}
