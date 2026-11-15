import '../../../../core/events/library_change_signal.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../domain/entities/release_date.dart';
import '../../domain/entities/song_single_presentation.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/repositories/song_single_presentation_repository.dart';

/// Edits a song's Single presentation (App Update 1.3, REF-1.3-04): the
/// release date, the dedicated cover and whether charts and Moments may
/// show it, each on its own.
///
/// Never touches the song, its Single designation, its album, its edition
/// dates or covers, or any history. Clearing the cover only unlinks it: the
/// artwork itself stays (other records may use it).
class SongSinglePresentationService {
  SongSinglePresentationService({
    required this._presentations,
    required this._songs,
    this._artwork,
    LibraryChangeSignal? changes,
    DateTime Function()? now,
  }) : _changes = changes ?? LibraryChangeSignal.shared,
       _now = now ?? DateTime.now;

  final SongSinglePresentationRepository _presentations;
  final SongRepository _songs;
  final ArtworkAssignmentService? _artwork;
  final LibraryChangeSignal _changes;
  final DateTime Function() _now;

  /// Whether a cover can be chosen (managed artwork storage is available).
  bool get canAssignArtwork => _artwork != null;

  Future<SongSinglePresentation?> load(String songId) =>
      _presentations.getBySongId(songId);

  /// Every presentation, by Song ID.
  Future<Map<String, SongSinglePresentation>> loadAll() =>
      _presentations.getAll();

  /// Sets or clears the single's release date.
  Future<SongSinglePresentation> setReleaseDate(
    String songId,
    ReleaseDate? date,
  ) => _update(
    songId,
    (current, now) => date == null
        ? current.copyWith(clearReleaseDate: true, updatedAt: now)
        : current.copyWith(releaseDate: date, updatedAt: now),
  );

  /// Copies [filePath] into managed artwork and makes it the single cover.
  Future<SongSinglePresentation> assignArtwork(
    String songId,
    String filePath,
  ) async {
    final artwork = _artwork;
    if (artwork == null) {
      throw StateError('Artwork storage is unavailable.');
    }
    await _requireSong(songId);
    final asset = await artwork.resolveArtworkAsset(filePath: filePath);
    return _update(
      songId,
      (current, now) => current.copyWith(
        artworkId: asset.id,
        artworkPath: asset.filePath,
        updatedAt: now,
      ),
    );
  }

  /// Unlinks the single cover; the artwork asset is kept.
  Future<SongSinglePresentation> clearArtwork(String songId) => _update(
    songId,
    (current, now) => current.copyWith(
      clearArtwork: true,
      useArtworkInCharts: false,
      updatedAt: now,
    ),
  );

  /// Whether charts and Moments may show the single cover.
  Future<SongSinglePresentation> setUseArtworkInCharts(
    String songId, {
    required bool value,
  }) => _update(
    songId,
    (current, now) =>
        current.copyWith(useArtworkInCharts: value, updatedAt: now),
  );

  Future<SongSinglePresentation> _update(
    String songId,
    SongSinglePresentation Function(SongSinglePresentation, DateTime) change,
  ) async {
    await _requireSong(songId);
    final now = _now().toUtc();
    final current =
        await _presentations.getBySongId(songId) ??
        SongSinglePresentation(songId: songId, createdAt: now, updatedAt: now);
    final next = change(current, now);
    await _presentations.save(next);
    _changes.notify(LibraryChangeKind.libraryEdited);
    return next;
  }

  Future<void> _requireSong(String songId) async {
    if (await _songs.getById(songId) == null) {
      throw StateError('Song not found: $songId');
    }
  }
}
